// The simulated Contoso field service branch for demo 5.4: a small VNet, a VPN gateway that
// plays the branch's on-premises VPN device, and one client VM that tests the tunnel.

param location string
param tags object
param addressPlan object
param sshPublicKey string
param imageVersion string
param vmSize string
param workspaceId string

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-sc500-l05-field-branch'
  location: location
  tags: union(tags, { role: 'Simulated field service branch (stands in for on-premises)' })
  properties: {
    addressSpace: { addressPrefixes: [addressPlan.branch] }
    subnets: [
      {
        name: 'snet-branch'
        properties: {
          addressPrefix: addressPlan.branchSubnet
          defaultOutboundAccess: false
        }
      }
      {
        name: 'GatewaySubnet'
        properties: { addressPrefix: addressPlan.branchGateway }
      }
    ]
  }
}

module gateway 'vpn-gateway.bicep' = {
  name: 'l05-vpn-branch-gateway'
  params: {
    name: 'vgw-contoso-field-branch'
    location: location
    tags: tags
    gatewaySubnetId: vnet.properties.subnets[1].id
    workspaceId: workspaceId
  }
}

module client 'vm.bicep' = {
  name: 'vm-branch-client'
  params: {
    name: 'vm-branch-client'
    location: location
    tags: tags
    subnetId: vnet.properties.subnets[0].id
    privateIp: addressPlan.branchHost
    vmSize: vmSize
    sshPublicKey: sshPublicKey
    imageVersion: imageVersion
  }
}

output gatewayId string = gateway.outputs.gatewayId
output publicIp string = gateway.outputs.publicIp
output vmId string = client.outputs.vmId
