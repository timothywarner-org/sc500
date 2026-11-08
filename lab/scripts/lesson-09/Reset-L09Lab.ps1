<#
.SYNOPSIS
    Resets the Lesson 9 demos between takes, or returns the lab to CTSO-L09-BASELINE after the
    recording session.

.DESCRIPTION
    Puts ca-status-prod-001's allow list back to the operator's address (demo 9.1's Block mode
    swaps it), deletes the servicehub namespace from aks-servicehub-prod-eastus2-001 if it's
    running (so the next take shows the workloads arriving and the privileged pod being refused),
    and, unless -KeepEdge is given, removes the bounded edge with Remove-L09Edge.ps1. With -Stop it
    then stops the AKS cluster.

      Between takes:            Reset-L09Lab.ps1 -KeepEdge   (edge and cluster stay up)
      After the session ships:  Reset-L09Lab.ps1 -Stop       (edge removed, cluster stopped)

.PARAMETER KeepEdge
    Leave the bounded edge in place (the next take needs it, and Front Door takes about 17 minutes
    to answer after a fresh deployment).

.PARAMETER Stop
    Stop the AKS cluster afterward (recommended between sessions).

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Reset-L09Lab.ps1 -KeepEdge

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Reset-L09Lab.ps1 -Stop
#>
[CmdletBinding()]
param([switch]$KeepEdge, [switch]$Stop)
. (Join-Path $PSScriptRoot 'L09.Common.ps1')
[void](Assert-L09Context)
$cfg = $script:L09Config
$n = $cfg.names

if ($KeepEdge) { Write-Host 'Keeping the bounded edge (about 0.65 USD an hour while it exists).' }
else { & (Join-Path $PSScriptRoot 'Remove-L09Edge.ps1') }

# The container app: exactly one Allow rule, for the operator's current address.
$id = Get-L09ResourceId 'Microsoft.App/containerApps' $n.containerApp
$app = Invoke-L09Rest -Path "$id`?api-version=2024-03-01"
$ing = $app.properties.configuration.ingress
$ing.ipSecurityRestrictions = @(@{ name = 'allow-operator'; description = 'Operator workstation only'; ipAddressRange = "$(Get-L09OperatorIp)/32"; action = 'Allow' })
Invoke-L09Rest -Method patch -Path "$id`?api-version=2024-03-01" -Body @{ properties = @{ configuration = @{ ingress = $ing } } } | Out-Null
Write-Host "Reset $($n.containerApp)'s allow list to your IP."

$state = Invoke-L09Az @('aks', 'show', '--resource-group', $cfg.resourceGroup, '--name', $n.aks, '--query', 'powerState.code')
if ($state -eq 'Running') {
    $r = Invoke-L09Kubectl -Command 'kubectl delete namespace servicehub --ignore-not-found --wait=false'
    Write-Host "servicehub namespace: $($r.Logs)"
}
if ($Stop) { & (Join-Path $PSScriptRoot 'Start-L09Lab.ps1') -Stop }
if ($KeepEdge) { Write-Host 'Reset complete. Run Test-L09Lab.ps1 -TakeReady to confirm the next take can start.' }
else { Write-Host 'Reset complete. Run Test-L09Lab.ps1 to confirm the baseline.' }
