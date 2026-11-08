// SC-500 Lesson 5 retained lab: the Contoso platform hub and the ServiceHub workload spoke.
//
// Demo 5.1 segments the spoke with one NSG whose rules name application security groups
// instead of IP addresses. Demo 5.2 adds a platform guardrail with Azure Virtual Network
// Manager security admin rules. Both demos start from CTSO-L05-BASELINE, which is what this
// template declares: the NSG has only its default rules (the introduced fault, because the
// default AllowVnetInBound rule lets every tier reach every other tier), and the AVNM
// configuration exists but isn't deployed. The demo scripts make the intended changes and
// Reset-L05Lab.ps1 puts the baseline back.
//
// Every subnet is private (no default outbound internet access) and no VM has a public IP.

param location string
param tags object
param operatorObjectId string
param sshPublicKey string
param imageVersion string
param vmSize string
param addressPlan object
param ports object
@description('Storage Blob Data Reader role definition ID, resolved by name at deploy time.')
param blobDataReaderRoleId string

var cloudInit = loadTextContent('servicehub-cloud-init.yaml')
var suffix = substring(uniqueString(resourceGroup().id), 0, 6)

// ---------- Observability: where flow logs and later firewall/VPN diagnostics land ----------

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-sc500-l05'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

// Flow logs must go to a standard storage account in the same region as the VNet.
resource flowStore 'Microsoft.Storage/storageAccounts@2025-06-01' = {
  name: 'stsc500l05flow${suffix}'
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
  }
}

// The operator reads flow-log blobs with Microsoft Entra ID, never with the account key.
resource operatorReadsFlowLogs 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(flowStore.id, operatorObjectId, blobDataReaderRoleId)
  scope: flowStore
  properties: {
    principalId: operatorObjectId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobDataReaderRoleId)
  }
}

// ---------- Segmentation objects ----------

// Tier membership is a property of the NIC, not of an address. Rules that name these groups
// keep working when a tier scales out or a VM is rebuilt with a new IP.
resource asgWeb 'Microsoft.Network/applicationSecurityGroups@2024-05-01' = {
  name: 'asg-servicehub-web'
  location: location
  tags: tags
}
resource asgApp 'Microsoft.Network/applicationSecurityGroups@2024-05-01' = {
  name: 'asg-servicehub-app'
  location: location
  tags: tags
}
resource asgData 'Microsoft.Network/applicationSecurityGroups@2024-05-01' = {
  name: 'asg-servicehub-data'
  location: location
  tags: tags
}

// Baseline: default rules only. That's the fault demo 5.1 fixes. The demo script adds the
// least-privilege rules; Reset-L05Lab.ps1 removes them again.
resource nsgServiceHub 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-servicehub'
  location: location
  tags: tags
  properties: {}
}

resource nsgManagement 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-platform-management'
  location: location
  tags: tags
  properties: {}
}

// ---------- Hub and spoke ----------

resource hub 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-sc500-l05-hub'
  location: location
  tags: union(tags, { role: 'Contoso platform hub' })
  properties: {
    addressSpace: { addressPrefixes: [addressPlan.hub] }
    subnets: [
      {
        name: 'snet-management'
        properties: {
          addressPrefix: addressPlan.hubManagement
          defaultOutboundAccess: false
          networkSecurityGroup: { id: nsgManagement.id }
        }
      }
      {
        // Reserved for the bounded demo 5.4 VPN gateway. Gateway subnets take no NSG.
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: addressPlan.hubGateway
        }
      }
    ]
  }
}

resource spoke 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-sc500-l05-servicehub'
  location: location
  tags: union(tags, { role: 'ServiceHub workload spoke' })
  properties: {
    addressSpace: { addressPrefixes: [addressPlan.servicehub] }
    subnets: [
      {
        // One subnet for every tier on purpose: the ASGs, not subnet boundaries, separate them.
        name: 'snet-servicehub'
        properties: {
          addressPrefix: addressPlan.servicehubSubnet
          defaultOutboundAccess: false
          networkSecurityGroup: { id: nsgServiceHub.id }
        }
      }
    ]
  }
}

// Peering makes the hub part of the spoke's VirtualNetwork service tag. It grants no RBAC.
resource hubToSpoke 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: hub
  name: 'peer-hub-to-servicehub'
  properties: {
    remoteVirtualNetwork: { id: spoke.id }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}
