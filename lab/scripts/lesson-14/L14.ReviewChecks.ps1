<#
.SYNOPSIS
    Evidence contracts for the selected L14 case and its handoff to L15.
.DESCRIPTION
    These helpers separate configuration from execution. A matching string alone cannot prove
    a successful playbook or a Purview service record. All cloud operations here are read-only.
#>
function Get-L14PinnedCase {
    $path = Join-Path $script:L14State 'handoff-case.json'
    if (Test-Path -LiteralPath $path) { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
    return $null
}

function Get-L14RecordingIncident {
    $pin = Get-L14PinnedCase
    if ($pin) { return $pin.incident }
    $path = Join-Path $script:L14State 'last-incident.json'
    if (-not (Test-Path -LiteralPath $path)) { throw 'No selected incident. Resolve the fixture with DetectionDemo -Mode Alert.' }
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Test-L14SucceededRun {
    <# .SYNOPSIS A run match requires the exact ID and terminal Succeeded state, never just a nonempty status. #>
    param($Run,[string]$ExpectedName)
    return [bool]($Run -and $Run.name -ceq $ExpectedName -and $Run.properties.status -ceq 'Succeeded')
}

function Get-L14CaseProof {
    param($L13Lab,$Lab)
    $selected = Get-L14RecordingIncident
    $fixture = Get-L14LastFixture
    $i = Invoke-L14Rest -Path "$($L13Lab.workspaceId)/providers/Microsoft.SecurityInsights/incidents/$($selected.incidentName)?api-version=2025-09-01"
    $rulePath = "$($L13Lab.workspaceId)/providers/Microsoft.SecurityInsights/alertRules/$($script:L14Config.names.analyticsRuleId)"
    $ruleMatches = @($i.properties.relatedAnalyticRuleIds) -contains $rulePath
    $alerts = @(Get-L14IncidentAlerts -L13Lab $L13Lab -IncidentName $i.name)
    # Match the fixture's custom detail, not the first alert in a possibly correlated incident.
    $matched = @(Get-L14FixtureAlerts -L13Lab $L13Lab -Alerts $alerts -FixtureId $fixture.fixtureId)
    $comments = @(Get-L14IncidentComments -L13Lab $L13Lab -IncidentName $i.name)
    $runs = @()
    foreach ($c in $comments) {
        $message = ($c.properties.message -replace '<[^>]+>', '').Trim()
        if ($message -match 'Run ([A-Za-z0-9]+) received' -and $c.properties.author.name -eq "Comment created from playbook - $($script:L14Config.names.playbook)") {
            $runName = $Matches[1]
            # Direct lookup avoids the old last-20-runs pagination false negative.
            $run = Invoke-L14Rest -AllowNotFound -Path "$($Lab.playbookId)/runs/$runName`?api-version=2019-05-01"
            $runs += [pscustomobject]@{name=$runName; succeeded=(Test-L14SucceededRun $run $runName); status=(Get-L14Value $run 'properties.status'); commentId=$c.name; commentUtc=$c.properties.createdTimeUtc}
        }
    }
    $tags = @($i.properties.labels | ForEach-Object labelName)
    $hasTags = @($script:L14Config.names.incidentTags | Where-Object { $tags -notcontains $_ }).Count -eq 0
    return [pscustomobject]@{incidentName=$i.name; incidentNumber=$i.properties.incidentNumber; defenderIncident=$i.properties.providerIncidentId; status=$i.properties.status; fixtureId=$fixture.fixtureId; fileName=$fixture.fileName; ruleMatches=$ruleMatches; fixtureAlerts=$matched.Count; hasTags=$hasTags; runs=$runs; executionPassed=[bool]($ruleMatches -and $matched.Count -gt 0 -and $hasTags -and @($runs | Where-Object succeeded).Count -gt 0); openForHandoff=($i.properties.status -ne 'Closed')}
}

function Get-L14FixtureAlerts {
    <# .SYNOPSIS Join an incident's exact alert IDs to their fixture custom details in SecurityAlert. #>
    param($L13Lab,[array]$Alerts,[string]$FixtureId)
    if ($FixtureId -notmatch '^[a-fA-F0-9-]{36}$') { throw 'Invalid fixture ID.' }
    $rows = @(Invoke-L14Query -Lab $L13Lab -Timespan 'P30D' -Kql @"
SecurityAlert
| extend Details = parse_json(tostring(parse_json(ExtendedProperties)['Custom Details']))
| where set_has_element(Details.FixtureId, '$FixtureId')
| distinct SystemAlertId
"@)
    $ids = @($rows | ForEach-Object SystemAlertId)
    # ARM's alert summary omits custom details. Until table ingestion completes this remains pending.
    return @($Alerts | Where-Object { $ids -contains $_.properties.systemAlertId })
}

function Test-L14AuditCapture {
    <#
    .SYNOPSIS Require an actual exported Audit row and an incident comment containing its record ID.
    .DESCRIPTION Store the unmodified Purview CSV export at .azure/lesson-14/audit-export.csv.
    This reads AuditData JSON from that CSV; it never manufactures a row from an analyst note.
    #>
    param($L13Lab)
    $file = Join-Path $script:L14State 'audit-export.csv'
    if (-not (Test-Path -LiteralPath $file)) { return [pscustomobject]@{passed=$false; detail='No captured Purview CSV export for the selected case.'} }
    $fixture = Get-L14LastFixture
    $inc = Get-L14RecordingIncident
    $comments = @(Get-L14IncidentComments -L13Lab $L13Lab -IncidentName $inc.incidentName)
    foreach ($row in (Import-Csv -LiteralPath $file)) {
        $raw = Get-L14Value $row 'AuditData'
        if (-not $raw) { continue }
        $a = $raw | ConvertFrom-Json
        $object = [string](Get-L14Value $a 'ObjectId')
        $name = [Uri]::UnescapeDataString(($object -split '/')[-1])
        if ((Get-L14Value $a 'Operation') -ne 'FileUploaded' -or (Get-L14Value $a 'UserId') -ne $script:L14Config.operatorUpn -or $name -cne $fixture.fileName -or -not (Get-L14Value $a 'Id') -or -not (Get-L14Value $a 'CreationTime')) { continue }
        $id = [string]$a.Id
        $attached = @($comments | Where-Object { $_.properties.message.Contains($id) -and $_.properties.message.Contains($fixture.fileName) }).Count -gt 0
        return [pscustomobject]@{passed=$attached; detail="Captured Audit record $id; attached to selected incident: $attached"; recordId=$id; fileSha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash; operationUtc=$a.CreationTime}
    }
    return [pscustomobject]@{passed=$false; detail='Export has no matching FileUploaded row for the selected file and operator.'}
}
