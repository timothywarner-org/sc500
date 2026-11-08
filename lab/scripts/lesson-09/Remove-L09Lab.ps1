<#
.SYNOPSIS
    Deletes the whole Lesson 9 lab: the resource group and the lab API app registration.
    your call, not a routine step.

.DESCRIPTION
    Asks you to type the resource group name (rg-appplatform-prod-eastus2) unless -Force is given.
    Checks the group's managedby tag and the app registration's display name and tag before
    deleting either. The AKS cluster's node resource group (rg-servicehubnodes-prod-eastus2) and
    its budget go with the cluster. Afterward, the Lesson 9 demos can't run until
    Deploy-L09Lab.ps1 -Deploy rebuilds everything, with a new app registration ID. The Defender
    plans stay as they are; Set-L09DefenderWindow.ps1 -State Close turns them off.

.PARAMETER Force
    Skip the typed confirmation.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Remove-L09Lab.ps1
#>
[CmdletBinding()]
param([switch]$Force)
. (Join-Path $PSScriptRoot 'L09.Common.ps1')
[void](Assert-L09Context)
$cfg = $script:L09Config
$rg = $cfg.resourceGroup

if (-not $Force) {
    $typed = Read-Host "This deletes $rg and the app registration $($cfg.apiAppDisplayName). Type the resource group name to continue"
    if ($typed -ne $rg) { Write-Host 'Nothing deleted.'; return }
}
if (Invoke-L09Az @('group', 'exists', '--name', $rg)) {
    $group = Invoke-L09Az @('group', 'show', '--name', $rg)
    if ((Get-L09Value $group 'tags.managedby') -ne $cfg.managedBy) { throw "$rg isn't tagged managedby=$($cfg.managedBy). Stopping." }
    Write-Host "Deleting $rg (AKS and API Management make this take a while)."
    Invoke-L09Az -Raw @('group', 'delete', '--name', $rg, '--yes') | Out-Null
}
$app = Get-L09ApiApp
if ($app) {
    $full = Invoke-L09Rest -Path "https://graph.microsoft.com/v1.0/applications/$($app.id)?`$select=id,tags"
    if (@($full.tags) -notcontains $cfg.managedBy) { throw "$($cfg.apiAppDisplayName) isn't tagged $($cfg.managedBy). Stopping." }
    Invoke-L09Rest -Method delete -Path "https://graph.microsoft.com/v1.0/applications/$($app.id)" | Out-Null
    Write-Host "Deleted app registration $($cfg.apiAppDisplayName) (it stays in deleted items for 30 days)."
}
[void](Write-L09Evidence 'lab-removed' ([pscustomobject]@{ removedUtc = [DateTime]::UtcNow.ToString('o') }))
