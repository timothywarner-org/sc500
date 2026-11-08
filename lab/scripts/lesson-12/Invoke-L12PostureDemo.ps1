<#
.SYNOPSIS
    SC-500 demo 12.1: read ServiceHub's security posture in Defender CSPM, fix one finding on the
    parts-export store, prove the fix, and trace it through compliance and governance.
.DESCRIPTION
    Modes (each saves a dated evidence file under lab/.azure/lesson-12/evidence/):
      Score       Classic secure score for the subscription and the controls with the most points
                  left, plus how ServiceHub's open recommendations spread across risk levels.
      Findings    One recommendation, "Storage accounts should prevent shared key access", on every
                  ServiceHub storage account: same severity everywhere, different risk levels, and
                  the risk factors that explain the difference. Then every open finding on the store.
      Remediate   WRITE. Proves a Shared Key request works, sets allowSharedKeyAccess to false on the
                  export store, proves the same request is now refused while your Entra path still
                  works, and records the Activity log receipt. Reset-L12Lab.ps1 puts the fault back.
      Receipt     Read-only follow-up: the store's settings, the Activity log write, the Defender
                  assessment status, and what exposure remains. This is the handoff Lesson 13 uses.
      Compliance  Regulatory compliance standards, and the controls that the shared-key finding fails.
      Governance  Governance rules and any owner and due date assigned to the store's finding.
      Assign      WRITE. Assigns the store's shared-key finding to you with a due date and a grace
                  period, then reads it back. Reset-L12Lab.ps1 removes it.
      Secrets     The secret-scanning finding on Lesson 3's runner VM: type, severity, and risk
                  level. It never reads or prints the secret itself.
      All         Score, Findings, Compliance, Governance, and Secrets (read-only).
    Only ServiceHub's own resource groups (config.json, servicehubResourceGroups) are printed, so
    labs from other courses in the same subscription stay off camera.
.PARAMETER Mode One of the modes above.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Invoke-L12PostureDemo.ps1 -Mode Findings
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Invoke-L12PostureDemo.ps1 -Mode Remediate
#>
[CmdletBinding()]
param([ValidateSet('Score', 'Findings', 'Remediate', 'Receipt', 'Compliance', 'Governance', 'Assign', 'Secrets', 'All')][string]$Mode = 'All')
. (Join-Path $PSScriptRoot 'L12.Common.ps1')
. (Join-Path $PSScriptRoot 'L12.Checks.ps1')
. (Join-Path $PSScriptRoot 'L12.Verdict.ps1')
$cfg = $script:L12Config
$pc = $cfg.posture
[void](Assert-L12Context)
$lab = Get-L12Outputs
$sub = "/subscriptions/$($cfg.subscriptionId)"
$key = $pc.sharedKeyAssessment
$fixtureAssessment = "$($lab.storageId)/providers/Microsoft.Security/assessments/$key"
# KQL list of ServiceHub groups, lowercased because Resource Graph IDs mix case.
$groups = ($cfg.servicehubResourceGroups | ForEach-Object { "'$($_.ToLower())'" }) -join ', '
$riskOrder = @{ Critical = 0; High = 1; Medium = 2; Low = 3 }

function Get-RiskSort($level) { if ($level -and $riskOrder.ContainsKey($level)) { $riskOrder[$level] } else { 9 } }

function Test-SharedKeyPath {
    # az fetches the account key itself (listKeys) when --auth-mode key has no key, so no key
    # ever passes through this script. The call succeeds only while Shared Key is allowed.
    $r = Invoke-L12Az -AllowFailure @('storage', 'container', 'list', '--account-name', $lab.storage, '--auth-mode', 'key', '--query', 'length(@)')
    $why = (($r.Stderr -split "`n") | Where-Object { $_.Trim() } | Select-Object -First 1)
    [pscustomobject]@{ allowed = ($r.ExitCode -eq 0); outcome = Get-L12KeyProbeOutcome $r.ExitCode $r.Stderr
        detail = $(if ($r.ExitCode -eq 0) { "listed $($r.Stdout.Trim()) container(s)" } else { "$why".Trim() }) }
}

function Get-FixtureAssessment {
    $a = Invoke-L12Rest -AllowNotFound -Path "$fixtureAssessment`?api-version=2021-06-01"
    if (-not $a) { return $null }
    [ordered]@{ status = (Get-L12Value $a 'properties.status.code'); statusChangeUtc = (Get-L12Value $a 'properties.status.statusChangeDate')
                firstEvaluationUtc = (Get-L12Value $a 'properties.status.firstEvaluationDate'); assessmentId = $a.id }
}

