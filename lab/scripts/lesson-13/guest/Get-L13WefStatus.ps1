<#
    Runs on vm-wec-shared-001 through Run Command. Read-only: the WEF subscription's runtime status,
    the source side's latest forwarding events, the newest event in ForwardedEvents, and the Azure
    Monitor Agent service state.
#>
$name = '__SUBSCRIPTION__'
"--- runtime status"; wecutil gr $name
$op = Get-WinEvent -LogName 'Microsoft-Windows-Forwarding/Operational' -MaxEvents 2 -ErrorAction SilentlyContinue
foreach ($e in $op) { "--- forwarding log $($e.Id) at $($e.TimeCreated.ToUniversalTime().ToString('u')): $(($e.Message -replace '\s+', ' ').Substring(0, [Math]::Min(160, ($e.Message -replace '\s+', ' ').Length)))" }
$last = Get-WinEvent -LogName ForwardedEvents -MaxEvents 1 -ErrorAction SilentlyContinue
"--- newest ForwardedEvents record: $(if ($last) { "Id $($last.Id) RecordId $($last.RecordId) at $($last.TimeCreated.ToUniversalTime().ToString('o'))" } else { 'none' })"
$svc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'AzureMonitorAgent|MonAgent' } | Select-Object -First 1
"--- Azure Monitor Agent service: $(if ($svc) { "$($svc.Name) $($svc.Status)" } else { 'not found by name' })"
