<#
.SYNOPSIS
    Deletes the whole SC-500 Lesson 11 lab. Your step, after you finish the lesson.
.DESCRIPTION
    Removes rg-servicehubai-prod-eastus2 and everything in it (the Foundry resource, project, guardrail,
    blocklist, model deployment, agent, workspace, and any gateway), then purges the soft-deleted
    Foundry resource and any soft-deleted gateway so no name stays reserved. Nothing outside the
    group is touched: the subscription's Defender plans stay exactly as they are.
    This is a separate, explicitly selected action. Reset-L11Lab.ps1 is the routine cleanup.
.PARAMETER Confirm Asks before deleting (default). Pass -Confirm:$false only if you mean it.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-11\Remove-L11Lab.ps1
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param()
. (Join-Path $PSScriptRoot 'L11.Common.ps1')
$cfg = $script:L11Config
[void](Assert-L11Context)
$lab = Get-L11Outputs
if ($PSCmdlet.ShouldProcess($cfg.resourceGroup, 'Delete the Lesson 11 resource group and purge its soft-deleted resources')) {
    & (Join-Path $PSScriptRoot 'Reset-L11Lab.ps1')
    Write-Host "Deleting $($cfg.resourceGroup) (several minutes)."
    [void](Invoke-L11Az -Raw @('group', 'delete', '--name', $cfg.resourceGroup, '--yes'))
    [void](Invoke-L11Az -Raw -AllowFailure @('cognitiveservices', 'account', 'purge', '--location', $cfg.location, '--resource-group', $cfg.resourceGroup, '--name', $lab.foundry))
    $still = Invoke-L11Az -AllowFailure @('group', 'show', '--name', $cfg.resourceGroup)
    Write-Host $(if ($still.ExitCode -ne 0) { 'The Lesson 11 group is gone and the Foundry resource is purged.' } else { 'The group still exists; check the portal.' })
    [void](Write-L11Evidence 'remove' ([ordered]@{ removedUtc = [DateTime]::UtcNow.ToString('o'); group = $cfg.resourceGroup; foundry = $lab.foundry; groupGone = ($still.ExitCode -ne 0) }))
}
