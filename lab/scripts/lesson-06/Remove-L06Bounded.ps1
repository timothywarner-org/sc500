<#
.SYNOPSIS
    Removes one bounded Lesson 6 lab after you finish, and proves it's gone.

.DESCRIPTION
      Pls        Deletes rg-partsapi-prod-eastus2 (load balancer, Private Link service, both VMs, the
                 partner VNet and its private endpoint).
      Dns        Deletes rg-fieldoffice-prod-eastus2 (resolver, inbound endpoint, field-office VNet and VM),
                 then the hub side of the field-office peering, which lives in the retained hub.
      Connector  Deletes the connector group (Windows host, NIC, NSG, public IP). The saved
                 DPAPI credential is deleted too, so the next deployment generates a new one. A
                 connector you registered stays listed in Entra as inactive until you remove it.
    Refuses to touch a resource group that isn't tagged managedBy=sc500-l06-iac. The retained
    lab's VNets, zone, storage account, and VM stay.

.PARAMETER Lab
    Pls, Dns, or Connector.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Remove-L06Bounded.ps1 -Lab Pls
#>
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Pls', 'Dns', 'Connector')][string]$Lab)
. (Join-Path $PSScriptRoot 'L06.Common.ps1')
[void](Assert-L06Context)
$cfg = $script:L06Config
$rgName = switch ($Lab) { 'Pls' { $cfg.plsResourceGroup } 'Dns' { $cfg.dnsResourceGroup } 'Connector' { $cfg.connectorResourceGroup } }
$removed = [ordered]@{ lab = $Lab; resourceGroup = $rgName }

if (Invoke-L06Az @('group', 'exists', '--name', $rgName)) {
    $rg = Invoke-L06Az @('group', 'show', '--name', $rgName)
    if ($rg.tags.managedBy -ne $cfg.managedBy) { throw "$rgName isn't tagged managedBy=$($cfg.managedBy). Nothing was deleted." }
    Write-Host "Deleting $rgName. This usually takes 5 to 10 minutes."
    [void](Invoke-L06Az -Raw @('group', 'delete', '--name', $rgName, '--yes'))
}
$removed.resourceGroupExists = [bool](Invoke-L06Az @('group', 'exists', '--name', $rgName))

if ($Lab -eq 'Dns') {
    $peerings = @(Invoke-L06Az @('network', 'vnet', 'peering', 'list', '--resource-group', $cfg.resourceGroup, '--vnet-name', $script:L06Names.hubVnet, '--query', '[].name'))
    if ($peerings -contains $script:L06Names.hubToFieldOffice) {
        Write-Host 'Deleting the hub side of the field-office peering.'
        [void](Invoke-L06Az -Raw @('network', 'vnet', 'peering', 'delete', '--resource-group', $cfg.resourceGroup, '--vnet-name', $script:L06Names.hubVnet, '--name', $script:L06Names.hubToFieldOffice))
    }
    $after = @(Invoke-L06Az @('network', 'vnet', 'peering', 'list', '--resource-group', $cfg.resourceGroup, '--vnet-name', $script:L06Names.hubVnet, '--query', '[].name'))
    $removed[$script:L06Names.hubToFieldOffice] = if ($after -contains $script:L06Names.hubToFieldOffice) { 'still present' } else { 'absent' }
}
if ($Lab -eq 'Connector') {
    $credPath = Join-Path $env:LOCALAPPDATA 'SC500/Lesson06/connector-admin.credential.xml'
    if (Test-Path -LiteralPath $credPath) { Remove-Item -LiteralPath $credPath -Force }
    $removed.savedCredential = if (Test-Path -LiteralPath $credPath) { 'still present' } else { 'absent' }
}
[void](Write-L06Evidence "remove-$($Lab.ToLowerInvariant())" $removed)
$removed.GetEnumerator() | ForEach-Object { '{0,-26} {1}' -f $_.Key, $_.Value }
if ($removed.resourceGroupExists -or @($removed.Values) -contains 'still present') { throw 'Something is still present. Check the portal before assuming billing stopped.' }
