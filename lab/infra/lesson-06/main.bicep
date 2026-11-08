// SC-500 Lesson 6 retained baseline (CTSO-L06-BASELINE). Subscription scope so one deployment
// creates the lesson resource group. The bounded labs (Private Link service, hybrid DNS, and
// the Private Access connector host) deploy separately with Deploy-L06Bounded.ps1.
targetScope = 'subscription'

param location string
param resourceGroupName string
param operatorObjectId string
param sshPublicKey string
param imageVersion string
param vmSize string
param addressPlan object
param ports object
param recordsContainer string
param privateDnsZoneName string
param blobDataReaderRoleId string
param blobDataContributorRoleId string
param managedBy string
param baseline string
@description('Resource names from config.json names, per Cloud Adoption Framework naming guidance, https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming (CAF, applied to Contoso).')
param names object
@description('CAF naming components from config.json naming: env, region, instance.')
param naming object

var tags = {
  managedBy: managedBy
  lesson: '6'
  scenario: 'Contoso ServiceHub'
  baseline: baseline
}

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module private 'private.bicep' = {
  scope: rg
  name: 'l06-private'
  params: {
    location: location
    tags: tags
    operatorObjectId: operatorObjectId
    sshPublicKey: sshPublicKey
    imageVersion: imageVersion
    vmSize: vmSize
    addressPlan: addressPlan
    ports: ports
    recordsContainer: recordsContainer
    privateDnsZoneName: privateDnsZoneName
    blobDataReaderRoleId: blobDataReaderRoleId
    blobDataContributorRoleId: blobDataContributorRoleId
    names: names
    naming: naming
  }
}

output lab object = private.outputs.lab
