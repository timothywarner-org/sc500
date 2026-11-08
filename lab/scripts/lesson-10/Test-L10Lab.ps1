<#
.SYNOPSIS
    Read-only readiness check for the Lesson 10 lab at CTSO-L10-BASELINE.
.DESCRIPTION
    PASS means the check matches the baseline the demos start from. WARN means something needs a
    look before the demo but doesn't break a demo. FAIL means a demo would start from the wrong state;
    run Reset-L10Lab.ps1 (or Deploy-L10Lab.ps1 -Deploy) and check again. Changes nothing, creates
    no credential, and requests no agent token; -Mode Token is the proof that the flow works.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-10\Test-L10Lab.ps1
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L10.Common.ps1')
$cfg = $script:L10Config; $dir = $cfg.directory
[void](Assert-L10Context)
$checks = [Collections.Generic.List[object]]::new()
function Add-Check([string]$Name, $Expected, $Actual, [switch]$WarnOnly) {
    $ok = "$Expected" -eq "$Actual"
    $checks.Add([pscustomobject]@{ Result = if ($ok) { 'PASS' } elseif ($WarnOnly) { 'WARN' } else { 'FAIL' }; Check = $Name; Expected = "$Expected"; Actual = "$Actual" })
}
$sponsor = Get-L10User $dir.sponsorUpn

# Directory half
$bp = Get-L10Blueprint
Add-Check "Blueprint $($dir.blueprint)" 'present' $(if ($bp) { 'present' } else { 'missing' })
if ($bp) {
    Add-Check 'Blueprint lab marker' $dir.marker $bp.description
    Add-Check 'Blueprint secrets at rest' 0 @(@(Get-L10Value $bp 'passwordCredentials') | Where-Object { $_ }).Count
    Add-Check 'Blueprint principal' 'present' $(if (Get-L10BlueprintPrincipal -AppId $bp.appId) { 'present' } else { 'missing' })
}
foreach ($which in 'assistant', 'triage') {
    $a = Get-L10Agent $which
    Add-Check "Agent identity $($dir.$which)" 'present' $(if ($a) { 'present' } else { 'missing' })
    if (-not $a) { continue }
    Add-Check "$which enabled" 'True' $a.accountEnabled
    Add-Check "$which from the lab blueprint" 'True' ($bp -and $a.agentIdentityBlueprintId -eq $bp.appId)
    $s = @((Invoke-L10Rest -Path "/beta/servicePrincipals/$($a.id)/microsoft.graph.agentIdentity/sponsors").value)
    Add-Check "$which sponsor" $sponsor.userPrincipalName ((@($s | ForEach-Object { Get-L10Value $_ 'userPrincipalName' }) | Where-Object { $_ }) -join ',')
}
$assistant = Get-L10Agent assistant
foreach ($pair in @(@($cfg.conditionalAccess.highRisk, 'high', ''), @($cfg.conditionalAccess.unapproved, '', $assistant.id))) {
    $name, $risk, $exclude = $pair
    $p = Get-L10Policy $name
    Add-Check "Policy $name" 'enabledForReportingButNotEnforced' $(if ($p) { $p.state } else { 'missing' })
    if (-not $p) { continue }
    Add-Check "$name targets all agent identities" 'All' (@(Get-L10Value $p 'conditions.clientApplications.includeAgentIdServicePrincipals') -join ',')
    Add-Check "$name agent risk" $risk ("$(Get-L10Value $p 'conditions.agentIdRiskLevels')")
    Add-Check "$name excludes" $exclude ((@(Get-L10Value $p 'conditions.clientApplications.excludeAgentIdServicePrincipals') | Where-Object { $_ }) -join ',')
    Add-Check "$name grant" 'block' (@(Get-L10Value $p 'grantControls.builtInControls') -join ',')
}

# Azure half
$group = Invoke-L10Az @('group', 'show', '--name', $cfg.resourceGroup)
Add-Check 'Resource group tag managedBy' $cfg.managedBy (Get-L10Value $group 'tags.managedBy')
$lab = Get-L10Outputs
$st = Invoke-L10Rest -Path "$($lab.storageId)?api-version=2023-05-01"
Add-Check "$($lab.storage) shared key access" 'False' $st.properties.allowSharedKeyAccess
Add-Check "$($lab.storage) public blob access" 'False' $st.properties.allowBlobPublicAccess
$blobs = foreach ($c in $cfg.names.containers) { @(Invoke-L10Az @('storage', 'blob', 'list', '--auth-mode', 'login', '--account-name', $lab.storage, '--container-name', $c, '--query', '[].name')) | ForEach-Object { "$c/$_" } }
Add-Check 'Fixture blobs' (@($cfg.fixtures | ForEach-Object { "$($_.container)/$($_.blob)" } | Sort-Object) -join ' ') (@($blobs | Sort-Object) -join ' ')
$f = [uri]::EscapeDataString("principalId eq '$($assistant.id)'")
$ra = @((Invoke-L10Rest -Path "/subscriptions/$($cfg.subscriptionId)/providers/Microsoft.Authorization/roleAssignments?`$filter=$f&api-version=2022-04-01").value)
Add-Check 'Assistant role scope (too broad on purpose)' 'storage account' (@($ra | ForEach-Object { if ($_.properties.scope -match '/containers/') { 'container' } elseif ($_.properties.scope -match '/storageAccounts/[^/]+$') { 'storage account' } else { $_.properties.scope } }) -join ',')
$triage = Get-L10Agent triage
$f = [uri]::EscapeDataString("principalId eq '$($triage.id)'")
$rt = @((Invoke-L10Rest -Path "/subscriptions/$($cfg.subscriptionId)/providers/Microsoft.Authorization/roleAssignments?`$filter=$f&api-version=2022-04-01").value)
Add-Check 'Triage role scope' 'container tickets' (@($rt | ForEach-Object { if ($_.properties.scope -match '/containers/([^/]+)$') { "container $($Matches[1])" } else { $_.properties.scope } }) -join ',')

[void](Write-L10Evidence 'readiness' $checks)
$fails = @($checks | Where-Object Result -eq 'FAIL').Count
$warns = @($checks | Where-Object Result -eq 'WARN').Count
if ($fails) { "NOT READY: $fails check(s) failed. Reset-L10Lab.ps1 restores the baseline; Deploy-L10Lab.ps1 -Deploy rebuilds anything missing." }
else { "BASELINE CHECK PASSED: $($cfg.baseline) ($warns warning(s)). Run Invoke-L10AgentDemo.ps1 -Mode Token to prove the agent flow itself." }
$checks | Format-Table -AutoSize | Out-String -Width 220
if ($fails) { exit 1 }
