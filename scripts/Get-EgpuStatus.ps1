<#
.SYNOPSIS
    Read-only status report for the eGPU: devices, root-port windows, link, PCIe errors,
    boot settings and the last UEFI Shell log run.

.PARAMETER RootPort
    PCI address of the eGPU root port (bus:device.function, hex). Latitude 5400: 00:1D.0

.PARAMETER LogPath
    Path to egpu-log.txt. Default: searches \EFI\shell\egpu-log.txt on removable drives.

.EXAMPLE
    .\Get-EgpuStatus.ps1
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}\.[0-7]$')] [string] $RootPort = '00:1D.0',
    [string] $LogPath
)

$ErrorActionPreference = 'Continue'
function Section($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Prop($id, $key) { (Get-PnpDeviceProperty -InstanceId $id -KeyName $key -ErrorAction SilentlyContinue).Data }
function Decode-LinkStatus([int] $v) {
    $speed = @{ 1 = '2.5 GT/s (Gen1)'; 2 = '5 GT/s (Gen2)'; 3 = '8 GT/s (Gen3)'; 4 = '16 GT/s (Gen4)' }[$v -band 0xF]
    '0x{0:X4}: speed {1}, width x{2}, training={3}, DLL-active={4}' -f $v, $speed, (($v -shr 4) -band 0x3F), (($v -shr 11) -band 1), (($v -shr 13) -band 1)
}

$bus, $devfn = $RootPort.Split(':'); $dev, $fn = $devfn.Split('.')
$location = 'PCI bus {0}, device {1}, function {2}' -f [Convert]::ToInt32($bus, 16), [Convert]::ToInt32($dev, 16), [int]$fn
$lastBoot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime

Section "Root port $RootPort"
$rp = Get-PnpDevice -Class System -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { (Prop $_.InstanceId 'DEVPKEY_Device_LocationInfo') -eq $location } | Select-Object -First 1
if (-not $rp) {
    Write-Host "No device at '$location'. Either the BIOS disabled the port (slot empty at POST) or the address is wrong." -ForegroundColor Yellow
} else {
    '{0}  status={1} present={2}' -f $rp.FriendlyName, $rp.Status, $rp.Present
    $cim = Get-CimInstance Win32_PnPEntity -Filter ("DeviceID='" + ($rp.InstanceId -replace '\\', '\\') + "'")
    'Memory windows:'
    Get-CimAssociatedInstance -InputObject $cim -ResultClassName Win32_DeviceMemoryAddress -ErrorAction SilentlyContinue |
        ForEach-Object { [pscustomobject]@{ S = [uint64]$_.StartingAddress; E = [uint64]$_.EndingAddress } } |
        Sort-Object S -Unique |
        ForEach-Object { '  0x{0:X} - 0x{1:X}  ({2:N2} MB)' -f $_.S, $_.E, (($_.E - $_.S + 1) / 1MB) }

    Section 'Devices behind the root port'
    $children = Prop $rp.InstanceId 'DEVPKEY_Device_Children'
    if (-not $children) { 'none' }
    foreach ($c in $children) {
        $d = Get-PnpDevice -InstanceId $c -ErrorAction SilentlyContinue
        '{0}' -f $d.FriendlyName
        '  status={0} problem={1} link=Gen{2} x{3} driver={4} {5}' -f $d.Status, (Prop $c 'DEVPKEY_Device_ProblemCode'),
            (Prop $c 'DEVPKEY_PciDevice_CurrentLinkSpeed'), (Prop $c 'DEVPKEY_PciDevice_CurrentLinkWidth'),
            (Prop $c 'DEVPKEY_Device_DriverProvider'), (Prop $c 'DEVPKEY_Device_DriverVersion')
    }
}

Section 'PCIe corrected/uncorrected errors (WHEA-Logger) for this root port'
$devId = if ($rp) { ($rp.InstanceId -split '\\')[1] } else { $null }
foreach ($range in @(@{ n = 'since boot'; t = $lastBoot }, @{ n = 'last 24 h'; t = (Get-Date).AddHours(-24) })) {
    $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $range.t } -ErrorAction SilentlyContinue)
    $mine = if ($devId) { @($ev | Where-Object { $_.Message -match [regex]::Escape($devId.Split('&')[1]) }) } else { $ev }
    '{0,-11}: {1} events ({2} total WHEA)' -f $range.n, $mine.Count, $ev.Count
}

Section 'Boot configuration'
$cur = (& bcdedit.exe /enum '{current}' 2>&1) -join "`n"
'current entry     : ' + ([regex]::Match($cur, 'description\s+(.+)').Groups[1].Value.Trim())
'usefirmwarepci   : ' + $(if ($cur -match 'usefirmwarepcisettings\s+(\w+)') { $Matches[1] } else { '(not set = Yes)' })
'Secure Boot       : ' + $(try { Confirm-SecureBootUEFI -ErrorAction Stop } catch { 'unknown (' + $_.Exception.Message + ')' })

Section 'Last UEFI Shell run (egpu-log.txt)'
if (-not $LogPath) {
    $LogPath = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Removable' } |
        ForEach-Object { "$($_.DriveLetter):\EFI\shell\egpu-log.txt" } | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $LogPath -or -not (Test-Path $LogPath)) { 'no log found' ; return }
$lines = Get-Content $LogPath
$start = ($lines | Select-String 'NEW RUN' | Select-Object -Last 1).LineNumber
$run = $lines[($start - 1)..($lines.Count - 1)]
"log: $LogPath  (run started line $start)"
$stage = ''
for ($i = 0; $i -lt $run.Count; $i++) {
    $l = $run[$i]
    if ($l -match '^\[(\w+)\]') { $stage = $Matches[1] }
    if ($l -match '^\d\d:\d\d:\d\d') { "time          : $l" }
    if ($l -match '^\[1b\]' -and $run[$i + 1] -match '^0x0?([0-9A-Fa-f])$') { "[1b] target   : Gen$([Convert]::ToInt32($Matches[1], 16))" }
    if ($l -match 'Bus \w\w Device 00 Func 00' -and $run[$i + 1] -match '00000000:\s+(\w\w) (\w\w) (\w\w) (\w\w)') {
        $vid = $Matches[2] + $Matches[1]; $did = $Matches[4] + $Matches[3]
        '[{0,-2}] endpoint : {1}' -f $stage, $(if ($vid -eq 'FFFF') { 'nothing answering (FFFF)' } else { "vendor $vid device $did" })
    }
    if ($l -match 'LinkCtl LinkSta|LinkSta:|LinkCtl\(0x50\)') {
        $vals = @($run[($i + 1)..($i + 3)] | Where-Object { $_ -match '^0x[0-9A-Fa-f]{4}$' })
        foreach ($v in $vals) { '[{0,-2}] LinkSta  : {1}' -f $stage, (Decode-LinkStatus ([Convert]::ToInt32($v.Substring(2), 16))) }
    }
}
