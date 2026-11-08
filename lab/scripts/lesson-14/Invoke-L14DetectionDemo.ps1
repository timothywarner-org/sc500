<#
.SYNOPSIS
    Demo 14.1: the ServiceHub export rule, a labeled fixture, tuning, and the alert and incident
    Microsoft Sentinel actually created.
.DESCRIPTION
    Modes (each saves a dated evidence file under lab/.azure/lesson-14/evidence/):
      Rule      Read-only. The deployed rule read back from Sentinel: schedule, threshold, entity
                mapping, custom details, grouping, and the first lines of its KQL.
      Fixture   Read-only. Shows the retained send selected for this incident and L15 handoff.
      Send      Refuses while pinned. Otherwise posts three synthetic ServiceHub export events,
                all sharing a new FixtureId: one export with service case SR-1043 (not a match),
                one approved replication job with no case (the tuned-out benign row), and one full
                export with no case from a documentation IP address (the intended match). The file
                name is unique, but Defender correlation does not promise a separate incident.
      Tune      Read-only. Runs the untuned query and the tuned query over this fixture and shows
                which row each filter removed. A query result is not an alert.
      Alert     Read-only. Waits (up to -WaitMinutes) for the incident the rule created for this
                fixture by joining its SecurityAlert custom detail to the incident's exact alert IDs.
                Until that detail reaches the table, the evidence is pending.
      History   Read-only. Every alert the rule raised in the last day, with its query window, its
                fixture, and the incident that holds it, plus each incident's provider. Shows
                grouping at work (two alerts in one incident) and which engine created the incident.
    The fixture is synthetic and labeled in EvidenceClass; the alert and incident are what the
    service actually created from it.
.PARAMETER Mode One of the modes above.
.PARAMETER WaitMinutes How long Alert may wait for the rule to run (default 20).
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Invoke-L14DetectionDemo.ps1 -Mode Send
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Rule', 'Send', 'Fixture', 'Tune', 'Alert', 'History')][string]$Mode,
    [ValidateRange(0, 60)][int]$WaitMinutes = 20
)
. (Join-Path $PSScriptRoot 'L14.Common.ps1')
$cfg = $script:L14Config
[void](Assert-L14Context)
$l13 = Get-L14L13Lab
$table = $cfg.l13.customTable
$ruleId = $cfg.names.analyticsRuleId
$rulePath = "$($l13.workspaceId)/providers/Microsoft.SecurityInsights/alertRules/$ruleId`?api-version=2025-09-01"

