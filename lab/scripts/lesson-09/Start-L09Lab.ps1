<#
.SYNOPSIS
    Starts, or stops, the Lesson 9 AKS cluster. Everything else in the retained lab is
    consumption-billed and needs no start.

.DESCRIPTION
    Starts or stops aks-servicehub-prod-eastus2-001 (one D4s_v3 node, eastus2). A stopped AKS
    cluster keeps its configuration (Entra and Azure RBAC, the Defender sensor profile, the Azure
    Policy add-on, workloads) and accrues no node or Defender for Containers charges; the node
    resource group's load balancer and public IP still bill. Starting it takes about five minutes.
    Start it about 20 minutes before a take so the Defender sensor and Gatekeeper are running.

    This is the lab's idle-compute guardrail. CAF's auto-shutdown schedules (DevTest Labs
    shutdown-computevm-*) target virtual machines, and AKS nodes are a scale set AKS manages, so
    the cluster is stopped between takes with -Stop instead.

.PARAMETER Stop
    Stop the cluster instead of starting it.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Start-L09Lab.ps1

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Start-L09Lab.ps1 -Stop
#>
[CmdletBinding()]
param([switch]$Stop)
. (Join-Path $PSScriptRoot 'L09.Common.ps1')
[void](Assert-L09Context)
$cfg = $script:L09Config

$aks = Invoke-L09Az @('aks', 'show', '--resource-group', $cfg.resourceGroup, '--name', $cfg.names.aks)
$state = $aks.powerState.code
$want = if ($Stop) { 'Stopped' } else { 'Running' }
if ($state -eq $want) { Write-Host "$($cfg.names.aks) is already $want." }
else {
    $started = Get-Date
    Write-Host "$(if ($Stop) { 'Stopping' } else { 'Starting' }) $($cfg.names.aks) (a few minutes)."
    Invoke-L09Az -Raw @('aks', $(if ($Stop) { 'stop' } else { 'start' }), '--resource-group', $cfg.resourceGroup, '--name', $cfg.names.aks) | Out-Null
    Write-Host ("Done in {0:N0} minutes." -f ((Get-Date) - $started).TotalMinutes)
}
$aks = Invoke-L09Az @('aks', 'show', '--resource-group', $cfg.resourceGroup, '--name', $cfg.names.aks)
$row = [pscustomobject]@{ Cluster = $aks.name; Power = $aks.powerState.code; Provisioning = $aks.provisioningState; AtUtc = [DateTime]::UtcNow.ToString('HH:mm:ss') }
[void](Write-L09Evidence "aks-$($want.ToLower())" $row)
$row | Format-Table -AutoSize | Out-String -Width 120 | Out-Host
