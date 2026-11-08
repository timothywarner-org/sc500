<#
.SYNOPSIS
    Your step after Lesson 15: removes everything Lesson 14 added and leaves Lesson 13 intact.
.DESCRIPTION
    Deletes the automation rule, the analytics rule, the two saved hunting queries, and the playbook
    identity's role on the workspace (all on Lesson 13's workspace), then deletes
    the response resource group after checking its ownership tag. Incidents stay in the workspace as
    history. Remove Lesson 13 separately with Remove-L13Lab.ps1.
.PARAMETER AfterLesson15
    Explicit release of the retained L14 dependency, only after L15 recording is complete.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Remove-L14Lab.ps1
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param([switch]$AfterLesson15)
. (Join-Path $PSScriptRoot 'L14.Common.ps1')
$cfg = $script:L14Config
[void](Assert-L14Context)
# Course-wide dependency must be consciously released before destructive cleanup, even with -Confirm:false.
if ((Get-L14PinnedCase) -and -not $AfterLesson15) { throw 'L15 depends on this lab. Removal requires -AfterLesson15 after its recording is complete.' }
$l13 = Get-L14L13Lab
$ws = $l13.workspaceId
$rg = Invoke-L14Az -AllowFailure @('group', 'show', '--name', $cfg.resourceGroup)
$rgObj = if ($rg.ExitCode -eq 0) { $rg.Stdout | ConvertFrom-Json } else { $null }
if (-not $rgObj) { throw 'Cannot verify the Lesson 14 ownership group. No resources were deleted.' }
if ($rgObj.tags.managedBy -ne $cfg.managedBy) { throw "$($cfg.resourceGroup) isn't tagged managedBy=$($cfg.managedBy); refusing to delete it." }
if (-not $PSCmdlet.ShouldProcess("Lesson 14 detection resources on $($cfg.l13.workspace) and $($cfg.resourceGroup)", 'Delete')) { return }

$playbookPrincipal = $null
if ($rgObj) {
    $w = Invoke-L14Rest -AllowNotFound -Path "/subscriptions/$($cfg.subscriptionId)/resourceGroups/$($cfg.resourceGroup)/providers/Microsoft.Logic/workflows/$($cfg.names.playbook)?api-version=2019-05-01"
    if ($w) { $playbookPrincipal = $w.identity.principalId }
}
foreach ($p in @(
    "$ws/providers/Microsoft.SecurityInsights/automationRules/$($cfg.names.automationRuleId)?api-version=2025-09-01"
    "$ws/providers/Microsoft.SecurityInsights/alertRules/$($cfg.names.analyticsRuleId)?api-version=2025-09-01"
    "$ws/savedSearches/$($cfg.names.huntExportActor)?api-version=2020-08-01"
    "$ws/savedSearches/$($cfg.names.huntStoreKeys)?api-version=2020-08-01")) {
    [void](Invoke-L14Rest -Method delete -AllowNotFound -Path $p)
    Write-Host "Deleted $((($p -split '\?')[0] -split '/')[-1])"
}
if ($playbookPrincipal) {
    [void](Invoke-L14Az @('role', 'assignment', 'delete', '--assignee', $playbookPrincipal, '--scope', $ws, '--role', $cfg.roles.sentinelResponder))
    Write-Host 'Removed the playbook identity''s Responder role on the workspace.'
}
if ($rgObj) {
    [void](Invoke-L14Az @('group', 'delete', '--name', $cfg.resourceGroup, '--yes'))
    Write-Host "Deleted $($cfg.resourceGroup) (playbook, connection, workbook, and Sentinel's role there)."
}
[void](Write-L14Evidence 'remove' ([ordered]@{ removedUtc = [DateTime]::UtcNow.ToString('o') }))