function Get-ActivityWrites([int]$Hours = 2) {
    $acts = Invoke-L12Az @('monitor', 'activity-log', 'list', '--resource-id', $lab.storageId, '--offset', "$($Hours)h", '--max-events', '200')
    @($acts | Where-Object { $_.operationName.value -eq 'Microsoft.Storage/storageAccounts/write' -and $_.status.value -eq 'Succeeded' } |
        Sort-Object eventTimestamp | ForEach-Object { [ordered]@{ timeUtc = $_.eventTimestamp; caller = $_.caller; operation = $_.operationName.value; correlationId = $_.correlationId } })
}

if ($Mode -in 'Score', 'All') {
    Write-Host '== Secure score (classic, Azure portal model)'
    $ss = Invoke-L12Rest -Path "$sub/providers/Microsoft.Security/secureScores/ascScore?api-version=2020-01-01"
    Write-Host ("  {0} of {1} ({2:P0})" -f $ss.properties.score.current, $ss.properties.score.max, [double]$ss.properties.score.percentage)
    $controls = Invoke-L12Graph -Query @"
securityresources
| where type == 'microsoft.security/securescores/securescorecontrols'
| extend current = todouble(properties.score.current), max = todouble(properties.score.max)
| project control = tostring(properties.displayName), current, max, left = round(max - current, 2), unhealthy = toint(properties.unhealthyResourceCount)
| where left > 0
| order by left desc
| take 5
"@
    $controls | ForEach-Object { Write-Host ("  {0,-45} {1,5} of {2,-3} points; {3} unhealthy resource(s)" -f $_.control, $_.current, $_.max, $_.unhealthy) }
    $levels = Invoke-L12Graph -Query @"
securityresources
| where type == 'microsoft.security/assessments' and tostring(properties.status.code) == 'Unhealthy'
| extend rg = tolower(tostring(split(tolower(tostring(properties.resourceDetails.Id)), '/')[4]))
| where rg in ($groups)
| summarize findings = count() by riskLevel = iff(isempty(tostring(properties.risk.level)), 'not rated', tostring(properties.risk.level))
"@
    $paths = @()
    $pathsRead = $false
    try { $paths = @(Invoke-L12Graph -Query "securityresources | where type == 'microsoft.security/attackpaths' | project name = tostring(properties.displayName), riskLevel = tostring(properties.riskLevel)"); $pathsRead = $true }
    catch { Write-Host "  Attack paths: the Resource Graph read failed ($($_.Exception.Message))" }
    # A failed query cannot establish an empty result, and an empty view is not proof of safety.
    Write-Host ("  Attack paths returned in this subscription view: {0}" -f $(if (-not $pathsRead) { 'unavailable: query failed' } elseif ($paths) { ($paths | ForEach-Object { "$($_.name) ($($_.riskLevel))" }) -join '; ' } else { 'none returned' }))
    Write-Host '  ServiceHub open findings by risk level (Defender CSPM):'
    $levels | Sort-Object { Get-RiskSort $_.riskLevel } | ForEach-Object { Write-Host ("    {0,-10} {1}" -f $_.riskLevel, $_.findings) }
    [void](Write-L12Evidence 'posture-score' ([ordered]@{ secureScore = $ss.properties.score; topControls = $controls; attackPathsReadSucceeded = $pathsRead; attackPaths = $paths; serviceHubRiskLevels = $levels }))
}

