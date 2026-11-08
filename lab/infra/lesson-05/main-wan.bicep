// Bounded demo 5.3 lab: creates rg-sc500-l05-wan and the secured Virtual WAN hub in it.
// Remove-L05Bounded.ps1 deletes the whole group afterward.
targetScope = 'subscription'

param location string
param resourceGroupName string
param addressPlan object
param ports object
param sshPublicKey string
param imageVersion string
param vmSize string
param workspaceId string
param managedBy string

var tags = {
  managedBy: managedBy
  lesson: '5'
  scenario: 'Contoso ServiceHub'
  lifecycle: 'bounded: remove after the rehearsal or take'
}

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module wan 'wan.bicep' = {
  scope: rg
  name: 'l05-wan'
  params: {
    location: location
    tags: tags
    addressPlan: addressPlan
    ports: ports
    sshPublicKey: sshPublicKey
    imageVersion: imageVersion
    vmSize: vmSize
    workspaceId: workspaceId
  }
}

output lab object = wan.outputs.lab
