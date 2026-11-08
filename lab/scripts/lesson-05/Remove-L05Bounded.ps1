<#
.SYNOPSIS
    Removes one bounded Lesson 5 lab after you finish, and proves it's gone.

.DESCRIPTION
      Wan  Deletes rg-sc500-l05-wan (Virtual WAN, hub, firewall, policy, spokes, VMs).
      Vpn  Deletes rg-sc500-l05-vpn (branch, local network gateways, connections), then the
           hub-side gateway vgw-contoso-platform-hub and its public IP from the retained
           network group. The hub VNet and its empty GatewaySubnet stay; they cost nothing.
    Refuses to touch a resource group that isn't tagged managedBy=sc500-l05-iac. It
    deletes only those bounded VPN resources from the retained group. Its VNets, VMs,
    flow logs, and subscription-wide settings remain unchanged.

.PARAMETER Lab
    Wan or Vpn.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-05\Remove-L05Bounded.ps1 -Lab Wan
#>
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Wan', 'Vpn')][string]$Lab)
. (Join-Path $PSScriptRoot 'L05.Common.ps1')
[void](Assert-L05Context)
$cfg = $script:L05Config
$rgName = if ($Lab -eq 'Wan') { $cfg.wanResourceGroup } else { $cfg.vpnResourceGroup }
$removed = [ordered]@{ lab = $Lab; resourceGroup = $rgName }

if (Invoke-L05Az @('group', 'exists', '--name', $rgName)) {
    $rg = Invoke-L05Az @('group', 'show', '--name', $rgName)
    if ($rg.tags.managedBy -ne $cfg.managedBy) { throw "$rgName isn't tagged managedBy=$($cfg.managedBy). Nothing was deleted." }
    Write-Host "Deleting $rgName. Virtual WAN hubs and VPN gateways can take 10 to 20 minutes to remove."
    [void](Invoke-L05Az -Raw @('group', 'delete', '--name', $rgName, '--yes'))
}
$removed.resourceGroupExists = [bool](Invoke-L05Az @('group', 'exists', '--name', $rgName))

if ($Lab -eq 'Vpn') {
    foreach ($target in @(
        [pscustomobject]@{ Command = 'vnet-gateway'; Name = 'vgw-contoso-platform-hub' }
        [pscustomobject]@{ Command = 'public-ip'; Name = 'pip-vgw-contoso-platform-hub' }
    )) {
        # Only a successful ARM inventory can establish absence. A failed GET cannot.
        $item = @(Get-L05HubVpnResources | Where-Object name -eq $target.Name)
        if ($item.Count) {
            if ((Get-L05Value $item[0] 'tags.managedBy') -ne $cfg.managedBy) { throw "$($target.Name) isn't tagged managedBy=$($cfg.managedBy). Stopping." }
            Write-Host "Deleting $($target.Name)."
            [void](Invoke-L05Az -Raw @('network', $target.Command, 'delete', '--resource-group', $cfg.resourceGroup, '--name', $target.Name))
        }
        $stillThere = @(Get-L05HubVpnResources | Where-Object name -eq $target.Name)
        $removed[$target.Name] = if ($stillThere.Count) { 'still present' } else { 'absent' }
    }
}
[void](Write-L05Evidence "remove-$($Lab.ToLowerInvariant())" $removed)
$removed.GetEnumerator() | ForEach-Object { '{0,-30} {1}' -f $_.Key, $_.Value }
if ($removed.resourceGroupExists -or @($removed.Values) -contains 'still present') { throw 'Something is still present. Check the portal before assuming billing stopped.' }
