// SC-500 Lesson 6 bounded lab: a Private Link service and a partner that consumes it.
//
// Provider side (Contoso): the parts API VM behind an internal Standard Load Balancer, and
// names.partsPrivateLink attached to the load balancer's frontend. The Private Link service
// source-NATs partner traffic to its NAT IP (10.61.0.68), so the parts API sees that address,
// never the partner's. Visibility is restricted to this subscription and auto-approval is empty,
// so every connection request waits for Contoso to approve it.
//
// Partner side (the Fabrikam stand-in): names.fabrikamVnet deliberately reuses the provider's address space
// (10.61.0.0/24), and the partner client even has the same IP as the parts API (10.61.0.4).
// Private Link doesn't care, because nothing is peered or routed. Demo 6.2 creates the partner's
// private endpoint with a manual request, then approves it from the provider side.
// Cost while deployed: about 0.06 USD an hour (see config.json).

param location string
param tags object
param sshPublicKey string
param imageVersion string
param vmSize string
param addressPlan object
param ports object
@description('Resource names from config.json names, per Cloud Adoption Framework naming guidance, https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming (CAF, applied to Contoso).')
param names object
@description('CAF naming components from config.json naming: env, region, instance.')
param naming object

var hosts = addressPlan.hosts

module providerEgress 'maintenance-egress.bicep' = {
  name: 'l06-maintenance-provider'
  params: { location: location, tags: tags, workload: 'partsapi', naming: naming }
}
module partnerEgress 'maintenance-egress.bicep' = {
  name: 'l06-maintenance-partner'
  params: { location: location, tags: tags, workload: 'fabrikam', naming: naming }
}

resource provider 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: names.partsVnet
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [addressPlan.provider] }
    subnets: [
      {
        name: 'snet-parts-backend'
        properties: {
          addressPrefix: addressPlan.providerBackend
          defaultOutboundAccess: false
          natGateway: { id: providerEgress.outputs.id }
        }
      }
      {
        name: 'snet-pls-nat'
        properties: {
          addressPrefix: addressPlan.providerPlsNat
          defaultOutboundAccess: false
          // Required on the subnet that holds the Private Link service's NAT IP.
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource lb 'Microsoft.Network/loadBalancers@2024-05-01' = {
  name: names.partsLoadBalancer
  location: location
  tags: tags
  sku: { name: 'Standard', tier: 'Regional' }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'fe-parts-api'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: hosts.partsFrontend
          subnet: { id: provider.properties.subnets[0].id }
        }
      }
    ]
    backendAddressPools: [{ name: 'be-parts-api' }]
    probes: [
      {
        name: 'probe-parts-api'
        properties: { protocol: 'Tcp', port: ports.parts, intervalInSeconds: 5, numberOfProbes: 2 }
      }
    ]
    loadBalancingRules: [
      {
        name: 'rule-parts-api'
        properties: {
          protocol: 'Tcp'
          frontendPort: ports.parts
          backendPort: ports.parts
          frontendIPConfiguration: { id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', names.partsLoadBalancer, 'fe-parts-api') }
          backendAddressPool: { id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', names.partsLoadBalancer, 'be-parts-api') }
          probe: { id: resourceId('Microsoft.Network/loadBalancers/probes', names.partsLoadBalancer, 'probe-parts-api') }
          disableOutboundSnat: true
        }
      }
    ]
  }
}

var partsListener = replace(replace(loadTextContent('listener-cloud-init.yaml'), '__ROLE__', 'parts API'), '__PORTS__', string(ports.parts))

module partsApi 'vm.bicep' = {
  name: 'l06-vm-parts-api'
  // Static child IDs keep what-if from skipping the VM; explicit dependencies retain order.
  dependsOn: [provider, lb]
  params: {
    name: names.partsVm
    location: location
    tags: tags
    subnetId: resourceId('Microsoft.Network/virtualNetworks/subnets', provider.name, 'snet-parts-backend')
    privateIp: hosts.partsApi
    customData: base64(partsListener)
    vmSize: vmSize
    sshPublicKey: sshPublicKey
    imageVersion: imageVersion
    lbBackendPoolIds: [resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lb.name, 'be-parts-api')]
  }
}

resource pls 'Microsoft.Network/privateLinkServices@2024-05-01' = {
  name: names.partsPrivateLink
  location: location
  tags: tags
  properties: {
    loadBalancerFrontendIpConfigurations: [{ id: lb.properties.frontendIPConfigurations[0].id }]
    ipConfigurations: [
      {
        name: 'nat-parts-api'
        properties: {
          primary: true
          privateIPAllocationMethod: 'Static'
          privateIPAddress: hosts.plsNat
          privateIPAddressVersion: 'IPv4'
          subnet: { id: provider.properties.subnets[1].id }
        }
      }
    ]
    // Restricted by subscription: only listed subscriptions can find the service by alias.
    // Auto-approval is empty, so every request lands as Pending for Contoso to review.
    visibility: { subscriptions: [subscription().subscriptionId] }
    autoApproval: { subscriptions: [] }
    enableProxyProtocol: false
  }
}

resource partner 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: names.fabrikamVnet
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [addressPlan.partner] }
    subnets: [
      {
        name: 'snet-partner'
        properties: {
          addressPrefix: addressPlan.partnerSubnet
          defaultOutboundAccess: false
          natGateway: { id: partnerEgress.outputs.id }
        }
      }
    ]
  }
}

module partnerClient 'vm.bicep' = {
  name: 'l06-vm-partner-client'
  dependsOn: [partner]
  params: {
    name: names.fabrikamVm
    location: location
    tags: tags
    subnetId: resourceId('Microsoft.Network/virtualNetworks/subnets', partner.name, 'snet-partner')
    privateIp: hosts.partnerClient
    vmSize: vmSize
    sshPublicKey: sshPublicKey
    imageVersion: imageVersion
  }
}

output lab object = {
  resourceGroup: resourceGroup().name
  plsId: pls.id
  plsName: pls.name
  plsAlias: pls.properties.alias
  partnerSubnetId: partner.properties.subnets[0].id
  partnerClient: names.fabrikamVm
  partsApiVm: names.partsVm
}
