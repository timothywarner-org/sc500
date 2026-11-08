// Bounded Private Access connector host (demo 6.3). Subscription scope: creates
// the connector group (config.json connectorResourceGroup). The NIC joins the retained hub's snet-connectors.
targetScope = 'subscription'

param location string
param resourceGroupName string
param subnetId string
param privateIp string
param vmSize string
param operatorPublicIp string
param managedBy string
@description('Resource names from config.json names, per Cloud Adoption Framework naming guidance, https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming (CAF, applied to Contoso).')
param names object
@secure()
param adminPassword string

var tags = {
  managedBy: managedBy
  lesson: '6'
  scenario: 'Contoso ServiceHub'
  lifecycle: 'bounded: remove after the rehearsal or take'
}

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module connector 'connector.bicep' = {
  scope: rg
  name: 'l06-connector'
  params: {
    location: location
    tags: tags
    subnetId: subnetId
    privateIp: privateIp
    vmSize: vmSize
    operatorPublicIp: operatorPublicIp
    adminPassword: adminPassword
    names: names
  }
}

output lab object = connector.outputs.lab
