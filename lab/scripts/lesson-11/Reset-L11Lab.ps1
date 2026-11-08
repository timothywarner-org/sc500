<#
.SYNOPSIS
    Returns the SC-500 Lesson 11 lab to CTSO-L11-BASELINE after you finish: removes
    the bounded AI gateway (API Management Basic v2) and purges its soft-deleted copy.
.DESCRIPTION
    API Management bills 0.21 USD an hour for Basic v2 whether or not traffic flows, so the
    gateway is removed after each session. Deleting an instance soft-deletes it for 48 hours; the
    purge frees the name so the next Deploy-L11Lab.ps1 -Gateway recreates it with the same URL,
    which the agent's OpenAPI tool depends on.
    Retained and untouched: the Foundry resource, project, guardrail, blocklist, model deployment,
    the servicehub-assistant agent, the workspace, and your role. Model, scan and log meters
    remain separate from the removed gateway's hourly charge.
    The script reads back that the instance and its soft-deleted copy are gone.
.PARAMETER WhatIf Show what would be removed and change nothing.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-11\Reset-L11Lab.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param()
. (Join-Path $PSScriptRoot 'L11.Common.ps1')
$cfg = $script:L11Config
[void](Assert-L11Context)
$lab = Get-L11Outputs
$removedRoles = [Collections.Generic.List[string]]::new()
$list = @(Invoke-L11Az @('apim', 'list', '--resource-group', $cfg.resourceGroup, '--query', "[?starts_with(name, '$($cfg.names.apimPrefix)')].name"))
if (-not $list) { Write-Host 'No Lesson 11 gateway instance exists.' }
foreach ($name in $list) {
    if ($PSCmdlet.ShouldProcess($name, 'Delete API Management instance and purge it')) {
        # Read the exact lesson identity before deletion, then remove only its backend grant.
        $gateway = Invoke-L11Az @('apim','show','--resource-group',$cfg.resourceGroup,'--name',$name)
        $principal = $gateway.identity.principalId
        $grants = @(Invoke-L11Az @('role','assignment','list','--scope',$lab.foundryId) |
            Where-Object { $_.principalId -eq $principal -and $_.scope -eq $lab.foundryId -and
                $_.roleDefinitionId -like "*/$($cfg.roles.openAiUser)" })
        Write-Host "Deleting $name (a few minutes)."
        [void](Invoke-L11Az -Raw @('apim', 'delete', '--resource-group', $cfg.resourceGroup, '--name', $name, '--yes'))
        foreach ($grant in $grants) {
            [void](Invoke-L11Az -Raw @('role','assignment','delete','--ids',$grant.id))
            $removedRoles.Add($grant.id)
        }
        foreach ($try in 1..20) {
            $del = Invoke-L11Az -AllowFailure @('apim', 'deletedservice', 'show', '--service-name', $name, '--location', $cfg.location)
            if ($del.ExitCode -eq 0) { break }
            Start-Sleep -Seconds 15
        }
        [void](Invoke-L11Az -Raw -AllowFailure @('apim', 'deletedservice', 'purge', '--service-name', $name, '--location', $cfg.location))
    }
}
$left = @(Invoke-L11Az @('apim', 'list', '--resource-group', $cfg.resourceGroup, '--query', '[].name'))
$soft = @(Invoke-L11Az @('apim', 'deletedservice', 'list', '--query', "[?starts_with(name, '$($cfg.names.apimPrefix)')].name"))
Write-Host ("Instances left: {0}. Soft-deleted copies left: {1}." -f $(if ($left) { $left -join ', ' } else { 'none' }), $(if ($soft) { $soft -join ', ' } else { 'none' }))
if (-not $WhatIfPreference) {
    [void](Write-L11Evidence 'reset' ([ordered]@{ resetUtc = [DateTime]::UtcNow.ToString('o'); removed = $list; removedBackendRoles = @($removedRoles); instancesLeft = $left; softDeletedLeft = $soft }))
    if ($left -or $soft) { Write-Warning 'The gateway is not fully gone. Check the portal before you assume billing stopped.'; exit 1 }
}
