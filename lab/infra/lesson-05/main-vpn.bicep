// Bounded demo 5.4 lab. Creates rg-sc500-l05-vpn with the simulated field service branch
// (VNet, VPN gateway, client VM) and the two site-to-site connections, and adds the hub-side
// VPN gateway, with point-to-site settings, to the retained hub VNet's GatewaySubnet.
// Remove-L05Bounded.ps1 deletes the VPN group and the hub gateway afterward.
targetScope = 'subscription'

param location string
param networkResourceGroup string
param vpnResourceGroup string
param addressPlan object
@secure()
param sharedKey string
param sshPublicKey string
param imageVersion string
param vmSize string
param workspaceId string
param tenantId string
param p2sAudience string
param managedBy string
@allowed(['legacy', 'baseline'])
param branchPolicy string = 'legacy'

var tags = {
  managedBy: managedBy
  lesson: '5'
  scenario: 'Contoso ServiceHub'
  lifecycle: 'bounded: remove after the rehearsal or take'
}

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: vpnResourceGroup
  location: location
  tags: tags
}

// Hub side: in the retained network group, attached to the existing GatewaySubnet.
module hubGateway 'vpn-gateway.bicep' = {
  scope: resourceGroup(networkResourceGroup)
  name: 'l05-vpn-hub-gateway'
  params: {
    name: 'vgw-contoso-platform-hub'
    location: location
    tags: tags
    gatewaySubnetId: resourceId(subscription().subscriptionId, networkResourceGroup, 'Microsoft.Network/virtualNetworks/subnets', 'vnet-sc500-l05-hub', 'GatewaySubnet')
    p2sAddressPool: addressPlan.p2sPool
    tenantId: tenantId
    p2sAudience: p2sAudience
    workspaceId: workspaceId
  }
}

module branch 'vpn-branch.bicep' = {
  scope: rg
  name: 'l05-vpn-branch'
  params: {
    location: location
    tags: tags
    addressPlan: addressPlan
    sshPublicKey: sshPublicKey
    imageVersion: imageVersion
    vmSize: vmSize
    workspaceId: workspaceId
  }
}

module links 'vpn-links.bicep' = {
  scope: rg
  name: 'l05-vpn-links'
  params: {
    location: location
    tags: tags
    hubGatewayId: hubGateway.outputs.gatewayId
    hubPublicIp: hubGateway.outputs.publicIp
    hubPrefixes: [addressPlan.hub, addressPlan.servicehub]
    branchGatewayId: branch.outputs.gatewayId
    branchPublicIp: branch.outputs.publicIp
    branchPrefixes: [addressPlan.branch]
    sharedKey: sharedKey
    branchPolicy: branchPolicy
  }
}

output lab object = {
  resourceGroup: vpnResourceGroup
  hubGatewayId: hubGateway.outputs.gatewayId
  branchGatewayId: branch.outputs.gatewayId
  hubConnectionId: links.outputs.hubConnectionId
  branchConnectionId: links.outputs.branchConnectionId
  branchVmId: branch.outputs.vmId
}
