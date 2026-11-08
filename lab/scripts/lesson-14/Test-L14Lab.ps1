<#
.SYNOPSIS
    Read-only readiness check for the SC-500 Lesson 14 lab. Exits 1 on any FAIL.
.DESCRIPTION
    Checks the analytics rule, the automation rule and its playbook, the two role assignments that
    let them run, the saved hunting queries, the workbook, and Lesson 13's custom table plan.
    -Recording also requires the selected fixture incident, automation tags, a matching Succeeded
    playbook run and an exported Purview Audit record attached by record ID, which is what the demo needs on screen. Tenant-level items (the Defender portal
    connection, the Microsoft 365 connector) are reported as INFO because they're your decisions.
.PARAMETER Recording Require the selected case execution and the captured Audit record attached to it.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Test-L14Lab.ps1 -Recording
#>
[CmdletBinding()]
param([switch]$Recording)
. (Join-Path $PSScriptRoot 'L14.Common.ps1')
$cfg = $script:L14Config
[void](Assert-L14Context)
$l13 = Get-L14L13Lab
$lab = Get-L14Outputs
$ws = $l13.workspaceId
$results = [Collections.Generic.List[object]]::new()
function Add-Result { param($Name, $Status, $Detail) $results.Add([pscustomobject][ordered]@{ Check = $Name; Status = $Status; Detail = $Detail }) }

$rule = Invoke-L14Rest -AllowNotFound -Path "$ws/providers/Microsoft.SecurityInsights/alertRules/$($cfg.names.analyticsRuleId)?api-version=2025-09-01"
if ($rule -and $rule.properties.enabled -and $rule.properties.incidentConfiguration.createIncident) { Add-Result 'Analytics rule' 'PASS' "$($rule.properties.displayName), every $($rule.properties.queryFrequency), creates incidents" }
else { Add-Result 'Analytics rule' 'FAIL' 'missing, disabled, or not creating incidents' }

$auto = Invoke-L14Rest -AllowNotFound -Path "$ws/providers/Microsoft.SecurityInsights/automationRules/$($cfg.names.automationRuleId)?api-version=2025-09-01"
$runsOurs = $auto -and @($auto.properties.actions | Where-Object { $_.actionType -eq 'RunPlaybook' -and $_.actionConfiguration.logicAppResourceId -eq $lab.playbookId }).Count -eq 1
$tagAction = @($auto.properties.actions | Where-Object actionType -eq 'ModifyProperties')
$playAction = @($auto.properties.actions | Where-Object actionType -eq 'RunPlaybook')
$tagNames = @($tagAction | ForEach-Object { $_.actionConfiguration.labels | ForEach-Object labelName })
$allTags = @($cfg.names.incidentTags | Where-Object { $tagNames -notcontains $_ }).Count -eq 0
$ordered = $tagAction.Count -eq 1 -and $playAction.Count -eq 1 -and $tagAction[0].order -lt $playAction[0].order
$narrowed = ($auto.properties.triggeringLogic.conditions | ConvertTo-Json -Depth 20 -Compress).Contains("$ws/providers/Microsoft.SecurityInsights/alertRules/$($cfg.names.analyticsRuleId)")
if ($auto -and $auto.properties.triggeringLogic.isEnabled -and $runsOurs -and $allTags -and $ordered -and $narrowed) { Add-Result 'Automation rule' 'PASS' 'enabled; tags, then runs the response playbook' }
else { Add-Result 'Automation rule' 'FAIL' 'missing, disabled, or not pointing at the playbook' }

$w = Invoke-L14Rest -AllowNotFound -Path "$($lab.playbookId)?api-version=2019-05-01"
if ($w -and $w.properties.state -eq 'Enabled' -and $w.identity.principalId) { Add-Result 'Playbook' 'PASS' "$($w.name) enabled with a managed identity" } else { Add-Result 'Playbook' 'FAIL' 'missing, disabled, or no managed identity' }

