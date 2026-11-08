<#
.SYNOPSIS
    Demo 13.4: ServiceHub's own audit events in a custom table, and how long each table keeps data.
.DESCRIPTION
    Modes:
      Schema     Read-only. The ServiceHubAudit_CL table (plan, retention, columns) and the DCR that
                 feeds it (input stream, transformation, output table, ingestion endpoint).
      Send       WRITE (log data). Posts one batch to the Logs Ingestion API with your Entra token:
                 three ServiceHub audit events and one heartbeat, all sharing a new FixtureId. The
                 transformation drops the heartbeat, so three rows should land.
      Trace      Read-only. Finds the latest FixtureId in ServiceHubAudit_CL with ingestion delay.
      Retention  Read-only. Plan, analytics retention, and total retention for the tables the lesson
                 uses, next to the workspace default.
      SetTotal   WRITE. Sets ServiceHubAudit_CL total retention to -TotalDays (analytics retention
                 unchanged). Reset-L13Lab.ps1 puts the configured value back.
    Every event is a synthetic fixture and is labeled so in EvidenceClass.
.PARAMETER Mode Schema, Send, Trace, Retention, or SetTotal.
.PARAMETER TotalDays Total retention for SetTotal. Allowed: 4 to 730, or 1095, 1460, 1826, 2191, 2556 (CLI limit is seven years).
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Invoke-L13TableDemo.ps1 -Mode Send
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Schema', 'Send', 'Trace', 'Retention', 'SetTotal')][string]$Mode,
    [int]$TotalDays = 730,
    # Retention's verdict compares total retention with this; the demo passes 730 after the portal change.
    [int]$ExpectTotalDays = 0
)
. (Join-Path $PSScriptRoot 'L13.Common.ps1')
$cfg = $script:L13Config
[void](Assert-L13Context)
$lab = Get-L13Outputs
$table = $cfg.names.customTable
$fixtureFile = Join-Path $script:L13State 'last-fixture.json'

function Get-L13Table {
    param([Parameter(Mandatory)][string]$Name)
    return Invoke-L13Rest -AllowNotFound -Path "$($lab.workspaceId)/tables/$Name`?api-version=2023-09-01"
}

