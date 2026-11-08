// SC-500 Lesson 6 retained lab: the ServiceHub records account and the networks that reach it.
//
// Baseline CTSO-L06-BASELINE (the demo 6.1 fault): the records account accepts traffic from
// every network, and there's no private endpoint yet. Demo 6.1 creates the endpoint in the hub
// and then disables public network access. The private DNS zone is already linked to both
// VNets, so the endpoint's A record resolves from either one the moment the demo creates it.
//
// Layout (see config.json):
//   names.hubVnet         snet-dns-inbound (delegated, for the bounded DNS resolver),
//                         snet-connectors (bounded Private Access connector host),
//                         snet-private-endpoints (the records endpoint, 10.60.0.68)
//   names.servicehubVnet  snet-workload (names.appVm, 10.60.16.4, listens on 8080)
// Names follow Cloud Adoption Framework naming guidance, https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming: CAF, applied to Contoso, with no course or lesson in them.
// Every subnet is private (no default outbound access). Tests run inside VMs through Run Command.

param location string
param tags object
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
@description('Resource names from config.json names, per Cloud Adoption Framework naming guidance, https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming (CAF, applied to Contoso).')
param names object
@description('CAF naming components from config.json naming: env, region, instance.')
param naming object
var hosts = addressPlan.hosts

module maintenance 'maintenance-egress.bicep' = {
  name: 'l06-maintenance-servicehub'
  params: { location: location, tags: tags, workload: 'servicehub', naming: naming }
}

// ---------------------------------------------------------------------------------------
// Networks
// ---------------------------------------------------------------------------------------
resource hub 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: names.hubVnet
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [addressPlan.hub] }
    subnets: [
      {
        name: 'snet-dns-inbound'
        properties: {
          addressPrefix: addressPlan.hubDnsInbound
          defaultOutboundAccess: false
          // An inbound endpoint needs a subnet delegated to the resolver and nothing else in it.
          delegations: [{ name: 'dns-resolver', properties: { serviceName: 'Microsoft.Network/dnsResolvers' } }]
        }
      }
      {
        name: 'snet-connectors'
        properties: {
          addressPrefix: addressPlan.hubConnectors
          defaultOutboundAccess: false
        }
      }
      {
        name: 'snet-private-endpoints'
        properties: {
          addressPrefix: addressPlan.hubPrivateEndpoints
          defaultOutboundAccess: false
          // The default. NSG and UDR rules don't apply to private endpoint traffic unless this
          // is set to Enabled (or NetworkSecurityGroupEnabled / RouteTableEnabled).
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource spoke 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: names.servicehubVnet
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [addressPlan.servicehub] }
    subnets: [
      {
        name: 'snet-workload'
        properties: {
          addressPrefix: addressPlan.servicehubWorkload
          defaultOutboundAccess: false
          natGateway: { id: maintenance.outputs.id }
        }
      }
    ]
  }
}

resource hubToSpoke 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: hub
  name: 'peer-hub-to-servicehub'
  properties: {
    remoteVirtualNetwork: { id: spoke.id }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
  }
}

resource spokeToHubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: spoke
  name: 'peer-servicehub-to-hub'
  properties: {
    remoteVirtualNetwork: { id: hub.id }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
  }
  dependsOn: [hubToSpoke]
}

// ---------------------------------------------------------------------------------------
// The records account. Entra ID only (no keys), no anonymous blobs, TLS 1.2. Public network
// access is Enabled at baseline: that's the exposure demo 6.1 closes.
// ---------------------------------------------------------------------------------------
resource records 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: names.recordsAccount
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    accessTier: 'Hot'
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
    networkAcls: { defaultAction: 'Allow', bypass: 'AzureServices' }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: records
  name: 'default'
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: recordsContainer
  properties: { publicAccess: 'None' }
}

// The operator seeds and reads the synthetic record with Entra ID.
resource operatorContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: container
  name: guid(container.id, operatorObjectId, blobDataContributorRoleId)
  properties: {
    principalId: operatorObjectId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobDataContributorRoleId)
  }
}

// ---------------------------------------------------------------------------------------
// Private DNS. The zone and both VNet links exist at baseline; the endpoint's DNS zone group
// adds the A record when demo 6.1 creates the endpoint. Fallback to internet stays off
// (resolutionPolicy Default): a missing record should fail loudly in this lab.
// ---------------------------------------------------------------------------------------
resource zone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: privateDnsZoneName
  location: 'global'
  tags: tags
}

resource hubLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: zone
  name: names.hubZoneLink
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: { id: hub.id }
    registrationEnabled: false
    resolutionPolicy: 'Default'
  }
}

resource spokeLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: zone
  name: names.servicehubZoneLink
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: { id: spoke.id }
    registrationEnabled: false
    resolutionPolicy: 'Default'
  }
}

// ---------------------------------------------------------------------------------------
// The ServiceHub app VM: reads the record with its own identity (demo 6.1) and serves the
// private API on 8080 that Private Access publishes (demo 6.3).
// ---------------------------------------------------------------------------------------
var listener = replace(replace(loadTextContent('listener-cloud-init.yaml'), '__ROLE__', 'ServiceHub app tier'), '__PORTS__', string(ports.app))

module app 'vm.bicep' = {
  name: 'l06-vm-servicehub-app'
  params: {
    name: names.appVm
    location: location
    tags: tags
    subnetId: spoke.properties.subnets[0].id
    privateIp: hosts.app
    customData: base64(listener)
    vmSize: vmSize
    sshPublicKey: sshPublicKey
    imageVersion: imageVersion
    identityType: 'SystemAssigned'
  }
}

resource appReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: container
  name: guid(container.id, names.appVm, blobDataReaderRoleId)
  properties: {
    principalId: app.outputs.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobDataReaderRoleId)
  }
}

// The bounded field-office VM (hybrid DNS lab) reads the record with this identity. It lives
// here, with its role assignment, so removing the bounded lab leaves no orphaned assignment.
resource onpremIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: names.fieldOfficeIdentity
  location: location
  tags: tags
}

resource onpremReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: container
  name: guid(container.id, onpremIdentity.id, blobDataReaderRoleId)
  properties: {
    principalId: onpremIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobDataReaderRoleId)
  }
}

output lab object = {
  resourceGroup: resourceGroup().name
  hubVnetId: hub.id
  hubVnetName: hub.name
  spokeVnetId: spoke.id
  dnsInboundSubnetId: hub.properties.subnets[0].id
  connectorsSubnetId: hub.properties.subnets[1].id
  privateEndpointsSubnetId: hub.properties.subnets[2].id
  recordsAccountId: records.id
  recordsAccountName: records.name
  recordsBlobHost: '${records.name}.blob.${environment().suffixes.storage}'
  recordsContainer: recordsContainer
  privateDnsZoneId: zone.id
  appVm: names.appVm
  appIp: hosts.app
  onpremIdentityId: onpremIdentity.id
  onpremIdentityClientId: onpremIdentity.properties.clientId
}
