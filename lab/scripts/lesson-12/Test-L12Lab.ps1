<#
.SYNOPSIS
    Readiness check for the SC-500 Lesson 12 lab (CTSO-L12-BASELINE). Read-only.
.DESCRIPTION
    Prints PASS, WARN, or FAIL for what the demos depend on:
      - the deployment record, the export store, and its deliberate Shared Key fault
      - the store's Defender for Storage exclusion (idle) and your data role on it
      - whether the store is staged for a take (container present) and anything left from a take
        (governance assignment, override on)
      - Defender CSPM and Defender for Storage on for the subscription, and whether Defender has
        assessed the store yet
      - the EASM workspace, its free-trial days left, and the discovery run
    Without -Recording, the idle baseline is expected and staged items are WARNs (they bill).
    With -Recording, the store must be staged, so a missing container is a FAIL.
    Exits 1 if any check fails.
.PARAMETER Recording Check readiness for a take instead of the idle baseline.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Test-L12Lab.ps1
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Test-L12Lab.ps1 -Recording
#>
[CmdletBinding()]
param([switch]$Recording)
. (Join-Path $PSScriptRoot 'L12.Common.ps1')
. (Join-Path $PSScriptRoot 'L12.Checks.ps1')
$cfg = $script:L12Config
[void](Assert-L12Context)
$lab = Get-L12Outputs
$sub = "/subscriptions/$($cfg.subscriptionId)"
$results = [System.Collections.Generic.List[object]]::new()
function Check([string]$Name, [bool]$Ok, [string]$Detail, [switch]$WarnOnly) {
    $state = if ($Ok) { 'PASS' } elseif ($WarnOnly) { 'WARN' } else { 'FAIL' }
    $results.Add([pscustomobject]@{ check = $Name; result = $state; detail = $Detail })
    Write-Host ("  {0}  {1}: {2}" -f $state, $Name, $Detail)
}

$fx = Get-L12Fixture -Lab $lab
Check 'Shared Key fault in place' ($fx.allowSharedKeyAccess -eq $true) "allowSharedKeyAccess=$($fx.allowSharedKeyAccess) (demo 12.1 turns it off; Reset turns it back on)" -WarnOnly:(-not $Recording)
Check 'Store otherwise hardened' ($fx.allowBlobPublicAccess -eq $false -and $fx.minimumTlsVersion -eq 'TLS1_2') "anonymous blob access $($fx.allowBlobPublicAccess), TLS $($fx.minimumTlsVersion)"
# The archive store is the comparison for demo 12.1: same Shared Key fault, no public network path.
$ar = Get-L12Fixture -Lab ([pscustomobject]@{ storageId = $lab.archiveStorageId })
Check 'Archive store: same fault, no public network' ($ar.allowSharedKeyAccess -eq $true -and $ar.publicNetworkAccess -eq 'Disabled') "$($lab.archiveStorage): allowSharedKeyAccess=$($ar.allowSharedKeyAccess), publicNetworkAccess=$($ar.publicNetworkAccess)"

$dfs = Invoke-L12Rest -AllowNotFound -Path "$($lab.storageId)/providers/Microsoft.Security/defenderForStorageSettings/current?api-version=2025-01-01"
$dfsOn = (Get-L12Value $dfs 'properties.isEnabled') -eq $true
$dfsOverride = (Get-L12Value $dfs 'properties.overrideSubscriptionLevelSettings') -eq $true
Check 'Defender for Storage excluded on the store' ((-not $dfsOn) -and $dfsOverride) "isEnabled=$(Get-L12Value $dfs 'properties.isEnabled'), override=$(Get-L12Value $dfs 'properties.overrideSubscriptionLevelSettings') (on only between demo 12.2 and Reset)" -WarnOnly:(-not $Recording)

$me = Invoke-L12Az -NoSubscription @('ad', 'signed-in-user', 'show', '--query', 'id', '--output', 'tsv') -Raw
$owner = @(Invoke-L12Az @('role', 'assignment', 'list', '--assignee', $me, '--scope', $lab.storageId, '--role', $cfg.roles.storageBlobDataOwner, '--query', '[].id'))
Check 'You hold Storage Blob Data Owner on the store' ($owner.Count -ge 1) 'needed to upload with Entra and read the scan verdict tag'
$retired = @(Invoke-L12Az @('role', 'assignment', 'list', '--assignee', $me, '--scope', $lab.storageId, '--role', $cfg.roles.retiredStorageBlobDataContributor, '--query', '[].id'))
Check 'No leftover Contributor assignment' ($retired.Count -eq 0) "$($retired.Count) found; Deploy-L12Lab.ps1 -Deploy removes it" -WarnOnly

