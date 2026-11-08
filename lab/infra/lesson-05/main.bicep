// SC-500 Lesson 5 retained baseline (CTSO-L05-BASELINE). Subscription scope so one
// deployment creates the lesson resource group and the flow logs in NetworkWatcherRG.
// The bounded Virtual WAN (wan.bicep) and VPN (vpn.bicep) labs deploy separately.
targetScope = 'subscription'

param location string
param resourceGroupName string
param networkWatcherResourceGroup string
param networkWatcherName string
param operatorObjectId string
param sshPublicKey string
param imageVersion string
param vmSize string
param addressPlan object
param ports object
param blobDataReaderRoleId string
param managedBy string
param baseline string

var tags = {
  managedBy: managedBy
  lesson: '5'
  scenario: 'Contoso ServiceHub'
  baseline: baseline
}

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module network 'network.bicep' = {
  scope: rg
  name: 'l05-network'
  params: {
    location: location
    tags: tags
    operatorObjectId: operatorObjectId
    sshPublicKey: sshPublicKey
    imageVersion: imageVersion
    vmSize: vmSize
    addressPlan: addressPlan
    ports: ports
    blobDataReaderRoleId: blobDataReaderRoleId
  }
}

module flowLogs 'flowlogs.bicep' = {
  scope: resourceGroup(networkWatcherResourceGroup)
  name: 'l05-flowlogs'
  params: {
    location: location
    tags: tags
    networkWatcherName: networkWatcherName
    vnets: [
      { name: 'vnet-sc500-l05-hub', id: network.outputs.lab.hubVnetId }
      { name: 'vnet-sc500-l05-servicehub', id: network.outputs.lab.spokeVnetId }
    ]
    storageId: network.outputs.lab.flowStoreId
    workspaceId: network.outputs.lab.workspaceId
    workspaceCustomerId: network.outputs.lab.workspaceCustomerId
  }
}

output lab object = network.outputs.lab
