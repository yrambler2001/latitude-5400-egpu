#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Puts the EDK2 UEFI Shell and the eGPU bring-up scripts on a FAT32 USB stick.

.DESCRIPTION
    - Downloads shellx64.efi from pbatard/UEFI-Shell and verifies its SHA256.
    - Renders uefi-shell\*.nsh.template with the values for your root port.
    - Writes everything to <Drive>:\EFI\shell\ . Nothing else on the stick is touched
      (an existing \EFI\BOOT, e.g. a Linux installer, keeps working).

.PARAMETER DriveLetter
    Drive letter of the USB stick (FAT32). Example: D

.PARAMETER Destination
    Render into this folder instead of a USB drive (to inspect or copy by hand).

.PARAMETER RootPort
    PCI address of the root port feeding the eGPU slot, as bus:device.function in hex.
    Latitude 5400 M.2 slot: 00:1D.0

.PARAMETER SecondaryBus
    Bus number (hex) the GPU appears on behind that root port. Check with the shell's
    `pci` command or Device Manager ("PCI bus N"). Latitude 5400: 02

.PARAMETER PcieCapOffset
    Offset (hex) of the PCI Express capability in the root port's config space.
    Intel PCH root ports: 40. The shell script prints and logs a check (expect 0x10).

.PARAMETER BridgeControl
    Original value (hex byte) of the root port Bridge Control register (0x3E), restored
    after the Secondary Bus Reset. Read it from a previous egpu-log.txt ("[1c]").
    Latitude 5400: 10

.PARAMETER WindowsEntryName
    Boot entry the scripts tell you to pick. Must match Set-BootConfig.ps1.

.EXAMPLE
    .\Install-UsbShell.ps1 -DriveLetter D
.EXAMPLE
    .\Install-UsbShell.ps1 -DriveLetter E -RootPort 00:1C.0 -SecondaryBus 03 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Drive')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Drive')] [ValidatePattern('^[A-Za-z]$')] [string] $DriveLetter,
    [Parameter(Mandatory, ParameterSetName = 'Folder')] [string] $Destination,
    [ValidatePattern('^[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}\.[0-7]$')] [string] $RootPort = '00:1D.0',
    [ValidatePattern('^[0-9A-Fa-f]{2}$')] [string] $SecondaryBus = '02',
    [ValidatePattern('^[0-9A-Fa-f]{2}$')] [string] $PcieCapOffset = '40',
    [ValidatePattern('^[0-9A-Fa-f]{2}$')] [string] $BridgeControl = '10',
    [string] $WindowsEntryName = 'Windows 11 (eGPU)',
    [string] $ShellReleaseTag = '26H1',
    [string] $ShellSha256 = '4EA080DDD576117CD04F5C02D16712EA5D9249C0752214D8E4055E460D7B11E0'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$templateDir = Join-Path $repoRoot 'uefi-shell'
$target = if ($Destination) { $Destination } else { "$($DriveLetter.ToUpper()):\EFI\shell" }

function ConvertTo-Hex2([int] $value) { '{0:X2}' -f ($value -band 0xFF) }
function ConvertFrom-Hex([string] $hex) { [Convert]::ToInt32($hex, 16) }

# --- sanity checks on the target drive (skipped with -Destination) --------------
if (-not $Destination) {
$vol = Get-Volume -DriveLetter $DriveLetter -ErrorAction SilentlyContinue
if (-not $vol) { throw "Drive ${DriveLetter}: not found." }
if ($vol.FileSystem -notmatch '^FAT') { throw "Drive ${DriveLetter}: is $($vol.FileSystem); UEFI firmware needs FAT32." }
$disk = Get-Partition -DriveLetter $DriveLetter | Get-Disk
if ($disk.IsBoot -or $disk.IsSystem) { throw "Drive ${DriveLetter}: is on the system/boot disk. Use a separate USB stick." }
Write-Host "Target: $($disk.FriendlyName) ($([math]::Round($disk.Size/1GB,1)) GB, $($disk.BusType)) -> $target"
}

# --- compute token values ---------------------------------------------------------
$bus, $devfn = $RootPort.Split(':'); $dev, $fn = $devfn.Split('.')
$cap = ConvertFrom-Hex $PcieCapOffset
$lctlEn = 0x40   # Common Clock Configuration on, ASPM off
$tokens = [ordered]@{
    '{{RP}}'        = ('0000{0}{1}{2}' -f $bus.ToUpper(), $dev.ToUpper(), ('{0:X2}' -f [int]$fn))
    '{{RP_PCI}}'    = ('{0} {1} {2:X2}' -f $bus.ToUpper(), $dev.ToUpper(), [int]$fn)
    '{{SECBUS}}'    = $SecondaryBus.ToUpper()
    '{{CAP}}'       = ConvertTo-Hex2 $cap
    '{{LCTL}}'      = ConvertTo-Hex2 ($cap + 0x10)
    '{{LSTA}}'      = ConvertTo-Hex2 ($cap + 0x12)
    '{{LCTL2}}'     = ConvertTo-Hex2 ($cap + 0x30)
    '{{BCTL_ORIG}}' = $BridgeControl.ToUpper()
    '{{BCTL_SBR}}'  = ConvertTo-Hex2 ((ConvertFrom-Hex $BridgeControl) -bor 0x40)
    '{{LCTL_EN}}'   = ConvertTo-Hex2 $lctlEn
    '{{LCTL_DIS}}'  = ConvertTo-Hex2 ($lctlEn -bor 0x10)
    '{{LCTL_RT}}'   = ConvertTo-Hex2 ($lctlEn -bor 0x20)
    '{{WIN_ENTRY}}' = $WindowsEntryName
}
if (($cap + 0x30) -gt 0xFF) { throw "PcieCapOffset $PcieCapOffset puts Link Control 2 beyond 0xFF; mm -pci only addresses 0x00-0xFF." }
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

# --- render templates --------------------------------------------------------------
$rendered = @{}
foreach ($name in 'startup.nsh', 'win.nsh') {
    $text = Get-Content (Join-Path $templateDir "$name.template") -Raw
    foreach ($t in $tokens.GetEnumerator()) { $text = $text.Replace($t.Key, $t.Value) }
    if ($text -match '\{\{[A-Z_0-9]+\}\}') { throw "Unrendered token in ${name}: $($Matches[0])" }
    $rendered[$name] = ($text -replace "`r?`n", "`r`n")
}

# --- write to the stick --------------------------------------------------------------
if ($PSCmdlet.ShouldProcess($target, 'Write shellx64.efi, startup.nsh, win.nsh')) {
    New-Item -ItemType Directory -Force $target | Out-Null
    Copy-Item $tmp (Join-Path $target 'shellx64.efi') -Force
    foreach ($kv in $rendered.GetEnumerator()) {
        [IO.File]::WriteAllText((Join-Path $target $kv.Key), $kv.Value, [Text.Encoding]::ASCII)
    }
    Get-ChildItem $target | Format-Table Name, Length, LastWriteTime -AutoSize
    if ($DriveLetter) { Write-Host "Done. Next: .\Set-BootConfig.ps1 -UsbDriveLetter $DriveLetter" -ForegroundColor Green }
}
