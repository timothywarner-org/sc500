<#
.SYNOPSIS
    Reads both sides of WEF, including the source plugin channel that reports delivery failures.
.DESCRIPTION
    A collector's Active status alone is insufficient. Keep errors, log ACLs, and subscription
    details together so troubleshooting does not confuse an accepted subscription with delivery.
#>
$ErrorActionPreference = 'Continue'
wecutil gr '__SUBSCRIPTION__'
$channels = @(Get-WinEvent -ListLog '*Forward*','*EventCollector*' -ErrorAction SilentlyContinue)
$channels | Select-Object LogName,IsEnabled,RecordCount | Format-Table
foreach ($channel in @($channels.LogName)) {
    "CHANNEL $channel"
    Get-WinEvent -LogName $channel -MaxEvents 2 -ErrorAction SilentlyContinue | ForEach-Object {
        "$($_.TimeCreated.ToUniversalTime().ToString('o')) $($_.Id) $($_.Message -replace '\s+',' ')"
    }
}
"SECURITY CONFIG"; wevtutil gl Security
"FORWARDED CONFIG"; wevtutil gl ForwardedEvents
"SERVICE IDENTITIES"
Get-CimInstance Win32_Service | Where-Object Name -In @('WinRM','Wecsvc') | Select-Object Name,StartName,State | Format-Table
"READERS"
Get-LocalGroupMember 'Event Log Readers' | Select-Object Name,SID | Format-Table
