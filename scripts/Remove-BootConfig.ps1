#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Removes the boot entries created by Set-BootConfig.ps1.

.DESCRIPTION
    Reads the state file written by Set-BootConfig.ps1 and deletes exactly those BCD
    entries. It does not touch anything else. See docs/cleanup.md for the other manual
    reverts (Secure Boot, USB stick).

.EXAMPLE
    .\Remove-BootConfig.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $StateDir = (Join-Path $env:ProgramData 'latitude-5400-egpu')
)

$ErrorActionPreference = 'Stop'
$statePath = Join-Path $StateDir 'state.json'
if (-not (Test-Path $statePath)) { throw "No state file at $statePath. Nothing recorded to remove." }
$state = Get-Content $statePath -Raw | ConvertFrom-Json

foreach ($id in @($state.windowsEntry, $state.shellEntry) | Where-Object { $_ }) {
    $exists = (& bcdedit.exe /enum $id 2>&1 | Out-String) -match [regex]::Escape($id)
    if (-not $exists) { Write-Host "$id already gone"; continue }
    if ($PSCmdlet.ShouldProcess($id, 'bcdedit /delete')) {
        $out = & bcdedit.exe /delete $id 2>&1
        if ($LASTEXITCODE -ne 0) { throw "bcdedit /delete $id failed: $out" }
        Write-Host "Deleted $id"
    }
}

if ($PSCmdlet.ShouldProcess($statePath, 'Remove state file')) {
    Remove-Item $statePath -Force
    Write-Host "Removed $statePath. BCD backup kept at $($state.bcdBackup)" -ForegroundColor Green
}
