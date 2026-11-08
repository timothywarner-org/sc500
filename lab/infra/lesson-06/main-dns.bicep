// Bounded hybrid DNS lab (demo 6.4). Subscription scope: creates the field office group (config.json dnsResourceGroup) and the hub
// side of the field-office peering in the retained group.
targetScope = 'subscription'

param location string
param resourceGroupName string
param retainedResourceGroup string
param sshPublicKey string
param imageVersion string
param vmSize string
param addressPlan object
param hubVnetId string
param hubVnetName string
param dnsInboundSubnetId string
param clientIdentityId string
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

module dns 'dns.bicep' = {
  scope: rg
  name: 'l06-dns'
  params: {
    location: location
    tags: tags
    sshPublicKey: sshPublicKey
    imageVersion: imageVersion
    vmSize: vmSize
    addressPlan: addressPlan
    hubVnetId: hubVnetId
    dnsInboundSubnetId: dnsInboundSubnetId
    clientIdentityId: clientIdentityId
    names: names
    naming: naming
  }
}

module hubSide 'hub-peering.bicep' = {
  scope: resourceGroup(retainedResourceGroup)
  name: 'l06-dns-hub-peering'
  params: {
    hubVnetName: hubVnetName
    remoteVnetId: dns.outputs.lab.fieldOfficeVnetId
    peeringName: names.hubToFieldOffice
  }
}

output lab object = dns.outputs.lab