switch ($Mode) {
    'Schema' {
        $t = Get-L13Table -Name $table
        $d = Invoke-L13Rest -Path "$($lab.dcrServiceHubId)?api-version=2023-03-11"
        $flow = $d.properties.dataFlows[0]
        $out = [ordered]@{
            table = $t.name; plan = $t.properties.plan; analyticsRetentionDays = $t.properties.retentionInDays
            totalRetentionDays = $t.properties.totalRetentionInDays
            columns = @($t.properties.schema.columns | ForEach-Object { "$($_.name):$($_.type)" }) -join ', '
            dcr = $d.name; dcrKind = $d.kind; inputStream = ($flow.streams -join ', '); transformKql = $flow.transformKql
            outputStream = $flow.outputStream; ingestionEndpoint = $d.properties.endpoints.logsIngestion; immutableId = $d.properties.immutableId
        }
        [pscustomobject]$out | Format-List | Out-Host
        [void](Write-L13Evidence 'table-schema' $out)
    }
    'Send' {
        $fixture = [guid]::NewGuid().ToString()
        $now = [DateTime]::UtcNow
        $store = @(Invoke-L13Az @('storage', 'account', 'list', '--resource-group', $cfg.l12Handoff.resourceGroup, '--query', '[].name') | Where-Object { $_ -like "$($cfg.l12Handoff.storagePrefix)*" })[0]
        $target = "$store/parts-exports/parts-export-2026-11-05.csv"   # Lesson 12's nightly export (lesson-12 config.json)
        # Invented events in ServiceHub's own vocabulary. Client IPs are RFC 5737 documentation addresses.
        $events = @(
            [ordered]@{ TimeGenerated = $now.AddMinutes(-3).ToString('o'); FixtureId = $fixture; EvidenceClass = 'synthetic fixture'; CaseId = 'SR-1043'; Actor = 'svc-servicehub-parts'; Operation = 'PartsExportRead'; TargetResource = $target; Result = 'Allowed'; ClientIp = '192.0.2.10'; Detail = 'Northwind Traders CTSO-P200 pump assembly lookup' }
            [ordered]@{ TimeGenerated = $now.AddMinutes(-2).ToString('o'); FixtureId = $fixture; EvidenceClass = 'synthetic fixture'; CaseId = 'SR-1043'; Actor = 'svc-servicehub-parts'; Operation = 'PartsExportRead'; TargetResource = $target; Result = 'Allowed'; ClientIp = '192.0.2.10'; Detail = 'Replacement confirmed for SR-1043' }
            [ordered]@{ TimeGenerated = $now.AddMinutes(-1).ToString('o'); FixtureId = $fixture; EvidenceClass = 'synthetic fixture'; CaseId = ''; Actor = 'svc-servicehub-parts'; Operation = 'PartsExportRead'; TargetResource = $target; Result = 'Allowed'; ClientIp = '198.51.100.77'; Detail = 'Full export read with no service case attached' }
            [ordered]@{ TimeGenerated = $now.ToString('o'); FixtureId = $fixture; EvidenceClass = 'synthetic fixture'; CaseId = ''; Actor = 'servicehub-monitor'; Operation = 'Heartbeat'; TargetResource = ''; Result = 'OK'; ClientIp = ''; Detail = 'Dropped by the DCR transformation' }
        )
        $token = Get-L13Token -Resource 'https://monitor.azure.com'
        $uri = "$($lab.logsIngestionEndpoint)/dataCollectionRules/$($lab.dcrServiceHubImmutableId)/streams/Custom-ServiceHubAudit?api-version=2023-01-01"
        $resp = $null
        foreach ($attempt in 1..10) {
            $resp = Invoke-WebRequest -Uri $uri -Method Post -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/json' `
                -Body (ConvertTo-Json -InputObject @($events) -Depth 5 -Compress) -SkipHttpErrorCheck
            if ([int]$resp.StatusCode -eq 204) { break }
            # A new role assignment on the DCR can take a few minutes to reach the ingestion service.
            Write-Host "  attempt $attempt returned $([int]$resp.StatusCode); waiting 30 seconds"
            Start-Sleep -Seconds 30
            $token = Get-L13Token -Resource 'https://monitor.azure.com'
        }
        $token = $null
        if ([int]$resp.StatusCode -ne 204) { throw "Logs Ingestion API returned $([int]$resp.StatusCode): $($resp.Content)" }
        Write-Host "Posted $($events.Count) records (three events and one heartbeat) with FixtureId $fixture. HTTP 204 means accepted, not yet queryable."
        @{ fixtureId = $fixture; sentUtc = $now.ToString('o'); records = $events.Count } | ConvertTo-Json | Set-Content -LiteralPath $fixtureFile -Encoding utf8
        [void](Write-L13Evidence 'table-send' ([ordered]@{ fixtureId = $fixture; sentUtc = $now.ToString('o'); status = [int]$resp.StatusCode; events = $events }))
    }
    'Trace' {
        if (-not (Test-Path -LiteralPath $fixtureFile)) { throw 'No fixture yet. Run -Mode Send first.' }
        $f = Get-Content -LiteralPath $fixtureFile -Raw | ConvertFrom-Json
        $rows = @(Invoke-L13Query -Lab $lab -Kql "$table | where FixtureId == '$($f.fixtureId)' | project TimeGenerated, Ingested = ingestion_time(), CaseId, Actor, Operation, Result, ClientIp, Detail | order by TimeGenerated asc" -Timespan 'P2D')
        foreach ($r in $rows) {
            $t = [DateTime]$r.TimeGenerated; $i = [DateTime]$r.Ingested
            Write-Host ("{0:u}  delay {1,5:N1} min  case {2,-8} {3,-16} {4,-8} {5}" -f $t.ToUniversalTime(), ($i - $t).TotalMinutes, $(if ($r.CaseId) { $r.CaseId } else { '(none)' }), $r.Operation, $r.Result, $r.Detail)
        }
        Write-Host "FixtureId $($f.fixtureId): $($rows.Count) rows landed from $($f.records) records sent."
        Write-L13Verdict -Rows @(
            [ordered]@{ Check = 'Rows landed'; Expected = '3'; Observed = "$($rows.Count)" }
            [ordered]@{ Check = 'Heartbeat dropped by the rule'; Expected = 'yes'; Observed = $(if (@($rows | Where-Object Operation -EQ 'Heartbeat').Count) { 'no' } else { 'yes' }) }
            [ordered]@{ Check = 'Export with no service case'; Expected = 'found'; Observed = $(if (@($rows | Where-Object { -not $_.CaseId }).Count) { 'found' } else { 'none' }) }
        )
        [void](Write-L13Evidence 'table-trace' ([ordered]@{ readUtc = [DateTime]::UtcNow.ToString('o'); fixtureId = $f.fixtureId; sent = $f.records; landed = $rows.Count; rows = $rows }))
    }
    'Retention' {
        $ws = Invoke-L13Rest -Path "$($lab.workspaceId)?api-version=2023-09-01"
        $rows = foreach ($name in @($table, 'SecurityEvent', 'WindowsEvent', 'Syslog', 'CommonSecurityLog', 'AzureActivity', 'SigninLogs', 'OfficeActivity')) {
            $t = Get-L13Table -Name $name
            if (-not $t) { continue }
            [pscustomobject][ordered]@{
                Table = $name; Plan = $t.properties.plan
                AnalyticsDays = $t.properties.retentionInDays; TotalDays = $t.properties.totalRetentionInDays
                FollowsWorkspace = [bool](Get-L13Value $t 'properties.retentionInDaysAsDefault')
            }
        }
        Write-Host "Workspace default analytics retention: $($ws.properties.retentionInDays) days."
        $rows | Format-Table -AutoSize | Out-Host
        $mine = $rows | Where-Object Table -EQ $table
        $wantTotal = if ($ExpectTotalDays) { $ExpectTotalDays } else { $cfg.customTable.totalRetentionInDays }
        Write-L13Verdict -Rows @(
            [ordered]@{ Check = "$table plan"; Expected = $cfg.customTable.plan; Observed = "$($mine.Plan)" }
            [ordered]@{ Check = "$table analytics days"; Expected = "$($cfg.customTable.retentionInDays)"; Observed = "$($mine.AnalyticsDays)" }
            [ordered]@{ Check = "$table total days"; Expected = "$wantTotal"; Observed = "$($mine.TotalDays)" }
        )
        [void](Write-L13Evidence 'retention' ([ordered]@{ readUtc = [DateTime]::UtcNow.ToString('o'); workspaceDays = $ws.properties.retentionInDays; tables = $rows }))
    }
    'SetTotal' {
        $before = Get-L13Table -Name $table
        [void](Invoke-L13Az @('monitor', 'log-analytics', 'workspace', 'table', 'update', '--resource-group', $cfg.resourceGroup,
            '--workspace-name', $lab.workspace, '--name', $table, '--total-retention-time', "$TotalDays"))
        $after = Get-L13Table -Name $table
        Write-Host "$table total retention: $($before.properties.totalRetentionInDays) to $($after.properties.totalRetentionInDays) days; analytics retention stays $($after.properties.retentionInDays)."
        [void](Write-L13Evidence 'retention-set' ([ordered]@{ changedUtc = [DateTime]::UtcNow.ToString('o'); table = $table;
            before = [ordered]@{ analytics = $before.properties.retentionInDays; total = $before.properties.totalRetentionInDays }
            after = [ordered]@{ analytics = $after.properties.retentionInDays; total = $after.properties.totalRetentionInDays } }))
    }
}
