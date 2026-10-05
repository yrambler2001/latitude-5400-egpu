#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Creates the Windows boot entry the eGPU method needs.

.DESCRIPTION
    Copies the current Windows boot entry and sets `usefirmwarepcisettings No` on the copy, so
    Windows re-plans PCI resources itself at boot (and sizes the eGPU root-port window).
    Your normal entry is left untouched as a fallback.

    The USB stick needs no boot entry: Install-UsbShell.ps1 puts the shell at
    \EFI\BOOT\BOOTX64.EFI, which the firmware boots when you pick the stick in F12.

    The BCD store is exported first. The created ID is saved to a state file so
    Remove-BootConfig.ps1 can undo exactly what was created.

.EXAMPLE
    .\Set-BootConfig.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $WindowsEntryName = 'Windows 11 (eGPU)',
    [string] $StateDir = (Join-Path $env:ProgramData 'latitude-5400-egpu')
)

$ErrorActionPreference = 'Stop'
$statePath = Join-Path $StateDir 'state.json'

function Invoke-Bcd {
    param([Parameter(ValueFromRemainingArguments)] [string[]] $BcdArgs)
    $out = & bcdedit.exe @BcdArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "bcdedit $($BcdArgs -join ' ') failed: $out" }
    $out
}

if (Test-Path $statePath) {
    throw "State file $statePath exists; the entry was already created. Run Remove-BootConfig.ps1 first."
}

if ($PSCmdlet.ShouldProcess('BCD store', "Export backup, create '$WindowsEntryName' (usefirmwarepcisettings No)")) {
    New-Item -ItemType Directory -Force $StateDir | Out-Null
    $backup = Join-Path $StateDir ("bcd-backup-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Invoke-Bcd /export $backup | Out-Null
    Write-Host "BCD exported to $backup"

    $out = Invoke-Bcd /copy '{current}' /d $WindowsEntryName
    $win = [regex]::Match(($out -join ' '), '\{[0-9a-fA-F-]{36}\}').Value
    if (-not $win) { throw "Could not parse a GUID from: $out" }
    Invoke-Bcd /set $win usefirmwarepcisettings no | Out-Null
    Write-Host "Created '$WindowsEntryName' $win (usefirmwarepcisettings No)"

    [ordered]@{ created = (Get-Date).ToString('s'); windowsEntry = $win; bcdBackup = $backup } |
        ConvertTo-Json | Set-Content -Path $statePath -Encoding UTF8
    Write-Host "State saved to $statePath" -ForegroundColor Green
}