switch ($Mode) {
    'Fixture' {
        # Read the retained send instead of replacing the case whose Audit file was staged beforehand.
        Get-L14LastFixture | Format-List | Out-Host
        Write-Host 'Captured synthetic send; this command did not send new events.'
    }
    'Rule' {
        $r = Invoke-L14Rest -Path $rulePath
        $p = $r.properties
        $out = [ordered]@{
            name = $p.displayName; enabled = $p.enabled; severity = $p.severity
            runsEvery = $p.queryFrequency; looksBack = $p.queryPeriod
            threshold = "$($p.triggerOperator) $($p.triggerThreshold)"; alertPer = $p.eventGroupingSettings.aggregationKind
            entities = (@($p.entityMappings | ForEach-Object { "$($_.entityType) <- $($_.fieldMappings[0].columnName)" }) -join '; ')
            customDetails = (@($p.customDetails.PSObject.Properties | ForEach-Object { "$($_.Name) <- $($_.Value)" }) -join '; ')
            alertName = $p.alertDetailsOverride.alertDisplayNameFormat
            createIncident = $p.incidentConfiguration.createIncident
            grouping = "$($p.incidentConfiguration.groupingConfiguration.matchingMethod) within $($p.incidentConfiguration.groupingConfiguration.lookbackDuration)"
            tactics = ($p.tactics -join ', '); techniques = ($p.techniques -join ', ')
        }
        # Query first, rule facts last. The demo terminal is the short bottom zone of the Demo layout,
        # so the lines demo step 1.2 points at (runsEvery, looksBack, entities, customDetails, grouping)
        # must be the last thing on screen, not scrolled off above the query.
        Write-Host '--- query'
        Write-Host $p.query
        Write-Host '--- rule'
        [pscustomobject]$out | Format-List | Out-Host
        [void](Write-L14Evidence 'rule' ([ordered]@{ readUtc = [DateTime]::UtcNow.ToString('o'); rule = $out; query = $p.query; lastModifiedUtc = $p.lastModifiedUtc }))
    }
    'Send' {
        if (Get-L14PinnedCase) { throw 'The L14/L15 recording case is pinned. Use -Mode Fixture to read it; do not replace its staged Audit file.' }
        $fixture = [guid]::NewGuid().ToString()
        $now = [DateTime]::UtcNow
        $stamp = $now.ToString('yyyyMMddTHHmmssfff') + 'Z-' + $fixture.Substring(0,8)
        # Lesson 12's export store, by prefix in its own resource group (config.json l12Handoff).
        $store = @(Invoke-L14Az @('storage', 'account', 'list', '--resource-group', $cfg.l12Handoff.resourceGroup, '--query', '[].name') | Where-Object { $_ -like "$($cfg.l12Handoff.storagePrefix)*" }) | Select-Object -First 1
        if (-not $store) { throw 'The Lesson 12 export store was not found.' }
        $fileName = "$($cfg.fixture.fileNamePrefix)-$stamp.csv"
        $f = $cfg.fixture
        # Invented events in ServiceHub's own vocabulary; client IPs are RFC 5737 documentation addresses.
        $events = @(
            [ordered]@{ TimeGenerated = $now.AddMinutes(-3).ToString('o'); FixtureId = $fixture; EvidenceClass = 'synthetic fixture'; CaseId = $f.caseId; Actor = $f.intendedActor; Operation = 'PartsExportRead'; TargetResource = "$store/parts-exports/parts-lookup-$($f.caseId).csv"; Result = 'Allowed'; ClientIp = $f.caseIp; Detail = "Replacement lookup for $($f.caseId)" }
            [ordered]@{ TimeGenerated = $now.AddMinutes(-2).ToString('o'); FixtureId = $fixture; EvidenceClass = 'synthetic fixture'; CaseId = ''; Actor = $f.benignActor; Operation = 'PartsExportRead'; TargetResource = "$store/parts-exports/parts-catalog-replica-$stamp.csv"; Result = 'Allowed'; ClientIp = $f.benignIp; Detail = 'Nightly replication to the parts catalog (approved job)' }
            [ordered]@{ TimeGenerated = $now.AddMinutes(-1).ToString('o'); FixtureId = $fixture; EvidenceClass = 'synthetic fixture'; CaseId = ''; Actor = $f.intendedActor; Operation = 'PartsExportRead'; TargetResource = "$store/parts-exports/$fileName"; Result = 'Allowed'; ClientIp = $f.intendedIp; Detail = 'Full export read with no service case attached' }
        )
        $token = Get-L14Token -Resource 'https://monitor.azure.com'
        $uri = "$($l13.logsIngestionEndpoint)/dataCollectionRules/$($l13.dcrServiceHubImmutableId)/streams/Custom-ServiceHubAudit?api-version=2023-01-01"
        $resp = Invoke-WebRequest -Uri $uri -Method Post -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/json' `
            -Body (ConvertTo-Json -InputObject @($events) -Depth 5 -Compress) -SkipHttpErrorCheck
        $token = $null
        if ([int]$resp.StatusCode -ne 204) { throw "Logs Ingestion API returned $([int]$resp.StatusCode): $($resp.Content)" }
        Write-Host "Posted $($events.Count) ServiceHub export events with FixtureId $fixture at $($now.ToString('HH:mm:ss')) UTC."
        Write-Host "The intended match reads $fileName. HTTP 204 means accepted, not yet queryable; the rule runs every five minutes."
        [ordered]@{ fixtureId = $fixture; sentUtc = $now.ToString('o'); fileName = $fileName; store = $store } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $script:L14State 'last-fixture.json') -Encoding utf8
        [void](Write-L14Evidence 'send' ([ordered]@{ fixtureId = $fixture; sentUtc = $now.ToString('o'); status = [int]$resp.StatusCode; fileName = $fileName; events = $events }))
    }
    'Tune' {
        $fx = Get-L14LastFixture
        # The untuned rule is the first idea anyone writes: every export. The tuned rule is the
        # deployed one without its time window, so it can run over this fixture at any time.
        $base = "$table | where FixtureId == '$($fx.fixtureId)' | where Operation == 'PartsExportRead' and Result == 'Allowed'"
        # P7D, not P2D: the query already pins one FixtureId, so the window only decides how long the
        # retained fixture stays readable. P2D made demo step 1.3 throw two days after the Send.
        $rows = @(Invoke-L14Query -Lab $l13 -Kql "$base | project TimeGenerated, Actor, CaseId, ClientIp, Detail | order by TimeGenerated asc" -Timespan 'P7D')
        if ($rows.Count -eq 0) { throw 'The fixture rows are not queryable yet (ingestion takes several minutes). Try again shortly.' }
        $approved = @($cfg.detection.approvedExportJobs)
        $table2 = foreach ($r in $rows) {
            $why = if ($r.CaseId) { "removed: service case $($r.CaseId)" } elseif ($approved -contains $r.Actor) { 'removed: approved export job' } else { 'kept: no case, not an approved job' }
            [pscustomobject][ordered]@{ Time = ([DateTime]$r.TimeGenerated).ToUniversalTime().ToString('HH:mm:ss'); Actor = $r.Actor; Case = $(if ($r.CaseId) { $r.CaseId } else { '(none)' }); ClientIp = $r.ClientIp; Tuned = $why }
        }
        $table2 | Format-Table -AutoSize | Out-Host
        $tuned = @($table2 | Where-Object { $_.Tuned -like 'kept*' })
        Write-Host "Untuned query: $($rows.Count) rows. Tuned query: $($tuned.Count). These are fixture query results, not observed alerts or a per-run guarantee."
        [void](Write-L14Evidence 'tune' ([ordered]@{ readUtc = [DateTime]::UtcNow.ToString('o'); fixtureId = $fx.fixtureId; untuned = $rows.Count; tuned = $tuned.Count; rows = $table2 }))
    }
    'Alert' {
        # Read the incidents API, not the SecurityAlert table: the API shows an incident within
        # seconds, while the tables can lag several minutes. The fixture's file name is unique per
        # send, so the File entity identifies which incident holds this fixture's alert.
        $fx = Get-L14LastFixture
        $sent = ([DateTime]$fx.sentUtc).ToUniversalTime()
        $deadline = [DateTime]::UtcNow.AddMinutes($WaitMinutes)
        $match = $null
        do {
            foreach ($i in (Get-L14Incidents -L13Lab $l13)) {
                if (([DateTime]$i.properties.createdTimeUtc).ToUniversalTime() -lt $sent) { continue }
                $ents = Invoke-L14Rest -Method post -Path "$($l13.workspaceId)/providers/Microsoft.SecurityInsights/incidents/$($i.name)/entities?api-version=2025-09-01"
                $files = @($ents.entities | Where-Object { $_.kind -eq 'File' } | ForEach-Object { $_.properties.fileName })
                if ($files -contains $fx.fileName) { $match = [pscustomobject]@{ incident = $i; entities = @($ents.entities) }; break }
            }
            if ($match -or [DateTime]::UtcNow -ge $deadline) { break }
            Write-Host "$([DateTime]::UtcNow.ToString('HH:mm:ss')) UTC: no incident for $($fx.fileName) yet; checking again in 60 seconds."
            Start-Sleep -Seconds 60
        } while ($true)
        if (-not $match) { Write-Host 'No incident for this fixture yet. The rule runs every five minutes after ingestion; run -Mode Alert again.'; exit 1 }
        $i = $match.incident
        $incidentAlerts = @(Get-L14IncidentAlerts -L13Lab $l13 -IncidentName $i.name)
        $alert = @(Get-L14FixtureAlerts -L13Lab $l13 -Alerts $incidentAlerts -FixtureId $fx.fixtureId | Sort-Object { $_.properties.timeGenerated }) | Select-Object -First 1
        if (-not $alert) { throw 'Incident has the file entity, but no alert matches this exact fixture ID.' }
        $alertTime = ([DateTime]$alert.properties.timeGenerated).ToUniversalTime()
        $created = ([DateTime]$i.properties.createdTimeUtc).ToUniversalTime()
        # Inside a switch block, $_ is the switch value, so keep the entity in its own variable.
        $entities = @($match.entities | ForEach-Object {
            $e = $_
            switch ($e.kind) { 'Account' { "account $($e.properties.accountName)" } 'Ip' { "ip $($e.properties.address)" } 'File' { "file $($e.properties.fileName)" } } }) -join '; '
        $out = [ordered]@{
            fixtureId = $fx.fixtureId; sentUtc = $sent.ToString('o')
            alertId = $alert.properties.systemAlertId; alertName = $alert.properties.alertDisplayName
            alertTimeUtc = $alertTime.ToString('o'); alertMinutesAfterSend = [math]::Round(($alertTime - $sent).TotalMinutes, 1)
            alertProvider = $alert.properties.productName; entities = $entities
            incidentNumber = $i.properties.incidentNumber; incidentName = $i.name; incidentTitle = $i.properties.title
            incidentCreatedUtc = $created.ToString('o'); incidentMinutesAfterSend = [math]::Round(($created - $sent).TotalMinutes, 1)
            incidentProvider = $i.properties.providerName; incidentStatus = $i.properties.status
            alertsInIncident = $i.properties.additionalData.alertsCount
        }
        [pscustomobject]$out | Format-List | Out-Host
        @{ incidentName = $i.name; incidentNumber = $i.properties.incidentNumber; alertId = $alert.properties.systemAlertId } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $script:L14State 'last-incident.json') -Encoding utf8
        [void](Write-L14Evidence 'alert' $out)
    }
    'History' {
        $alerts = @(Invoke-L14Query -Lab $l13 -Timespan 'P1D' -Kql @'
SecurityAlert
| where AlertName startswith "Parts export with no service case"
| summarize arg_max(TimeGenerated, *) by SystemAlertId
| extend EP = parse_json(ExtendedProperties)
| extend Fixture = tostring(parse_json(tostring(EP["Custom Details"])).FixtureId[0]), WindowStart = tostring(EP["Query Start Time UTC"]), WindowEnd = tostring(EP["Query End Time UTC"])
| join kind=leftouter (SecurityIncident | summarize arg_max(TimeGenerated, *) by IncidentNumber | mv-expand AlertId = AlertIds to typeof(string) | project AlertId, IncidentNumber) on $left.SystemAlertId == $right.AlertId
| project Written = TimeGenerated, WindowStart, WindowEnd, Fixture, IncidentNumber, SystemAlertId
| order by Written asc
'@)
        foreach ($a in $alerts) {
            Write-Host ('{0:HH:mm:ss}  window {1} to {2}  fixture {3}  incident {4}' -f ([DateTime]$a.Written).ToUniversalTime(), $a.WindowStart, $a.WindowEnd, ([string]$a.Fixture).Substring(0, [Math]::Min(8, ([string]$a.Fixture).Length)), $a.IncidentNumber)
        }
        $incidents = @(Get-L14Incidents -L13Lab $l13 | ForEach-Object { [pscustomobject][ordered]@{
            Number = $_.properties.incidentNumber; CreatedUtc = ([DateTime]$_.properties.createdTimeUtc).ToUniversalTime().ToString('HH:mm:ss')
            Provider = $_.properties.providerName; DefenderIncident = $_.properties.providerIncidentId
            Alerts = $_.properties.additionalData.alertsCount; Status = $_.properties.status } })
        $incidents | Format-Table -AutoSize | Out-Host
        [void](Write-L14Evidence 'history' ([ordered]@{ readUtc = [DateTime]::UtcNow.ToString('o'); alerts = $alerts; incidents = $incidents }))
    }
}
