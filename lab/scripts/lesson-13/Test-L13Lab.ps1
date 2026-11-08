<#
.SYNOPSIS
    Read-only readiness check for the Lesson 13 lab. Exits 1 on any FAIL.
.DESCRIPTION
    Checks the workspace and Sentinel, the custom table's plan and retention, every data collection
    rule and association, the Activity log route, the two role-demo groups, the collectors' power
    state, and (with -Recording) that rows from every lab-owned route arrived in the last 24 hours.
    Recording also requires Entra and Microsoft 365 routes and delivered rows. Since the
    2026-11-06 move, this workspace is the tenant's only Sentinel workspace, so it's the primary
    in the Defender portal and XDR incidents land here (Lesson 14's incident came from Microsoft XDR).
    Without Recording, configuration and idle state are reported independently of delivery.
.PARAMETER Recording Also require running collectors, temporary egress, and fresh rows.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Test-L13Lab.ps1 -Recording
#>
[CmdletBinding()]
param([switch]$Recording)
. (Join-Path $PSScriptRoot 'L13.Common.ps1')
$cfg = $script:L13Config
[void](Assert-L13Context)
$results = [Collections.Generic.List[object]]::new()
function Add-Check([string]$Name, [string]$State, [string]$Detail) { $results.Add([pscustomobject]@{ Check = $Name; Result = $State; Detail = $Detail }) }

$lab = Get-L13Outputs
$n = $cfg.names
$ws = Invoke-L13Rest -AllowNotFound -Path "$($lab.workspaceId)?api-version=2023-09-01"
Add-Check 'Workspace' $(if ($ws -and $ws.properties.retentionInDays -eq $cfg.workspace.retentionInDays) { 'PASS' } else { 'FAIL' }) "$($lab.workspace), $($ws.properties.retentionInDays) days"
$onb = Invoke-L13Rest -AllowNotFound -Path "$($lab.workspaceId)/providers/Microsoft.SecurityInsights/onboardingStates/default?api-version=2024-09-01"
Add-Check 'Sentinel enabled' $(if ($onb) { 'PASS' } else { 'FAIL' }) 'onboardingStates/default'
$t = Invoke-L13Rest -AllowNotFound -Path "$($lab.workspaceId)/tables/$($n.customTable)?api-version=2023-09-01"
$tOk = $t -and $t.properties.plan -eq 'Analytics' -and $t.properties.retentionInDays -eq $cfg.customTable.retentionInDays -and $t.properties.totalRetentionInDays -eq $cfg.customTable.totalRetentionInDays
Add-Check 'Custom table' $(if ($tOk) { 'PASS' } else { 'FAIL' }) "$($n.customTable) $($t.properties.plan) $($t.properties.retentionInDays)/$($t.properties.totalRetentionInDays) days (Lesson 14 needs Analytics)"

$expected = @{ $n.dcrSyslog = $n.forwarderVm; $n.dcrCef = $n.forwarderVm; $n.dcrWindowsSecurity = $n.collectorVm; $n.dcrForwarded = $n.collectorVm; $n.dcrServiceHub = '' }
foreach ($name in $expected.Keys) {
    $d = Invoke-L13Rest -AllowNotFound -Path "/subscriptions/$($cfg.subscriptionId)/resourceGroups/$($cfg.resourceGroup)/providers/Microsoft.Insights/dataCollectionRules/$name`?api-version=2023-03-11"
    if (-not $d) { Add-Check "DCR $name" 'FAIL' 'missing'; continue }
    if ($expected[$name]) {
        $a = Invoke-L13Rest -Path "$($d.id)/associations?api-version=2023-03-11"
        $on = @($a.value | ForEach-Object { ($_.id -split '/providers/Microsoft.Insights')[0].Split('/')[-1] })
        Add-Check "DCR $name" $(if ($on -contains $expected[$name]) { 'PASS' } else { 'FAIL' }) "attached to $($on -join ', ')"
    }
    else { Add-Check "DCR $name" $(if ($d.kind -eq 'Direct' -and $d.properties.endpoints.logsIngestion) { 'PASS' } else { 'FAIL' }) "Direct, own ingestion endpoint" }
}
$act = Invoke-L13Rest -AllowNotFound -Path "/subscriptions/$($cfg.subscriptionId)/providers/Microsoft.Insights/diagnosticSettings/$($n.activityDiagnosticSetting)?api-version=2021-05-01-preview"
Add-Check 'Activity log route' $(if ($act -and $act.properties.workspaceId -eq $lab.workspaceId) { 'PASS' } else { 'FAIL' }) $n.activityDiagnosticSetting
foreach ($g in @($n.analystGroup, $n.engineerGroup)) {
    $found = @(Invoke-L13Az -NoSubscription @('ad', 'group', 'list', '--filter', "displayName eq '$g'", '--query', '[].id'))
    Add-Check "Group $g" $(if ($found.Count -eq 1) { 'PASS' } else { 'FAIL' }) 'role demo principal, no members'
}
$fwd = Get-L13PowerState -Vm $n.forwarderVm; $wec = Get-L13PowerState -Vm $n.collectorVm
$nat = @(Invoke-L13Az @('network', 'nat', 'gateway', 'list', '--resource-group', $cfg.resourceGroup) | Where-Object name -EQ $n.nat).Count
if ($Recording) {
    Add-Check 'Collectors running' $(if ($fwd -eq 'running' -and $wec -eq 'running') { 'PASS' } else { 'FAIL' }) "forwarder $fwd, collector $wec"
    Add-Check 'Temporary egress' $(if ($nat -eq 1) { 'PASS' } else { 'FAIL' }) 'NAT gateway present'
    $kql = "union withsource=Table isfuzzy=true AzureActivity, Syslog, CommonSecurityLog, SecurityEvent, WindowsEvent, $($n.customTable) | where TimeGenerated > ago(24h) | summarize Rows = count() by Table"
    $rows = @{}; foreach ($r in (Invoke-L13Query -Lab $lab -Kql $kql -Timespan 'P1D')) { $rows[$r.Table] = [int]$r.Rows }
    foreach ($tn in @('AzureActivity', 'Syslog', 'CommonSecurityLog', 'SecurityEvent', 'WindowsEvent', $n.customTable)) {
        Add-Check "Rows in $tn" $(if ($rows[$tn] -gt 0) { 'PASS' } else { 'FAIL' }) "$([int]$rows[$tn]) in 24 hours"
    }
}
else {
    Add-Check 'Idle baseline' $(if ($fwd -eq 'deallocated' -and $wec -eq 'deallocated' -and $nat -eq 0) { 'PASS' } else { 'INFO' }) "forwarder $fwd, collector $wec, NAT $nat"
}
$entra = Invoke-L13Rest -Path '/providers/microsoft.aadiam/diagnosticSettings?api-version=2017-04-01-preview'
$here = @($entra.value | Where-Object { $_.properties.workspaceId -eq $lab.workspaceId }).Count
Add-Check 'Microsoft Entra route' $(if ($Recording -and -not $here) { 'FAIL' } elseif ($here) { 'PASS' } else { 'INFO' }) "$(if ($here) { 'connected' } else { 'not connected; shared-tenant slot decision pending' }); tenant uses $(@($entra.value).Count) of 5 settings"
$conn = Invoke-L13Rest -Path "$($lab.workspaceId)/providers/Microsoft.SecurityInsights/dataConnectors?api-version=2024-09-01"
Add-Check 'Sentinel data connectors' 'INFO' "$(if ($conn.value) { ($conn.value | ForEach-Object kind) -join ', ' } else { 'no explicit dataConnector resources; primary XDR routing is checked separately' })"

if ($Recording) {
    $office = @($conn.value | Where-Object kind -EQ 'Office365')
    Add-Check 'Microsoft 365 route' $(if ($office.Count) { 'PASS' } else { 'FAIL' }) 'Office365 connector configuration'
    $tenantRows = Invoke-L13Query -Lab $lab -Kql 'union withsource=Table isfuzzy=true SigninLogs, AuditLogs, OfficeActivity, AzureActivity | where TimeGenerated > ago(24h) | summarize Rows=count() by Table' -Timespan P1D
    foreach ($tn in @('SigninLogs','AuditLogs','OfficeActivity')) {
        $count = @($tenantRows | Where-Object Table -EQ $tn | ForEach-Object Rows | Measure-Object -Sum).Sum
        Add-Check "Tenant rows in $tn" $(if ($count -gt 0) { 'PASS' } else { 'FAIL' }) "$count observed in 24 hours"
    }
    $markerPath = Join-Path $script:L13State 'last-marker.json'
    $fresh = $false
    if (Test-Path -LiteralPath $markerPath) {
        $marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
        $failureUtc = Get-L13Value $marker 'failureUtc'
        if ($failureUtc -and [DateTime]$failureUtc -gt [DateTime]::UtcNow.AddHours(-24)) {
            $k = "union withsource=Table isfuzzy=true SecurityEvent, WindowsEvent | where TimeGenerated >= datetime($failureUtc) | where EventID == 4625 | where tostring(column_ifexists('TargetUserName','')) =~ '$($cfg.collection.probeAccount)' or tostring(column_ifexists('EventData',dynamic({})).TargetUserName) =~ '$($cfg.collection.probeAccount)' | summarize Rows=count() by Table"
            $delivered = @(Invoke-L13Query -Lab $lab -Kql $k -Timespan P1D)
            $fresh = @($delivered | Where-Object Table -EQ 'SecurityEvent').Count -gt 0 -and @($delivered | Where-Object Table -EQ 'WindowsEvent').Count -gt 0
        }
    }
    Add-Check 'Latest failed sign-in on both routes' $(if ($fresh) { 'PASS' } else { 'FAIL' }) 'Both tables must contain the configured probe after the latest attempt started.'
}
$results | Format-Table -AutoSize | Out-Host
[void](Write-L13Evidence ($(if ($Recording) { 'test-recording' } else { 'test' })) ([ordered]@{ testedUtc = [DateTime]::UtcNow.ToString('o'); results = $results }))
if (@($results | Where-Object Result -EQ 'FAIL').Count -gt 0) { Write-Host 'Not ready.'; exit 1 }
if ($Recording) { Write-Host 'Recording evidence checks passed. Your rehearsal and measured timing remain separate.' }
else { Write-Host 'Configuration checks passed. Review the separate idle result. Event delivery and recording readiness are not certified.' }
