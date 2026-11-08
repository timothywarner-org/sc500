// SC-500 Lesson 5, demo 5.3: a secured Virtual WAN hub for the same ServiceHub tiers.
//
// This is the Virtual WAN alternative to the customer-managed hub in network.bicep, not a
// second copy running beside it in the story. It's bounded: Deploy-L05Wan.ps1 creates it for
// a rehearsal or take and removes it afterward, because the hub and firewall bill by the hour.
//
// Security configuration shown:
//   * Standard Virtual WAN (Basic hubs can't host a firewall or transit VNet traffic).
//   * Azure Firewall Basic in the hub, driven by a Firewall Policy.
//   * Routing intent with a private traffic policy, so spoke-to-spoke traffic must pass the
//     firewall. Without it the hub router would connect the spokes directly, uninspected.
//   * Firewall logs in the retained Lesson 5 Log Analytics workspace.
// Internet traffic stays off the routing policy in this lab: the fixtures have no internet
// dependency, and the slide explains that option instead.

param location string
param tags object
param addressPlan object
param ports object
param sshPublicKey string
param imageVersion string
param vmSize string
@description('Resource ID of law-sc500-l05 in the retained Lesson 5 resource group.')
param workspaceId string

var cloudInit = loadTextContent('servicehub-cloud-init.yaml')

resource wan 'Microsoft.Network/virtualWans@2024-05-01' = {
  name: 'vwan-sc500-l05'
  location: location
  tags: tags
  properties: {
    type: 'Standard'
    allowBranchToBranchTraffic: true
    disableVpnEncryption: false
  }
}

resource hub 'Microsoft.Network/virtualHubs@2024-05-01' = {
  name: 'vhub-sc500-l05-eastus2'
  location: location
  tags: tags
  properties: {
    addressPrefix: addressPlan.wanHub
    sku: 'Standard'
    virtualWan: { id: wan.id }
  }
}

// Firewall Basic supports threat intelligence in alert mode only; Standard or Premium can deny.
resource policy 'Microsoft.Network/firewallPolicies@2024-05-01' = {
  name: 'afwp-sc500-l05'
  location: location
  tags: tags
  properties: {
    sku: { tier: 'Basic' }
    threatIntelMode: 'Alert'
  }
}

// One allowed east-west path. Everything else between the spokes hits the firewall's
// default deny, which the network rule log records.
resource eastWest 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-05-01' = {
  parent: policy
  name: 'rcg-servicehub-east-west'
  properties: {
    priority: 200
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'allow-servicehub-to-shared-api'
        priority: 100
        action: { type: 'Allow' }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'servicehub-app-to-shared-api'
            description: 'ServiceHub app tier calls the shared parts API. Nothing else crosses spokes.'
            ipProtocols: ['TCP']
            sourceAddresses: [addressPlan.wanServicehub]
            destinationAddresses: [addressPlan.wanShared]
            destinationPorts: [string(ports.shared)]
          }
        ]
      }
    ]
  }
}

resource firewall 'Microsoft.Network/azureFirewalls@2024-05-01' = {
  name: 'afw-sc500-l05-hub'
  location: location
  tags: tags
  dependsOn: [eastWest]
  properties: {
    sku: { name: 'AZFW_Hub', tier: 'Basic' }
    virtualHub: { id: hub.id }
    hubIPAddresses: { publicIPs: { count: 1 } }
    firewallPolicy: { id: policy.id }
  }
}

resource firewallLogs 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-law-sc500-l05'
  scope: firewall
  properties: {
    workspaceId: workspaceId
    // Resource-specific tables (AZFWNetworkRule and friends) instead of AzureDiagnostics.
    logAnalyticsDestinationType: 'Dedicated'
    logs: [{ categoryGroup: 'allLogs', enabled: true }]
  }
}

var spokes = [
  { key: 'servicehub', name: 'vnet-sc500-l05-wan-servicehub', prefix: addressPlan.wanServicehub, vm: 'vm-wan-servicehub-app', ip: addressPlan.wanHosts.app, ports: '80' }
  { key: 'shared', name: 'vnet-sc500-l05-wan-shared', prefix: addressPlan.wanShared, vm: 'vm-wan-shared-api', ip: addressPlan.wanHosts.shared, ports: '${ports.shared} ${ports.data}' }
]

resource spokeVnets 'Microsoft.Network/virtualNetworks@2024-05-01' = [for s in spokes: {
  name: s.name
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [s.prefix] }
    subnets: [
      {
        name: 'snet-workload'
        properties: {
          addressPrefix: s.prefix
          defaultOutboundAccess: false
        }
      }
    ]
  }
}]

// Connections are made after the firewall exists, and routing intent after the connections,
// because the hub router rejects concurrent updates.
@batchSize(1)
resource connections 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2024-05-01' = [for (s, i) in spokes: {
  parent: hub
  name: 'conn-${s.key}'
  dependsOn: [firewall]
  properties: {
    remoteVirtualNetwork: { id: spokeVnets[i].id }
    enableInternetSecurity: false
  }
}]

resource routingIntent 'Microsoft.Network/virtualHubs/routingIntent@2024-05-01' = {
  parent: hub
  name: 'ri-private-traffic-to-firewall'
  dependsOn: [connections]
  properties: {
    routingPolicies: [
      {
        name: 'PrivateTrafficPolicy'
        destinations: ['PrivateTraffic']
        nextHop: firewall.id
      }
    ]
  }
}

module vms 'vm.bicep' = [for (s, i) in spokes: {
  name: s.vm
  params: {
    name: s.vm
    location: location
    tags: tags
    subnetId: spokeVnets[i].properties.subnets[0].id
    privateIp: s.ip
    customData: base64(replace(replace(cloudInit, '__ROLE__', s.key), '__PORTS__', s.ports))
    vmSize: vmSize
    sshPublicKey: sshPublicKey
    imageVersion: imageVersion
  }
}]

output lab object = {
  resourceGroup: resourceGroup().name
  virtualWanId: wan.id
  hubId: hub.id
  firewallId: firewall.id
  firewallPolicyId: policy.id
  vms: { app: vms[0].outputs.vmId, shared: vms[1].outputs.vmId }
}