$containers = @(Invoke-L12Az @('storage', 'container-rm', 'list', '--resource-group', $lab.resourceGroup, '--storage-account', $lab.storage, '--query', '[].name'))
if ($Recording) { Check 'Store staged for a take' ($containers -contains $lab.container) "containers: $(if ($containers) { $containers -join ', ' } else { 'none; run Deploy-L12Lab.ps1 -Stage' })" }
else { Check 'Store idle (no containers)' ($containers.Count -eq 0) "containers: $(if ($containers) { ($containers -join ', ') + ' (Defender CSPM bills the store while one exists; Reset removes it)' } else { 'none' })" -WarnOnly }

$ga = @(@(Get-L12Value (Invoke-L12Rest -AllowNotFound -Path "$($lab.storageId)/providers/Microsoft.Security/assessments/$($cfg.posture.sharedKeyAssessment)/governanceAssignments?api-version=2025-05-04") 'value') | Where-Object { $_ })
Check 'No governance assignment left over' ($ga.Count -eq 0) $(if ($ga) { "$($ga.Count) on the store's finding; remove only the lab's fixed assignment" } else { 'none' }) -WarnOnly:(-not $Recording)

$cspm = Invoke-L12Rest -Path "$sub/providers/Microsoft.Security/pricings/CloudPosture?api-version=2024-01-01"
Check 'Defender CSPM on' ($cspm.properties.pricingTier -eq 'Standard') "$($cspm.properties.pricingTier); risk levels, attack paths and governance need it"
$st = Invoke-L12Rest -Path "$sub/providers/Microsoft.Security/pricings/StorageAccounts?api-version=2024-01-01"
Check 'Defender for Storage plan on' ($st.properties.pricingTier -eq 'Standard') "$($st.properties.pricingTier) $(Get-L12Value $st 'properties.subPlan')" -WarnOnly

$as = Invoke-L12Rest -AllowNotFound -Path "$($lab.storageId)/providers/Microsoft.Security/assessments/$($cfg.posture.sharedKeyAssessment)?api-version=2021-06-01"
$assessmentStatus = [string](Get-L12Value $as 'properties.status.code')
$assessmentGate = Get-L12AssessmentGate $assessmentStatus ([bool]$Recording)
Check 'Defender has assessed the staged fault' ($assessmentGate -eq 'PASS') $(if ($as) { "shared-key finding $assessmentStatus; needs Unhealthy for the assignment demo" } else { 'not yet; assignment demonstration is unavailable' }) -WarnOnly:($assessmentGate -eq 'WARN')

$ws = Invoke-L12Rest -AllowNotFound -Path "$($lab.easmWorkspaceId)?api-version=2023-04-01-preview"
Check 'EASM workspace' ($null -ne $ws) "$($lab.easmWorkspace) in $($lab.easmLocation)"
if ($ws) {
    # Only Approved assets bill. Whether a trial covers this workspace depends on the tenant's first EASM
    # resource, so this reports the age and leaves the bill to -Mode Billable.
    $age = [DateTime]::UtcNow - ([DateTime](Get-L12Value $ws 'systemData.createdAt')).ToUniversalTime()
    Check 'EASM workspace age' $true ("{0:N1} days; Approved assets bill per day (Invoke-L12EasmDemo.ps1 -Mode Billable)" -f $age.TotalDays)
    $g = Invoke-L12Easm -Path "discoGroups/$($cfg.names.discoveryGroup)"
    $runState = Get-L12Value $g.Body 'latestRun.state'
    if ($runState -eq 'failed' -or $g.Status -ge 300) { Check 'EASM discovery run' $false "HTTP $($g.Status), state $runState" }
    else { Check 'EASM discovery run' ($runState -eq 'completed') "state $runState (Invoke-L12EasmDemo.ps1 -Mode Inventory reads what it found)" -WarnOnly }
}

[void](Write-L12Evidence 'test' ([ordered]@{ testedUtc = [DateTime]::UtcNow.ToString('o'); recording = [bool]$Recording; results = $results }))
$fail = @($results | Where-Object result -eq 'FAIL').Count
$warn = @($results | Where-Object result -eq 'WARN').Count
Write-Host ("Result: {0}. {1} warning(s)." -f $(if ($fail) { "$fail check(s) FAILED" } else { 'ready' }), $warn)
if ($fail) { exit 1 }
