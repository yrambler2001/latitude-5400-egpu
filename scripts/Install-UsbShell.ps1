#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Makes a FAT32 USB stick that boots straight into the EDK2 UEFI Shell and runs the eGPU
    bring-up scripts.

.DESCRIPTION
    - Downloads shellx64.efi from pbatard/UEFI-Shell and verifies its SHA256.
    - Installs it as \EFI\BOOT\BOOTX64.EFI, the file UEFI firmware starts when you pick the
      stick in the one-time boot menu (F12 on Dell). No custom boot entry is needed.
    - Renders uefi-shell\*.nsh.template for your root port into \EFI\shell\ and generates
      gen1.nsh .. gen4.nsh (speed choices).
    - Installs a launcher startup.nsh in \EFI\BOOT\ and the stick root.

    An existing \EFI\BOOT\BOOTX64.EFI (e.g. a Linux installer) is only replaced with
    -ReplaceBootloader, and is then kept as BOOTX64.EFI.orig.

.PARAMETER DriveLetter
    Drive letter of the USB stick (FAT32). Example: D

.PARAMETER Destination
    Render the stick layout into this folder instead (to inspect, or copy by hand).

.PARAMETER RootPort
    PCI address of the root port feeding the eGPU slot, as bus:device.function in hex.
    Latitude 5400 M.2 slot: 00:1D.0

.PARAMETER SecondaryBus
    Bus number (hex) the GPU appears on behind that root port. Latitude 5400: 02

.PARAMETER PcieCapOffset
    Offset (hex) of the PCI Express capability in the root port's config space.
    Intel PCH root ports: 40. The shell script prints and logs a check (expect 0x10).

.PARAMETER WindowsEntryName
    Boot entry the scripts tell you to pick. Must match Set-BootConfig.ps1.

.PARAMETER ReplaceBootloader
    Allow replacing an existing \EFI\BOOT\BOOTX64.EFI that is not this shell.

.EXAMPLE
    .\Install-UsbShell.ps1 -DriveLetter D
.EXAMPLE
    .\Install-UsbShell.ps1 -Destination .\out -RootPort 00:1C.4 -SecondaryBus 05
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Drive')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Drive')] [ValidatePattern('^[A-Za-z]$')] [string] $DriveLetter,
    [Parameter(Mandatory, ParameterSetName = 'Folder')] [string] $Destination,
    [ValidatePattern('^[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}\.[0-7]$')] [string] $RootPort = '00:1D.0',
    [ValidatePattern('^[0-9A-Fa-f]{2}$')] [string] $SecondaryBus = '02',
    [ValidatePattern('^[0-9A-Fa-f]{2}$')] [string] $PcieCapOffset = '40',
    [string] $WindowsEntryName = 'Windows 11 (eGPU)',
    [switch] $ReplaceBootloader,
    [string] $ShellReleaseTag = '26H1',
    [string] $ShellSha256 = '4EA080DDD576117CD04F5C02D16712EA5D9249C0752214D8E4055E460D7B11E0'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$templateDir = Join-Path $repoRoot 'uefi-shell'
