#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Creates the two boot entries the eGPU method needs.

.DESCRIPTION
    1. A copy of the current Windows boot entry with `usefirmwarepcisettings No`, so Windows
       re-plans PCI resources itself (and sizes the eGPU root-port window) at boot.
       Your normal entry is left untouched as a fallback.
    2. A firmware (F12) boot entry that starts \EFI\shell\shellx64.efi from the USB stick.

    The BCD store is exported first. The created IDs are saved to a state file so
    Remove-BootConfig.ps1 can undo exactly what was created.

.PARAMETER UsbDriveLetter
    Drive letter of the USB stick prepared by Install-UsbShell.ps1.

.EXAMPLE
    .\Set-BootConfig.ps1 -UsbDriveLetter D
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [ValidatePattern('^[A-Za-z]$')] [string] $UsbDriveLetter,
    [string] $WindowsEntryName = 'Windows 11 (eGPU)',
    [string] $ShellEntryName = 'UEFI Shell (eGPU)',
    [string] $StateDir = (Join-Path $env:ProgramData 'latitude-5400-egpu')
)

$ErrorActionPreference = 'Stop'
$statePath = Join-Path $StateDir 'state.json'
$shellPath = "$($UsbDriveLetter.ToUpper()):\EFI\shell\shellx64.efi"

function Invoke-Bcd {
    param([Parameter(ValueFromRemainingArguments)] [string[]] $BcdArgs)
    $out = & bcdedit.exe @BcdArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "bcdedit $($BcdArgs -join ' ') failed: $out" }
    $out
}
function Get-NewId($text) {
    $id = [regex]::Match(($text -join ' '), '\{[0-9a-fA-F-]{36}\}').Value
    if (-not $id) { throw "Could not parse a GUID from: $text" }
    $id
}

if (-not (Test-Path $shellPath)) { throw "$shellPath not found. Run Install-UsbShell.ps1 first." }
if (Test-Path $statePath) {
    throw "State file $statePath exists; entries were already created. Run Remove-BootConfig.ps1 first."
}

$state = [ordered]@{ created = (Get-Date).ToString('s'); windowsEntry = $null; shellEntry = $null; bcdBackup = $null }

if ($PSCmdlet.ShouldProcess('BCD store', "Export backup, create '$WindowsEntryName' and '$ShellEntryName'")) {
    New-Item -ItemType Directory -Force $StateDir | Out-Null
    $backup = Join-Path $StateDir ("bcd-backup-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Invoke-Bcd /export $backup | Out-Null
    $state.bcdBackup = $backup
    Write-Host "BCD exported to $backup"

    # 1) Windows entry with usefirmwarepcisettings No
    $win = Get-NewId (Invoke-Bcd /copy '{current}' /d $WindowsEntryName)
    Invoke-Bcd /set $win usefirmwarepcisettings no | Out-Null
    $state.windowsEntry = $win
    Write-Host "Created '$WindowsEntryName' $win (usefirmwarepcisettings No)"

    # 2) Firmware application entry for the UEFI Shell on the USB stick
    $sh = Get-NewId (Invoke-Bcd /copy '{bootmgr}' /d $ShellEntryName)
    Invoke-Bcd /set $sh device "partition=$($UsbDriveLetter.ToUpper()):" | Out-Null
    Invoke-Bcd /set $sh path '\EFI\shell\shellx64.efi' | Out-Null
    foreach ($v in 'default', 'displayorder', 'toolsdisplayorder', 'timeout', 'resumeobject', 'locale', 'inherit') {
        & bcdedit.exe /deletevalue $sh $v 2>&1 | Out-Null   # inherited from {bootmgr}; absent ones are fine
    }
    Invoke-Bcd /set '{fwbootmgr}' displayorder $sh /addlast | Out-Null
    $state.shellEntry = $sh
    Write-Host "Created firmware entry '$ShellEntryName' $sh -> $shellPath"

    $state | ConvertTo-Json | Set-Content -Path $statePath -Encoding UTF8
    Write-Host "State saved to $statePath" -ForegroundColor Green
    Write-Host "Boot with F12 -> '$ShellEntryName'; the shell script will tell you to pick '$WindowsEntryName'."
}
