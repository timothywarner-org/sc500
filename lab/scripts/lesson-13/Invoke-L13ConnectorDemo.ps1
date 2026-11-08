<#
.SYNOPSIS
    Demo 13.2: which sources reach the ServiceHub workspace, by which route, into which table.
.DESCRIPTION
    Modes:
      Sources  Read-only. For every source family in the lesson, the destination table, rows in the
               last 24 hours, and the newest row. No rows is an observation, not a connection verdict.
      Routes   Read-only. The collection plumbing: the subscription Activity log setting, the data
               collection rules, the Sentinel data connectors and content hub packages on the workspace,
               and whether any tenant-level Microsoft Entra diagnostic setting targets this workspace.
      Probe    WRITE (a logged action, no configuration change). Lists the keys of Lesson 12's export
               store once, the way a Shared Key client would, and discards them without printing.
               That produces one fresh Activity log event for Katie's question.
      Trace    Read-only. Finds that listKeys event in AzureActivity: caller, time, result, and
               ingestion delay. It also reads the same events from the Activity log itself, so
               the output shows whether the workspace has caught up with the source. The
               caller's IP address is kept in private evidence, not printed.
.PARAMETER Mode Sources, Routes, Probe, or Trace.
.PARAMETER Hours How far back Trace looks. Default 6.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Invoke-L13ConnectorDemo.ps1 -Mode Sources
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Sources', 'Routes', 'Probe', 'Trace')][string]$Mode,
    [ValidateRange(1, 168)][int]$Hours = 6
)
. (Join-Path $PSScriptRoot 'L13.Common.ps1')
$cfg = $script:L13Config
[void](Assert-L13Context)
$lab = Get-L13Outputs

function Get-L13ExportStore {
    # Lesson 12's export store, found by prefix in its own resource group.
    $s = @(Invoke-L13Az @('storage', 'account', 'list', '--resource-group', $cfg.l12Handoff.resourceGroup, '--query', '[].{name:name,id:id}') |
        Where-Object { $_.name -like "$($cfg.l12Handoff.storagePrefix)*" })
    if ($s.Count -ne 1) { throw "Expected one $($cfg.l12Handoff.storagePrefix)* store in $($cfg.l12Handoff.resourceGroup); found $($s.Count)." }
    return $s[0]
}

