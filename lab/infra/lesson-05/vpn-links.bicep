// Demo 5.4 site-to-site links between the Contoso platform hub and the simulated field
// service branch. The branch is a second Azure VPN gateway standing in for an on-premises
// device, so each side gets a local network gateway describing the other side and an IPsec
// connection of its own. This is a genuine site-to-site IPsec connection, not the VNet-to-VNet
// connection type.
//
// The introduced fault: the branch still offers legacy crypto (AES128, SHA1, DH group 2). The
// hub insists on the Contoso baseline with a custom IPsec/IKE policy, so the tunnel can't form
// until demo 5.4 updates the branch side. A custom policy is a single proposal, which is why a
// mismatch fails instead of quietly negotiating down.

param location string
param tags object
param hubGatewayId string
param hubPublicIp string
param hubPrefixes array
param branchGatewayId string
param branchPublicIp string
param branchPrefixes array
@secure()
param sharedKey string
@description('Branch-side policy at deploy time: legacy (the fault) or baseline.')
@allowed(['legacy', 'baseline'])
param branchPolicy string = 'legacy'

var policies = {
  baseline: {
    ikeEncryption: 'AES256'
    ikeIntegrity: 'SHA256'
    dhGroup: 'DHGroup14'
    ipsecEncryption: 'GCMAES256'
    ipsecIntegrity: 'GCMAES256'
    pfsGroup: 'PFS14'
    saLifeTimeSeconds: 27000
    saDataSizeKilobytes: 102400000
  }
  legacy: {
    ikeEncryption: 'AES128'
    ikeIntegrity: 'SHA1'
    dhGroup: 'DHGroup2'
    ipsecEncryption: 'AES128'
    ipsecIntegrity: 'SHA1'
    pfsGroup: 'None'
    saLifeTimeSeconds: 27000
    saDataSizeKilobytes: 102400000
  }
}

// What the hub knows about the branch, and what the branch knows about the hub.
resource lngBranch 'Microsoft.Network/localNetworkGateways@2024-05-01' = {
  name: 'lng-contoso-field-branch'
  location: location
  tags: tags
  properties: {
    gatewayIpAddress: branchPublicIp
    localNetworkAddressSpace: { addressPrefixes: branchPrefixes }
  }
}
resource lngHub 'Microsoft.Network/localNetworkGateways@2024-05-01' = {
  name: 'lng-contoso-platform-hub'
  location: location
  tags: tags
  properties: {
    gatewayIpAddress: hubPublicIp
    localNetworkAddressSpace: { addressPrefixes: hubPrefixes }
  }
}

resource hubToBranch 'Microsoft.Network/connections@2024-05-01' = {
  name: 'conn-hub-to-field-branch'
  location: location
  tags: tags
  properties: {
    connectionType: 'IPsec'
    connectionProtocol: 'IKEv2'
    virtualNetworkGateway1: { id: hubGatewayId, properties: {} }
    localNetworkGateway2: { id: lngBranch.id, properties: {} }
    sharedKey: sharedKey
    usePolicyBasedTrafficSelectors: false
    ipsecPolicies: [policies.baseline]
  }
}

resource branchToHub 'Microsoft.Network/connections@2024-05-01' = {
  name: 'conn-field-branch-to-hub'
  location: location
  tags: tags
  properties: {
    connectionType: 'IPsec'
    connectionProtocol: 'IKEv2'
    virtualNetworkGateway1: { id: branchGatewayId, properties: {} }
    localNetworkGateway2: { id: lngHub.id, properties: {} }
    sharedKey: sharedKey
    usePolicyBasedTrafficSelectors: false
    ipsecPolicies: [policies[branchPolicy]]
  }
}

output hubConnectionId string = hubToBranch.id
output branchConnectionId string = branchToHub.id
