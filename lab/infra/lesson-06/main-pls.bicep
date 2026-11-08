// Bounded Private Link service lab (demo 6.2). Subscription scope: creates the parts API group (config.json plsResourceGroup).
targetScope = 'subscription'

param location string
param resourceGroupName string
param sshPublicKey string
param imageVersion string
param vmSize string
param addressPlan object
param ports object
param managedBy string
@description('Resource names from config.json names, per Cloud Adoption Framework naming guidance, https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming (CAF, applied to Contoso).')
param names object
@description('CAF naming components from config.json naming: env, region, instance.')
param naming object

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

module pls 'pls.bicep' = {
  scope: rg
  name: 'l06-pls'
  params: {
    location: location
    tags: tags
    sshPublicKey: sshPublicKey
    imageVersion: imageVersion
    vmSize: vmSize
    addressPlan: addressPlan
    ports: ports
    names: names
    naming: naming
  }
}

output lab object = pls.outputs.lab