if ($Mode -in 'Findings', 'All') {
    Write-Host "== '$($pc.sharedKeyDisplayName)' across ServiceHub"
    $rows = Invoke-L12Graph -Query @"
securityresources
| where type == 'microsoft.security/assessments' and name == '$key'
| extend rid = tolower(tostring(properties.resourceDetails.Id))
| extend rg = tostring(split(rid, '/')[4]), resource = tostring(split(rid, '/')[8])
| where rg in ($groups)
| project resource, rg, status = tostring(properties.status.code), severity = tostring(properties.metadata.severity),
          riskLevel = tostring(properties.risk.level), riskFactors = strcat_array(properties.risk.riskFactors, ', '),
          statusChangeUtc = tostring(properties.status.statusChangeDate), assessmentId = id
"@
    $rows = @($rows | Sort-Object { Get-RiskSort $_.riskLevel }, resource)
    $rows | ForEach-Object {
        Write-Host ("  {0,-26} {1,-10} severity {2,-7} risk {3,-9} {4}" -f $_.resource, $_.status, $_.severity,
            $(if ($_.riskLevel) { $_.riskLevel } else { '-' }), $(if ($_.riskFactors) { "factors: $($_.riskFactors)" } else { '' }))
    }
    if (-not ($rows | Where-Object { $_.resource -eq $lab.storage })) { Write-Host "  $($lab.storage) isn't assessed yet. New resources usually appear within a few hours." }
    Write-Host "== Every open finding on $($lab.storage)"
    $mine = Invoke-L12Graph -Query @"
securityresources
| where type == 'microsoft.security/assessments' and tostring(properties.status.code) == 'Unhealthy'
| where tolower(tostring(properties.resourceDetails.Id)) == '$($lab.storageId.ToLower())'
| project recommendation = tostring(properties.displayName), severity = tostring(properties.metadata.severity),
          riskLevel = tostring(properties.risk.level), riskFactors = strcat_array(properties.risk.riskFactors, ', '), assessmentKey = name
"@
    $mine = @($mine | Sort-Object { Get-RiskSort $_.riskLevel }, recommendation)
    $mine | ForEach-Object { Write-Host ("  {0,-9} {1,-7} {2}" -f $(if ($_.riskLevel) { $_.riskLevel } else { '-' }), $_.severity, $_.recommendation) }
    if (-not $mine) { Write-Host '  none yet' }
    $sev = @($rows | ForEach-Object { $_.severity } | Where-Object { $_ } | Sort-Object -Unique)
    $risk = @($rows | ForEach-Object { $_.riskLevel } | Where-Object { $_ } | Sort-Object -Unique)
    Write-L12Verdict -Rows @(
        [ordered]@{ Check = 'Severity across ServiceHub stores'; Expected = 'one value'; Observed = $(if ($sev.Count -eq 1) { 'one value' } elseif ($sev.Count -eq 0) { 'not reported' } else { "$($sev.Count) values" }) }
        [ordered]@{ Check = 'Risk level across ServiceHub stores'; Expected = 'one value'; Observed = $(if ($risk.Count -gt 1) { 'varies' } elseif ($risk.Count -eq 1) { 'one value' } else { 'not rated' }) }
        [ordered]@{ Check = "$($lab.storage) assessed"; Expected = 'yes'; Observed = $(if ($rows | Where-Object { $_.resource -eq $lab.storage }) { 'yes' } else { 'not yet' }) }
    )
    [void](Write-L12Evidence 'posture-findings' ([ordered]@{ observedUtc = [DateTime]::UtcNow.ToString('o'); recommendation = $pc.sharedKeyDisplayName; assessmentKey = $key; acrossServiceHub = $rows; storeFindings = $mine }))
}