switch ($Mode) {
    'Sources' {
        $families = @(
            @{ family = 'Azure resources (Activity log)'; table = 'AzureActivity' }
            @{ family = 'Microsoft Entra sign-ins'; table = 'SigninLogs' }
            @{ family = 'Microsoft Entra audit'; table = 'AuditLogs' }
            @{ family = 'Microsoft 365'; table = 'OfficeActivity' }
            @{ family = 'Defender XDR incidents'; table = 'SecurityIncident' }
            @{ family = 'Defender alerts'; table = 'SecurityAlert' }
            @{ family = 'Linux Syslog'; table = 'Syslog' }
            @{ family = 'CEF appliances'; table = 'CommonSecurityLog' }
            @{ family = 'Windows Security (AMA)'; table = 'SecurityEvent' }
            @{ family = 'Windows forwarded (WEF)'; table = 'WindowsEvent' }
            @{ family = 'ServiceHub audit (custom)'; table = $cfg.names.customTable }
        )
        $names = ($families | ForEach-Object { $_.table }) -join ', '
        # isfuzzy lets the union run when a table has never received data in this workspace.
        $kql = "union withsource=Table isfuzzy=true $names | where TimeGenerated > ago(24h) | summarize Rows = count(), Newest = max(TimeGenerated) by Table"
        $seen = @{}; foreach ($r in (Invoke-L13Query -Lab $lab -Kql $kql -Timespan 'P1D')) { $seen[$r.Table] = $r }
        $rows = foreach ($f in $families) {
            $r = $seen[$f.table]
            [pscustomobject][ordered]@{
                Source = $f.family; Table = $f.table
                Rows24h = if ($r) { [int]$r.Rows } else { 0 }
                NewestUtc = if ($r) { ([DateTime]$r.Newest).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') } else { '' }
                State = if ($r) { 'Rows observed in 24h' } else { 'No rows observed in 24h; inspect Routes' }
            }
        }
        $rows | Format-Table -AutoSize | Out-Host
        [void](Write-L13Evidence 'sources' ([ordered]@{ readUtc = [DateTime]::UtcNow.ToString('o'); sources = $rows }))
    }
    'Routes' {
        $sub = "/subscriptions/$($cfg.subscriptionId)"
        $activity = Invoke-L13Rest -AllowNotFound -Path "$sub/providers/Microsoft.Insights/diagnosticSettings/$($cfg.names.activityDiagnosticSetting)?api-version=2021-05-01-preview"
        $dcrs = @(Invoke-L13Az @('monitor', 'data-collection', 'rule', 'list', '--resource-group', $cfg.resourceGroup))
        $dcrRows = foreach ($d in $dcrs) {
            $assoc = Invoke-L13Rest -Path "$($d.id)/associations?api-version=2023-03-11"
            [pscustomobject][ordered]@{
                Rule = $d.name; Kind = $d.kind
                Streams = (@($d.dataFlows | ForEach-Object { $_.streams }) | Select-Object -Unique) -join ', '
                Transform = (@($d.dataFlows | ForEach-Object { Get-L13Value $_ 'transformKql' } | Where-Object { $_ }) -join ' ')
                AttachedTo = (@($assoc.value | ForEach-Object { ($_.id -split '/providers/Microsoft.Insights')[0].Split('/')[-1] }) -join ', ')
            }
        }
        $connectors = Invoke-L13Rest -Path "$($lab.workspaceId)/providers/Microsoft.SecurityInsights/dataConnectors?api-version=2024-09-01"
        $packages = Invoke-L13Rest -Path "$($lab.workspaceId)/providers/Microsoft.SecurityInsights/contentPackages?api-version=2024-09-01"
        # Tenant-level Entra settings: report only whether one targets this workspace (other courses share the tenant).
        $entra = Invoke-L13Rest -Path '/providers/microsoft.aadiam/diagnosticSettings?api-version=2017-04-01-preview'
        $entraHere = @($entra.value | Where-Object { $_.properties.workspaceId -eq $lab.workspaceId })
        Write-Host "Activity log to workspace: $(if ($activity) { 'yes (' + $activity.name + ')' } else { 'no' })"
        $dcrRows | Format-Table -AutoSize | Out-Host
        Write-Host "Sentinel data connectors on the workspace: $(if ($connectors.value) { ($connectors.value | ForEach-Object kind) -join ', ' } else { 'none' })"
        Write-Host "Content hub packages installed: $(if ($packages.value) { ($packages.value | ForEach-Object { $_.properties.displayName }) -join '; ' } else { 'none' })"
        Write-Host "Microsoft Entra diagnostic setting to this workspace: $(if ($entraHere) { 'yes' } else { 'no' }) (tenant slots used: $(@($entra.value).Count) of 5)"
        [void](Write-L13Evidence 'routes' ([ordered]@{
            readUtc = [DateTime]::UtcNow.ToString('o'); activitySetting = $activity; dcrs = $dcrRows
            connectors = @($connectors.value | ForEach-Object { [ordered]@{ name = $_.name; kind = $_.kind } })
            contentPackages = @($packages.value | ForEach-Object { [ordered]@{ name = $_.properties.displayName; version = $_.properties.version } })
            entraToThisWorkspace = [bool]$entraHere; entraSettingsInTenant = @($entra.value).Count
        }))
    }
    'Probe' {
        $store = Get-L13ExportStore
        $utc = [DateTime]::UtcNow
        $r = Invoke-L13Rest -Method post -Path "$($store.id)/listKeys?api-version=2023-05-01"
        $count = @($r.keys).Count
        $r = $null  # The keys are discarded here and never printed or saved.
        Write-Host "listKeys on $($store.name) at $($utc.ToString('o')): returned $count keys (not shown)."
        [void](Write-L13Evidence 'probe' ([ordered]@{ probeUtc = $utc.ToString('o'); storage = $store.name; storageId = $store.id; keysReturned = $count }))
    }
    'Trace' {
        $store = Get-L13ExportStore
        $kql = @"
AzureActivity
| where TimeGenerated > ago($($Hours)h)
| where OperationNameValue =~ 'MICROSOFT.STORAGE/STORAGEACCOUNTS/LISTKEYS/ACTION'
| where _ResourceId =~ '$($store.id)'
| project TimeGenerated, Ingested = ingestion_time(), Caller, CallerIpAddress, ActivityStatusValue, OperationNameValue, CorrelationId, ResourceGroup
| order by TimeGenerated desc
"@
        $rows = Invoke-L13Query -Lab $lab -Kql $kql -Timespan "PT$($Hours)H"
        $shown = foreach ($r in $rows) {
            $t = [DateTime]$r.TimeGenerated; $i = [DateTime]$r.Ingested
            [pscustomobject][ordered]@{
                TimeUtc = $t.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss'); Caller = $r.Caller; CallerIp = 'Your IP (in private evidence)'
                Status = $r.ActivityStatusValue; Resource = $store.name; CorrelationId = $r.CorrelationId
                IngestDelayMin = [math]::Round(($i - $t).TotalMinutes, 1)
            }
        }
        # The source of truth for comparison: the subscription's own Activity log, before any export.
        $since = [DateTime]::UtcNow.AddHours(-$Hours).ToString('yyyy-MM-ddTHH:mm:ssZ')
        $source = @(Invoke-L13Az @('monitor', 'activity-log', 'list', '--resource-id', $store.id, '--start-time', $since,
            '--query', "[?operationName.value=='Microsoft.Storage/storageAccounts/listKeys/action' && status.value=='Succeeded'].{time:eventTimestamp,caller:caller,correlationId:correlationId}"))
        Write-Host ("In the Activity log itself: {0} successful listKeys events on {1} in the last {2} hours." -f $source.Count, $store.name, $Hours)
        foreach ($e in ($source | Sort-Object time)) { Write-Host ("  {0:u}  {1}  {2}" -f ([DateTime]$e.time).ToUniversalTime(), $e.caller, $e.correlationId) }
        if (-not $shown) { Write-Host "In the workspace (AzureActivity): no matching rows in this window. Compare the source and route; this alone does not establish delay or data loss." }
        else { Write-Host "In the workspace (AzureActivity):"; $shown | Format-List | Out-Host }
        # Select-Object, not [0]: under strict mode, indexing an empty result throws instead of returning nothing.
        $latest = @($shown) | Select-Object -First 1
        $same = $latest -and @($source | Where-Object { $_.correlationId -eq $latest.CorrelationId }).Count -gt 0
        Write-L13Verdict -Rows @(
            [ordered]@{ Check = 'listKeys in the Activity log'; Expected = 'found'; Observed = $(if ($source.Count) { 'found' } else { 'none' }) }
            [ordered]@{ Check = 'listKeys in AzureActivity'; Expected = 'found'; Observed = $(if ($latest) { 'found' } else { 'not yet' }) }
            [ordered]@{ Check = 'Same correlation ID in both'; Expected = 'yes'; Observed = $(if ($same) { 'yes' } else { 'no' }) }
            [ordered]@{ Check = 'Result'; Expected = 'Success'; Observed = $(if ($latest) { "$($latest.Status)" } else { 'none' }) }
        )
        [void](Write-L13Evidence 'trace-activity' ([ordered]@{ readUtc = [DateTime]::UtcNow.ToString('o'); storage = $store.name; rows = $rows; activityLogSource = $source }))
    }
}
