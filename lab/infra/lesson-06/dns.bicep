// SC-500 Lesson 6 bounded lab: hybrid name resolution for the records private endpoint.
//
// names.dnsResolver is an Azure DNS Private Resolver in the retained hub VNet, with an inbound
// endpoint at 10.60.0.4. The hub is linked to privatelink.blob.core.windows.net, so a query that
// arrives at the inbound endpoint resolves the records account to its private endpoint.
//
// names.fieldOfficeVnet stands in for an on-premises network. It's peered to the hub in
// place of a site-to-site VPN (Lesson 5 covers the tunnel; here we only need a routed path), and
// it is NOT linked to the private DNS zone, because on-premises networks can't be. Its VM runs
// the field-office DNS stand-in from onprem-dns-cloud-init.yaml, with no conditional forwarders
// at baseline. Demo 6.4 adds one line: blob.core.windows.net -> 10.60.0.4.
// Cost while deployed: about 0.26 USD an hour, nearly all of it the inbound endpoint.

param location string
param tags object
param sshPublicKey string
param imageVersion string
param vmSize string
param addressPlan object
param hubVnetId string
param dnsInboundSubnetId string
param clientIdentityId string
@description('Resource names from config.json names, per Cloud Adoption Framework naming guidance, https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming (CAF, applied to Contoso).')
param names object
@description('CAF naming components from config.json naming: env, region, instance.')
param naming object

var hosts = addressPlan.hosts

module maintenance 'maintenance-egress.bicep' = {
  name: 'l06-maintenance-field-office'
  params: { location: location, tags: tags, workload: 'fieldoffice', naming: naming }
}

resource resolver 'Microsoft.Network/dnsResolvers@2022-07-01' = {
  name: names.dnsResolver
  location: location
  tags: tags
  properties: {
    virtualNetwork: { id: hubVnetId }
  }
}

resource inbound 'Microsoft.Network/dnsResolvers/inboundEndpoints@2022-07-01' = {
  parent: resolver
  name: names.dnsInbound
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        privateIpAllocationMethod: 'Static'
        privateIpAddress: hosts.resolverInbound
        subnet: { id: dnsInboundSubnetId }
      }
    ]
  }
}

resource fieldOffice 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: names.fieldOfficeVnet
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [addressPlan.onprem] }
    subnets: [
      {
        name: 'snet-field-office'
        properties: {
          addressPrefix: addressPlan.onpremSubnet
          defaultOutboundAccess: false
          natGateway: { id: maintenance.outputs.id }
        }
      }
    ]
  }
}

resource fieldToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: fieldOffice
  name: names.fieldOfficeToHub
  properties: {
    remoteVirtualNetwork: { id: hubVnetId }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
  }
}

module dnsVm 'vm.bicep' = {
  name: 'l06-vm-field-office-dns'
  params: {
    name: names.fieldOfficeDnsVm
    location: location
    tags: tags
    subnetId: fieldOffice.properties.subnets[0].id
    privateIp: hosts.onpremDns
    customData: base64(loadTextContent('onprem-dns-cloud-init.yaml'))
    vmSize: vmSize
    sshPublicKey: sshPublicKey
    imageVersion: imageVersion
    identityType: 'UserAssigned'
    userAssignedIdentityIds: [clientIdentityId]
  }
}

output lab object = {
  resourceGroup: resourceGroup().name
  resolverName: resolver.name
  inboundIp: hosts.resolverInbound
  inboundProvisioning: inbound.properties.provisioningState
  fieldOfficeVnetId: fieldOffice.id
  fieldOfficeVm: names.fieldOfficeDnsVm
}