if ($Mode -eq 'Remediate') {
    Write-Host "== Remediate: prevent Shared Key access on $($lab.storage)"
    $before = Get-L12Fixture -Lab $lab
    $probeBefore = Test-SharedKeyPath
    if (-not $probeBefore.allowed) { throw 'The before request did not succeed. Restore the named lesson baseline before this comparison; no setting was changed.' }
    Write-Host ("  Before: allowSharedKeyAccess={0}; Shared Key request {1} ({2})" -f $before.allowSharedKeyAccess, $(if ($probeBefore.allowed) { 'ALLOWED' } else { 'REFUSED' }), $probeBefore.detail)
    $changedUtc = [DateTime]::UtcNow
    [void](Invoke-L12Az @('storage', 'account', 'update', '--name', $lab.storage, '--resource-group', $lab.resourceGroup, '--allow-shared-key-access', 'false', '--query', 'id'))
    $after = Get-L12Fixture -Lab $lab
    # The setting can take a few seconds to reach the data plane, so retry the refused-request proof.
    $probeAfter = $null
    foreach ($try in 1..8) { $probeAfter = Test-SharedKeyPath; if (-not $probeAfter.allowed) { break }; Start-Sleep -Seconds 10 }
    $entra = Invoke-L12Az -AllowFailure @('storage', 'container', 'list', '--account-name', $lab.storage, '--auth-mode', 'login', '--query', 'length(@)')
    Write-Host ("  After:  allowSharedKeyAccess={0}; Shared Key request {1} ({2})" -f $after.allowSharedKeyAccess, $(if ($probeAfter.allowed) { 'ALLOWED' } else { 'REFUSED' }), $probeAfter.detail)
    Write-Host ("  Your Entra request: {0}" -f $(if ($entra.ExitCode -eq 0) { "ALLOWED, listed $($entra.Stdout.Trim()) container(s)" } else { "REFUSED: $((($entra.Stderr -split "`n")[0]).Trim())" }))
    $receipt = @()
    foreach ($try in 1..6) {
        $receipt = @(Get-ActivityWrites -Hours 1 | Where-Object { (ConvertTo-L12UtcTime $_.timeUtc) -ge (ConvertTo-L12UtcTime $changedUtc) -and $_.caller -eq $cfg.operatorUpn })
        if ($receipt) { break }
        Start-Sleep -Seconds 30
    }
    if ($receipt) { $receipt | ForEach-Object { Write-Host ("  Activity log: {0}  {1}  by {2}  correlation {3}" -f $_.timeUtc, $_.operation, $_.caller, $_.correlationId) } }
    else { Write-Host '  Activity log: the write isn''t visible yet. Run -Mode Receipt in a few minutes.' }
    $status = Get-FixtureAssessment
    Write-Host ("  Defender assessment right now: {0}. Defender re-evaluates on its own cycle, so this lags the fix." -f $(if ($status) { $status.status } else { 'not assessed yet' }))
    $proof = Test-L12RemediationProof $probeBefore $probeAfter ($after.allowSharedKeyAccess -eq $false) $entra.ExitCode
    Write-Host "  Access comparison established: $proof; denial classification: $($probeAfter.outcome)"
    Write-L12Verdict -Rows @(
        [ordered]@{ Check = 'Shared Key request before'; Expected = 'ALLOWED'; Observed = $(if ($probeBefore.allowed) { 'ALLOWED' } else { 'REFUSED' }) }
        [ordered]@{ Check = 'allowSharedKeyAccess after'; Expected = 'False'; Observed = "$($after.allowSharedKeyAccess)" }
        [ordered]@{ Check = 'Shared Key request after'; Expected = 'REFUSED'; Observed = $(if ($probeAfter.allowed) { 'ALLOWED' } else { 'REFUSED' }) }
        [ordered]@{ Check = "Your Entra request after"; Expected = 'ALLOWED'; Observed = $(if ($entra.ExitCode -eq 0) { 'ALLOWED' } else { 'REFUSED' }) }
        [ordered]@{ Check = 'Activity log write by you'; Expected = 'found'; Observed = $(if ($receipt) { 'found' } else { 'not yet' }) }
    )
    [void](Write-L12Evidence 'posture-remediate' ([ordered]@{ changedUtc = $changedUtc.ToString('o'); before = $before; sharedKeyBefore = $probeBefore; after = $after; sharedKeyAfter = $probeAfter
        entraAfter = ($entra.ExitCode -eq 0); accessComparisonPassed = $proof; activityLog = $receipt; defenderAssessment = $status }))
    if (-not $proof) { Write-Warning 'The required before/denied-key/allowed-Entra comparison is incomplete. Inspect the recorded cause.'; exit 1 }
}

if ($Mode -eq 'Receipt') {
    Write-Host "== Handoff record for $($lab.storage)"
    $fx = Get-L12Fixture -Lab $lab
    $writes = Get-ActivityWrites -Hours 72
    $status = Get-FixtureAssessment
    $remaining = Invoke-L12Graph -Query @"
securityresources
| where type == 'microsoft.security/assessments' and tostring(properties.status.code) == 'Unhealthy'
| where tolower(tostring(properties.resourceDetails.Id)) == '$($lab.storageId.ToLower())'
| project recommendation = tostring(properties.displayName), riskLevel = tostring(properties.risk.level), riskFactors = strcat_array(properties.risk.riskFactors, ', ')
"@
    Write-Host ("  Settings: allowSharedKeyAccess={0}; publicNetworkAccess={1}; network default action={2}" -f $fx.allowSharedKeyAccess, $fx.publicNetworkAccess, $fx.networkDefaultAction)
    $writes | Select-Object -Last 3 | ForEach-Object { Write-Host ("  Write: {0} by {1}, correlation {2}" -f $_.timeUtc, $_.caller, $_.correlationId) }
    Write-Host ("  Shared-key finding: {0} (status changed {1})" -f $(if ($status) { $status.status } else { 'not assessed' }), $(if ($status) { $status.statusChangeUtc } else { '-' }))
    @($remaining) | ForEach-Object { Write-Host ("  Still open: {0} ({1})" -f $_.recommendation, $(if ($_.riskLevel) { "risk $($_.riskLevel)" } else { 'not rated' })) }
    [void](Write-L12Evidence 'posture-handoff' ([ordered]@{
        observedUtc = [DateTime]::UtcNow.ToString('o'); resource = $lab.storageId; findingId = $fixtureAssessment; recommendation = $pc.sharedKeyDisplayName
        settings = $fx; remediationReceipts = $writes; defenderStatus = $status; remainingExposure = $remaining
        logSources = @('Azure Activity log: Microsoft.Storage/storageAccounts/write with caller and correlation ID', 'Defender for Cloud assessment status history (securityresources)', 'Storage resource logs are not enabled on this store, which is itself a gap for Lesson 13')
    }))
}

if ($Mode -in 'Compliance', 'All') {
    Write-Host '== Regulatory compliance standards'
    $stds = Invoke-L12Graph -Query @"
securityresources
| where type == 'microsoft.security/regulatorycompliancestandards'
| project standard = name, state = tostring(properties.state), passed = toint(properties.passedControls), failed = toint(properties.failedControls), skipped = toint(properties.skippedControls)
"@
    $stds | ForEach-Object { Write-Host ("  {0,-38} {1,-7} passed {2,3}  failed {3,3}  skipped {4,3}" -f $_.standard, $_.state, $_.passed, $_.failed, $_.skipped) }
    Write-Host "== Controls that '$($pc.sharedKeyDisplayName)' feeds"
    $ctl = Invoke-L12Graph -Query @"
securityresources
| where type == 'microsoft.security/regulatorycompliancestandards/regulatorycompliancecontrols/regulatorycomplianceassessments' and name == '$key'
| extend parts = split(id, '/')
| project standard = tostring(parts[6]), control = tostring(parts[8]), state = tostring(properties.state), failedResources = toint(properties.failedResources), passedResources = toint(properties.passedResources)
"@
    $ctl | ForEach-Object { Write-Host ("  {0} control {1}: {2} ({3} failed, {4} passed resources)" -f $_.standard, $_.control, $_.state, $_.failedResources, $_.passedResources) }
    [void](Write-L12Evidence 'posture-compliance' ([ordered]@{ standards = $stds; sharedKeyControls = $ctl }))
}

if ($Mode -in 'Governance', 'All') {
    Write-Host '== Governance'
    $rules = Invoke-L12Rest -Path "$sub/providers/Microsoft.Security/governanceRules?api-version=2022-01-01-preview"
    $ruleRows = @(@($rules.value) | Where-Object { $_ } | ForEach-Object { [ordered]@{ name = $_.properties.displayName; owner = (Get-L12Value $_ 'properties.ownerSource.value'); days = (Get-L12Value $_ 'properties.remediationTimeframe'); disabled = (Get-L12Value $_ 'properties.isDisabled') } })
    Write-Host ("  Governance rules on the subscription: {0}" -f $(if ($ruleRows) { ($ruleRows | ForEach-Object { $_.name }) -join ', ' } else { 'none' }))
    $ga = Invoke-L12Rest -AllowNotFound -Path "$fixtureAssessment/governanceAssignments?api-version=2025-05-04"
    $gaRows = @(@(Get-L12Value $ga 'value') | Where-Object { $_ } | ForEach-Object { [ordered]@{ key = $_.name; owner = $_.properties.owner; dueUtc = $_.properties.remediationDueDate; gracePeriod = $_.properties.isGracePeriod } })
    Write-Host ("  Assignments on the store's shared-key finding: {0}" -f $(if ($gaRows) { ($gaRows | ForEach-Object { "$($_.owner), due $($_.dueUtc), grace period $($_.gracePeriod)" }) -join '; ' } else { 'none' }))
    [void](Write-L12Evidence 'posture-governance' ([ordered]@{ rules = $ruleRows; storeAssignments = $gaRows }))
}

if ($Mode -eq 'Assign') {
    $assessment = Get-FixtureAssessment
    if ((Get-L12AssessmentGate ([string](Get-L12Value $assessment 'status')) $true) -ne 'PASS') {
        throw "$($lab.storage) needs an Unhealthy shared-key assessment before this assignment demonstration. No assignment was written."
    }
    $due = [DateTime]::UtcNow.Date.AddDays([int]$pc.governanceDueDays).ToString('yyyy-MM-ddT00:00:00Z')
    $body = @{ properties = @{ owner = $cfg.operatorUpn; remediationDueDate = $due; isGracePeriod = $true
        governanceEmailNotification = @{ disableManagerEmailNotification = $true; disableOwnerEmailNotification = $true } } }
    $path = "$fixtureAssessment/governanceAssignments/$($pc.governanceAssignmentKey)?api-version=2025-05-04"
    [void](Invoke-L12Rest -Method put -Path $path -Body $body)
    $back = Invoke-L12Rest -Path $path
    $verified = Test-L12AssignmentProof $back "$fixtureAssessment/governanceAssignments/$($pc.governanceAssignmentKey)" $cfg.operatorUpn (ConvertTo-L12UtcTime $due)
    Write-Host ("== Assigned: owner {0}, due {1}, grace period {2}" -f $back.properties.owner, $back.properties.remediationDueDate, $back.properties.isGracePeriod)
    Write-L12Verdict -Rows @(
        [ordered]@{ Check = 'Owner'; Expected = "$($cfg.operatorUpn)"; Observed = "$($back.properties.owner)" }
        [ordered]@{ Check = 'Due date (UTC)'; Expected = (ConvertTo-L12UtcTime $due).ToString('yyyy-MM-dd'); Observed = $(if ($back.properties.remediationDueDate) { (ConvertTo-L12UtcTime $back.properties.remediationDueDate).ToString('yyyy-MM-dd') } else { 'missing' }) }
        [ordered]@{ Check = 'Grace period'; Expected = 'True'; Observed = "$($back.properties.isGracePeriod)" }
        [ordered]@{ Check = 'Read back as written'; Expected = 'yes'; Observed = $(if ($verified) { 'yes' } else { 'no' }) }
    )
    [void](Write-L12Evidence 'posture-assign' ([ordered]@{ observedUtc = [DateTime]::UtcNow.ToString('o'); assessmentBefore = $assessment
        assignmentId = $back.id; owner = $back.properties.owner; dueUtc = $back.properties.remediationDueDate; gracePeriod = $back.properties.isGracePeriod
        notifications = $back.properties.governanceEmailNotification; assignmentVerified = $verified; readback = $back }))
    if (-not $verified) { throw 'The governance assignment did not read back with the expected scope, owner, due date, grace period and disabled notifications.' }
}

if (($Mode -in 'Secrets', 'All') -and -not $pc.secretFindingVm) {
    # The November 5 lab on sub-ttt-labs-primary deploys no VM, so there's nothing for secret scanning to read.
    Write-Host '== Secret scanning: no virtual machine in this lab, so there is no machine finding to read.'
}
if (($Mode -in 'Secrets', 'All') -and $pc.secretFindingVm) {
    Write-Host "== Secret scanning on $($pc.secretFindingVm)"
    $s = Invoke-L12Graph -Query @"
securityresources
| where type == 'microsoft.security/assessments' and name == '$($pc.secretFindingAssessment)'
| where tolower(tostring(properties.resourceDetails.Id)) == tolower('$sub/resourceGroups/$($pc.secretFindingResourceGroup)/providers/Microsoft.Compute/virtualMachines/$($pc.secretFindingVm)')
| project finding = tostring(properties.displayName), status = tostring(properties.status.code), severity = tostring(properties.metadata.severity),
          riskLevel = tostring(properties.risk.level), riskFactors = strcat_array(properties.risk.riskFactors, ', '),
          secretType = tostring(properties.additionalData.SecretTypeDisplayName), scanner = tostring(properties.additionalData.SecretScannerName),
          firstEvaluationUtc = tostring(properties.status.firstEvaluationDate)
"@
    $s | ForEach-Object { Write-Host ("  {0}: {1}; severity {2}, risk {3} ({4}); scanner {5}" -f $_.finding, $_.status, $_.severity, $_.riskLevel, $_.riskFactors, $_.scanner) }
    if (-not $s) { Write-Host '  no secret finding on record' }
    [void](Write-L12Evidence 'posture-secrets' ([ordered]@{ vm = $pc.secretFindingVm; finding = $s }))
}