$root = if ($Destination) { $Destination } else { "$($DriveLetter.ToUpper()):\" }
$bootDir = Join-Path $root 'EFI\BOOT'
$shellDir = Join-Path $root 'EFI\shell'

function ConvertTo-Hex2([int] $value) { '{0:X2}' -f ($value -band 0xFF) }

# --- sanity checks on the target drive (skipped with -Destination) --------------
if (-not $Destination) {
    $vol = Get-Volume -DriveLetter $DriveLetter -ErrorAction SilentlyContinue
    if (-not $vol) { throw "Drive ${DriveLetter}: not found." }
    if ($vol.FileSystem -notmatch '^FAT') { throw "Drive ${DriveLetter}: is $($vol.FileSystem); UEFI firmware needs FAT32." }
    $disk = Get-Partition -DriveLetter $DriveLetter | Get-Disk
    if ($disk.IsBoot -or $disk.IsSystem) { throw "Drive ${DriveLetter}: is on the system/boot disk. Use a separate USB stick." }
    Write-Host "Target: $($disk.FriendlyName) ($([math]::Round($disk.Size/1GB,1)) GB, $($disk.BusType)) -> $root"
}

# --- compute token values ---------------------------------------------------------
$bus, $devfn = $RootPort.Split(':'); $dev, $fn = $devfn.Split('.')
$cap = [Convert]::ToInt32($PcieCapOffset, 16)
if (($cap + 0x30) -gt 0xFF) { throw "PcieCapOffset $PcieCapOffset puts Link Control 2 beyond 0xFF; mm -pci only addresses 0x00-0xFF." }
$tokens = [ordered]@{
    '{{RP}}'        = ('0000{0}{1}{2:X2}' -f $bus.ToUpper(), $dev.ToUpper(), [int]$fn)
    '{{RP_PCI}}'    = ('{0} {1} {2:X2}' -f $bus.ToUpper(), $dev.ToUpper(), [int]$fn)
    '{{SECBUS}}'    = $SecondaryBus.ToUpper()
    '{{CAP}}'       = ConvertTo-Hex2 $cap
    '{{LSTA}}'      = ConvertTo-Hex2 ($cap + 0x12)
    '{{LCTL2}}'     = ConvertTo-Hex2 ($cap + 0x30)
    '{{WIN_ENTRY}}' = $WindowsEntryName
}
$tokens.GetEnumerator() | ForEach-Object { Write-Verbose ("{0,-14} = {1}" -f $_.Key, $_.Value) }

# --- download and verify the UEFI Shell -------------------------------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) "shellx64-$ShellReleaseTag.efi"
$url = "https://github.com/pbatard/UEFI-Shell/releases/download/$ShellReleaseTag/shellx64.efi"
if (-not (Test-Path $tmp) -or (Get-FileHash $tmp -Algorithm SHA256).Hash -ne $ShellSha256) {
    Write-Host "Downloading $url"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
}
$hash = (Get-FileHash $tmp -Algorithm SHA256).Hash
if ($hash -ne $ShellSha256.ToUpper()) {
    Remove-Item $tmp -Force
    throw "SHA256 mismatch for shellx64.efi. Expected $ShellSha256, got $hash. Refusing to install."
}
Write-Host "shellx64.efi SHA256 verified: $hash"

# --- existing bootloader on the stick? ------------------------------------------------
$bootEfi = Join-Path $bootDir 'BOOTX64.EFI'
$backupExisting = $false
if (Test-Path $bootEfi) {
    if ((Get-FileHash $bootEfi -Algorithm SHA256).Hash -ne $hash) {
        if (-not $ReplaceBootloader) {
            throw "$bootEfi already exists and is not this UEFI Shell (another bootloader?). Re-run with -ReplaceBootloader to replace it (it will be kept as BOOTX64.EFI.orig)."
        }
        $backupExisting = $true
    }
}

# --- render templates ----------------------------------------------------------------
function Render([string] $templateName) {
    $text = Get-Content (Join-Path $templateDir $templateName) -Raw
    foreach ($t in $tokens.GetEnumerator()) { $text = $text.Replace($t.Key, $t.Value) }
    if ($text -match '\{\{[A-Z_0-9]+\}\}') { throw "Unrendered token in ${templateName}: $($Matches[0])" }
    $text -replace "`r?`n", "`r`n"
}
$shellFiles = [ordered]@{}
foreach ($n in 'startup', 'flow', 'again', 'win') { $shellFiles["$n.nsh"] = Render "$n.nsh.template" }
foreach ($g in 1..4) {
    $warn = if ($g -eq 4) { "echo ""WARNING: Gen4 only works if both the root port and the GPU support 16 GT/s. If the link does not come up, power-cycle the PSU and use gen3 or lower.""`r`n" } else { '' }
    $shellFiles["gen$g.nsh"] = "@echo -off`r`n# Speed choice: Gen$g`r`n${warn}flow.nsh 0$g`r`n"
}
$launcher = Render 'launcher.nsh.template'

# --- write --------------------------------------------------------------------------------
if ($PSCmdlet.ShouldProcess($root, 'Install UEFI Shell as \EFI\BOOT\BOOTX64.EFI and write eGPU scripts')) {
    New-Item -ItemType Directory -Force $bootDir, $shellDir | Out-Null
    if ($backupExisting) {
        Copy-Item $bootEfi "$bootEfi.orig" -Force
        Write-Host "Existing bootloader kept as $bootEfi.orig"
    }
    Copy-Item $tmp $bootEfi -Force
    $ascii = [Text.Encoding]::ASCII
    [IO.File]::WriteAllText((Join-Path $bootDir 'startup.nsh'), $launcher, $ascii)
    [IO.File]::WriteAllText((Join-Path $root 'startup.nsh'), $launcher, $ascii)
    foreach ($kv in $shellFiles.GetEnumerator()) {
        [IO.File]::WriteAllText((Join-Path $shellDir $kv.Key), $kv.Value, $ascii)
    }
    $efiFull = (Get-Item (Join-Path $root 'EFI')).FullName
    Get-ChildItem $efiFull -Recurse -File | Select-Object @{ n = 'Path'; e = { '\EFI' + $_.FullName.Substring($efiFull.Length) } }, Length |
        Format-Table -AutoSize
    Write-Host "Done. Boot: F12 -> pick the USB stick. Next (once): .\Set-BootConfig.ps1" -ForegroundColor Green
}