$asi = Invoke-L14Az -NoSubscription -Raw @('ad', 'sp', 'show', '--id', $cfg.roles.azureSecurityInsightsAppId, '--query', 'id', '--output', 'tsv')
foreach ($g in @(
    @{ n = 'Sentinel may run playbooks'; p = $asi; s = "/subscriptions/$($cfg.subscriptionId)/resourceGroups/$($cfg.resourceGroup)"; r = $cfg.roles.sentinelAutomationContributor }
    @{ n = 'Playbook may comment'; p = $(if ($w) { $w.identity.principalId }); s = $ws; r = $cfg.roles.sentinelResponder })) {
    # @() outside the if: an if statement unrolls a one-item array into a bare string.
    $found = @(if ($g.p) { Invoke-L14Az @('role', 'assignment', 'list', '--assignee', $g.p, '--scope', $g.s, '--query', "[?ends_with(roleDefinitionId, '$($g.r)')].roleDefinitionName") })
    if ($found) { Add-Result $g.n 'PASS' "$($found[0]) at $(($g.s -split '/')[-1])" } else { Add-Result $g.n 'FAIL' 'role assignment missing' }
}

foreach ($n in @($cfg.names.huntExportActor, $cfg.names.huntStoreKeys)) {
    $s = Invoke-L14Rest -AllowNotFound -Path "$ws/savedSearches/$n`?api-version=2020-08-01"
    if ($s -and $s.properties.category -eq 'Hunting Queries') { Add-Result "Hunting query $n" 'PASS' $s.properties.displayName } else { Add-Result "Hunting query $n" 'FAIL' 'missing' }
}

$wb = Invoke-L14Rest -AllowNotFound -Path "$($lab.workbookId)?api-version=2022-04-01"
if ($wb -and $wb.properties.category -eq 'sentinel') { Add-Result 'Workbook' 'PASS' $wb.properties.displayName } else { Add-Result 'Workbook' 'FAIL' 'missing' }

$t = Invoke-L14Rest -AllowNotFound -Path "$ws/tables/$($cfg.l13.customTable)?api-version=2023-09-01"
if ($t -and $t.properties.plan -eq 'Analytics') { Add-Result 'Custom table plan' 'PASS' "$($cfg.l13.customTable) on Analytics (rules can query it)" } else { Add-Result 'Custom table plan' 'FAIL' 'not on the Analytics plan' }

if (Test-Path -LiteralPath (Join-Path $script:L14State 'notebook-params.json')) { Add-Result 'Notebook parameters' 'PASS' 'private parameters file present' } else { Add-Result 'Notebook parameters' 'FAIL' 'run Deploy-L14Lab.ps1 -Deploy' }

if ($Recording) {
    try {
        $proof = Get-L14CaseProof -L13Lab $l13 -Lab $lab
        Add-Result 'Selected case execution' $(if ($proof.executionPassed -and $proof.openForHandoff) { 'PASS' } else { 'FAIL' }) ($proof | ConvertTo-Json -Depth 8 -Compress)
        $audit = Test-L14AuditCapture -L13Lab $l13
        Add-Result 'Purview Audit record attached' $(if ($audit.passed) { 'PASS' } else { 'FAIL' }) $audit.detail
    } catch { Add-Result 'Recording evidence' 'FAIL' $_.Exception.Message }
}

# The incident provider shows which engine created the latest incident: "Microsoft XDR" means the
# workspace is connected to the Defender portal. The connection itself is your step, never a script's.
$latest = @(Get-L14Incidents -L13Lab $l13 -Top 5) | Select-Object -First 1
$provider = if ($latest) { "$($latest.properties.providerName) (Defender incident $($latest.properties.providerIncidentId))" } else { 'no incident yet' }
Add-Result 'Defender portal connection' 'INFO' "latest incident provider: $provider; connecting or disconnecting the workspace is your step"
try { $o = @(Invoke-L14Query -Lab $l13 -Kql 'OfficeActivity | take 1' -Timespan 'P7D'); $m365 = if ($o) { 'rows present' } else { 'table empty' } } catch { $m365 = 'query unavailable; connection status not established by this error' }
Add-Result 'Microsoft 365 connector' 'INFO' "$m365 (your decision; Purview Audit in the Defender portal is the source of record)"

$results | Format-Table -AutoSize -Wrap | Out-Host
[void](Write-L14Evidence 'test' ([ordered]@{ testedUtc = [DateTime]::UtcNow.ToString('o'); recording = [bool]$Recording; results = $results }))
if (@($results | Where-Object Status -eq 'FAIL').Count) { exit 1 }
