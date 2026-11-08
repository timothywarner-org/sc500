// SC-500 Lesson 7 bounded resource: Azure Firewall Premium in the retained hub, attached to the
// retained policy and public IP, with resource-specific diagnostic logs.
//
// It bills about 1.75 USD an hour from creation to deletion, so Deploy-L07Bounded.ps1 creates it
// while you work through the demo and Remove-L07Bounded.ps1 deletes it. It must live in the same
// resource group as the hub VNet, which is why it isn't in a group of its own.

@description('Azure region.')
param location string

@description('Common tags from config.json. The firewall adds workload hub, env shared, and bounded true.')
param tags object

@description('Every resource name, from config.json.')
param names object

@description('Resource ID of AzureFirewallSubnet in the hub.')
param firewallSubnetId string

@description('Resource ID of the retained firewall public IP.')
param firewallPublicIpId string

@description('Resource ID of the retained firewall policy.')
param firewallPolicyId string

@description('Resource ID of the lesson Log Analytics workspace.')
param workspaceId string

resource firewall 'Microsoft.Network/azureFirewalls@2024-05-01' = {
  name: names.firewall
  location: location
  tags: union(tags, { workload: 'hub', env: 'shared', bounded: 'true', lifecycle: 'bounded: remove after the rehearsal or take' })
  properties: {
    sku: { name: 'AZFW_VNet', tier: 'Premium' }
    firewallPolicy: { id: firewallPolicyId }
    ipConfigurations: [
      {
        name: 'ipconfig-data'
        properties: {
          subnet: { id: firewallSubnetId }
          publicIPAddress: { id: firewallPublicIpId }
        }
      }
    ]
  }
}

// Dedicated = resource-specific tables instead of one AzureDiagnostics table. The categories are
// named one by one: the firewall also publishes the legacy AzureFirewall* categories, and the
// allLogs category group would enable those too. (With allLogs, the September 27 rehearsal
// delivered nothing to the workspace at all.)
var structuredLogs = [
  'AZFWApplicationRule'
  'AZFWNetworkRule'
  'AZFWNatRule'
  'AZFWThreatIntel'
  'AZFWIdpsSignature'
  'AZFWDnsQuery'
]

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: firewall
  name: names.firewallDiagnostics
  properties: {
    workspaceId: workspaceId
    logAnalyticsDestinationType: 'Dedicated'
    logs: [for c in structuredLogs: { category: c, enabled: true }]
  }
}

@description('The firewall\'s resource ID.')
output firewallId string = firewall.id

@description('The private IP the firewall took. The spoke routes expect 10.70.0.4.')
output privateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