resource spokeToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: spoke
  name: 'peer-servicehub-to-hub'
  properties: {
    remoteVirtualNetwork: { id: hub.id }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

// ---------- Fixture VMs ----------

var tiers = [
  { role: 'web', asg: asgWeb.id, port: ports.web, ip: addressPlan.hosts.web }
  { role: 'app', asg: asgApp.id, port: ports.app, ip: addressPlan.hosts.app }
  { role: 'data', asg: asgData.id, port: ports.data, ip: addressPlan.hosts.data }
]

module tierVms 'vm.bicep' = [for t in tiers: {
  name: 'vm-servicehub-${t.role}'
  params: {
    name: 'vm-servicehub-${t.role}'
    location: location
    tags: union(tags, { tier: t.role })
    subnetId: spoke.properties.subnets[0].id
    privateIp: t.ip
    asgIds: [t.asg]
    customData: base64(replace(replace(cloudInit, '__ROLE__', t.role), '__PORTS__', string(t.port)))
    vmSize: vmSize
    sshPublicKey: sshPublicKey
    imageVersion: imageVersion
  }
}]

// The platform security scanner. Demo 5.2's Always Allow rule exists for this source.
module scannerVm 'vm.bicep' = {
  name: 'vm-platform-scan'
  params: {
    name: 'vm-platform-scan'
    location: location
    tags: union(tags, { tier: 'platform-management' })
    subnetId: hub.properties.subnets[0].id
    privateIp: addressPlan.hosts.mgmt
    vmSize: vmSize
    sshPublicKey: sshPublicKey
    imageVersion: imageVersion
  }
}

// ---------- Azure Virtual Network Manager (defined here, deployed by demo 5.2) ----------

resource avnm 'Microsoft.Network/networkManagers@2024-05-01' = {
  name: 'avnm-sc500-l05'
  location: location
  tags: tags
  properties: {
    description: 'Contoso platform network manager for the SC-500 Lesson 5 lab.'
    networkManagerScopes: {
      subscriptions: [subscription().id]
      managementGroups: []
    }
    networkManagerScopeAccesses: ['SecurityAdmin']
  }
}

resource workloadGroup 'Microsoft.Network/networkManagers/networkGroups@2024-05-01' = {
  parent: avnm
  name: 'ng-servicehub-workloads'
  properties: {
    description: 'Workload spokes that must carry the Contoso platform guardrails.'
    memberType: 'VirtualNetwork'
  }
}

// Waits for the peering, not just the VNet: on 2026-09-26 a static member created while the
// spoke was still settling failed with no detail, and the same write succeeded on retry.
resource workloadMember 'Microsoft.Network/networkManagers/networkGroups/staticMembers@2024-05-01' = {
  parent: workloadGroup
  name: 'sm-servicehub-spoke'
  dependsOn: [spokeToHub]
  properties: { resourceId: spoke.id }
}

resource baselineConfig 'Microsoft.Network/networkManagers/securityAdminConfigurations@2024-05-01' = {
  parent: avnm
  name: 'sac-contoso-platform-baseline'
  properties: {
    description: 'Platform guardrails that workload NSGs cannot override.'
    applyOnNetworkIntentPolicyBasedServices: ['None']
  }
}

resource guardrails 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections@2024-05-01' = {
  parent: baselineConfig
  name: 'rc-platform-remote-access'
  properties: {
    description: 'Remote administration reaches workloads only from the platform management subnet.'
    appliesToGroups: [{ networkGroupId: workloadGroup.id }]
  }
}

// Priority 100 is evaluated before 200, so the scanner's SSH matches Always Allow first.
resource allowScanner 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections/rules@2024-05-01' = {
  parent: guardrails
  name: 'AlwaysAllow-PlatformScanner-SSH'
  kind: 'Custom'
  properties: {
    description: 'The platform scanner always reaches SSH, even when a workload NSG denies it.'
    access: 'AlwaysAllow'
    direction: 'Inbound'
    priority: 100
    protocol: 'Tcp'
    sources: [{ addressPrefixType: 'IPPrefix', addressPrefix: addressPlan.hubManagement }]
    destinations: [{ addressPrefixType: 'IPPrefix', addressPrefix: '*' }]
    sourcePortRanges: ['0-65535']
    destinationPortRanges: ['22']
  }
}

resource denyRemoteAdmin 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections/rules@2024-05-01' = {
  parent: guardrails
  name: 'Deny-RemoteAdmin-Elsewhere'
  kind: 'Custom'
  properties: {
    description: 'No other source reaches SSH or RDP, even when a workload NSG allows it.'
    access: 'Deny'
    direction: 'Inbound'
    priority: 200
    protocol: 'Tcp'
    sources: [{ addressPrefixType: 'IPPrefix', addressPrefix: '*' }]
    destinations: [{ addressPrefixType: 'IPPrefix', addressPrefix: '*' }]
    sourcePortRanges: ['0-65535']
    destinationPortRanges: ['22', '3389']
  }
}

output lab object = {
  resourceGroup: resourceGroup().name
  hubVnetId: hub.id
  spokeVnetId: spoke.id
  nsgId: nsgServiceHub.id
  asgIds: { web: asgWeb.id, app: asgApp.id, data: asgData.id }
  workspaceId: workspace.id
  workspaceCustomerId: workspace.properties.customerId
  flowStoreId: flowStore.id
  flowStoreName: flowStore.name
  networkManagerId: avnm.id
  networkGroupId: workloadGroup.id
  securityAdminConfigId: baselineConfig.id
  vms: {
    web: tierVms[0].outputs.vmId
    app: tierVms[1].outputs.vmId
    data: tierVms[2].outputs.vmId
    scanner: scannerVm.outputs.vmId
  }
}
