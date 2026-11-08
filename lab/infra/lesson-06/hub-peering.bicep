// The hub side of the field-office peering. It's a child of the retained hub VNet, so it deploys
// into the retained resource group, and Remove-L06Bounded.ps1 -Lab Dns deletes it explicitly
// (deleting the bounded group alone would leave it behind, Disconnected).

param hubVnetName string
param remoteVnetId string
@description('config.json names.hubToFieldOffice')
param peeringName string

resource hub 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: hubVnetName
}

resource hubToField 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: hub
  name: peeringName
  properties: {
    remoteVirtualNetwork: { id: remoteVnetId }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
  }
}
