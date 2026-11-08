<#
.SYNOPSIS
    Deletes the whole Lesson 10 lab. Your call, not a routine step.
.DESCRIPTION
    Asks you to type the resource group name unless -Force is given. Deletes, in this order, and
    checks each object's lab marker before it deletes it:
      1. the two report-only Conditional Access policies (by exact name, report-only state only);
      2. the two agent identities (only if they come from the lab blueprint);
      3. the blueprint principal and the blueprint (only with the lab description and tag);
      4. rg-sc500-l10-agents (only with the managedBy tag).
    Deleted directory objects sit in Entra deleted items for 30 days. Afterward the demos can't run
    until Deploy-L10Lab.ps1 -Deploy builds everything again, with new IDs.
.PARAMETER Force Skip the typed confirmation.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-10\Remove-L10Lab.ps1
#>
[CmdletBinding()]
param([switch]$Force)
. (Join-Path $PSScriptRoot 'L10.Common.ps1')
$cfg = $script:L10Config; $dir = $cfg.directory; $rg = $cfg.resourceGroup
[void](Assert-L10Context)
if (-not $Force) {
    $typed = Read-Host "This deletes $rg, the lab's agent identities, its blueprint, and its two report-only policies. Type the resource group name to continue"
    if ($typed -ne $rg) { Write-Host 'Nothing deleted.'; return }
}
$log = [Collections.Generic.List[string]]::new()

foreach ($name in $cfg.conditionalAccess.highRisk, $cfg.conditionalAccess.unapproved) {
    $p = Get-L10Policy $name
    if (-not $p) { continue }
    if ($p.state -ne 'enabledForReportingButNotEnforced') { throw "$name isn't report-only. Someone changed it by hand; stopping before deleting anything else." }
    [void](Invoke-L10Rest -Method delete -Path "/beta/identity/conditionalAccess/policies/$($p.id)"); $log.Add("deleted policy $name")
}

$bp = Get-L10Blueprint
if ($bp -and $bp.description -ne $dir.marker) { throw "Blueprint $($dir.blueprint) has no lab marker. Stopping." }
foreach ($which in 'assistant', 'triage') {
    $a = Get-L10Agent $which
    if (-not $a) { continue }
    if (-not $bp -or $a.agentIdentityBlueprintId -ne $bp.appId) { throw "$($a.displayName) doesn't come from the lab blueprint. Stopping." }
    [void](Invoke-L10Rest -Method delete -Path "/beta/servicePrincipals/$($a.id)"); $log.Add("deleted agent identity $($a.displayName)")
}
if ($bp) {
    $bpp = Get-L10BlueprintPrincipal -AppId $bp.appId
    if ($bpp) { [void](Invoke-L10Rest -Method delete -Path "/v1.0/servicePrincipals/$($bpp.id)"); $log.Add('deleted the blueprint principal') }
    if (@($bp.tags) -notcontains $dir.tag) { throw "The blueprint isn't tagged $($dir.tag). Stopping before deleting it." }
    [void](Invoke-L10Rest -Method delete -Path "/v1.0/applications/$($bp.id)"); $log.Add("deleted blueprint $($bp.displayName)")
}

if (Invoke-L10Az @('group', 'exists', '--name', $rg)) {
    $group = Invoke-L10Az @('group', 'show', '--name', $rg)
    if ((Get-L10Value $group 'tags.managedBy') -ne $cfg.managedBy) { throw "$rg isn't tagged managedBy=$($cfg.managedBy). Stopping." }
    Invoke-L10Az -Raw @('group', 'delete', '--name', $rg, '--yes', '--no-wait') | Out-Null; $log.Add("started deleting $rg")
}
$log | ForEach-Object { "  $_" } | Out-Host
[void](Write-L10Evidence 'lab-removed' ([ordered]@{ removedUtc = [DateTime]::UtcNow.ToString('o'); steps = $log }))
