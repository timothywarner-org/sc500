// SC-500 Lesson 7 retained resources, deployed into rg-perimeter-shared-eastus2 by main.bicep.
//
// Contoso's ServiceHub perimeter: a hub VNet that will hold Azure Firewall Premium, and two spoke
// VNets, production and test, peered only to the hub. Each spoke's route table sends 0.0.0.0/0 to
// the firewall's private IP, so spoke-to-spoke and internet traffic can only move through the
// firewall, and the firewall denies what no rule allows.
//
// The firewall itself is NOT here: it bills about 1.75 USD an hour, so Deploy-L07Bounded.ps1
// creates it while you work through the demo. Everything here costs cents a day with the VMs
// deallocated. While the firewall is absent, the spoke routes point at an address nobody holds,
// so the spokes have no path out at all, which is also the Zero Trust default.
//
// Every name comes from the names object (config.json). Every resource carries the common tags
// plus its own workload and env, the Cloud Adoption Framework's functional tags.

@description('Azure region for every resource.')
param location string

@description('Common tags from config.json.')
param tags object

@description('Object ID of the operator who imports the inspection CA.')
param operatorObjectId string

@description('The operator\'s current public IPv4 address, admitted by the Key Vault firewall.')
param operatorPublicIp string

@description('SSH public key for the Linux VMs.')
param sshPublicKey string

@description('Pinned Ubuntu image version.')
param imageVersion string

@description('VM size.')
param vmSize string

@description('Every resource name, from config.json.')
param names object

@description('Address plan, from config.json.')
param addressPlan object

@description('Listener ports, from config.json.')
param ports object

@description('Probe targets, from config.json.')
param tests object

@description('Base64 of the lab root CA public certificate (PEM). Public data.')
param rootCaB64 string

@description('Base64 of the inspection CA public certificate (PEM). Public data.')
param interCaB64 string

@description('Role definition ID (GUID) of Key Vault Secrets User.')
#disable-next-line secure-secrets-in-params // A role definition GUID, public data; the rule matches 'Secrets' in the role's name.
param keyVaultSecretsUserRoleId string

@description('Role definition ID (GUID) of Key Vault Certificates Officer.')
param keyVaultCertificatesOfficerRoleId string

@description('Auto-shutdown settings from config.json.')
param autoShutdown object

var hubTags = union(tags, { workload: 'hub', env: 'shared' })
var prodTags = union(tags, { workload: 'servicehub', env: 'prod' })
var testTags = union(tags, { workload: 'servicehub', env: 'test' })
var firewallIp = addressPlan.hosts.firewall

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: names.workspace
  location: location
  tags: hubTags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

// The firewall policy reads its inspection CA from Key Vault as this identity.
resource firewallIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: names.firewallIdentity
  location: location
  tags: hubTags
}

// Azure RBAC for the data plane (Microsoft documents both RBAC and access policies for the
// firewall). The vault's own firewall denies by default: Azure Firewall Premium is a Key Vault
// trusted service, and the operator's current public IP is allowed only so the deploy script
// can import the CA. The name is fixed in config.json and checked for availability by the deploy
// script's preflight, because vault names are global.
resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: names.keyVault
  location: location
  tags: hubTags
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: [{ value: operatorPublicIp }]
    }
  }
}

// Key Vault access is audited to the lesson workspace, the Microsoft cloud security benchmark's
// logging control for a vault that holds a CA key.
resource vaultDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: vault
  name: names.keyVaultDiagnostics
  properties: {
    workspaceId: workspace.id
    logAnalyticsDestinationType: 'Dedicated'
    logs: [{ category: 'AuditEvent', enabled: true }]
  }
}

resource firewallReadsSecrets 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: vault
  name: guid(vault.id, firewallIdentity.id, keyVaultSecretsUserRoleId)
  properties: {
    principalId: firewallIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
  }
}

resource operatorImportsCertificates 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: vault
  name: guid(vault.id, operatorObjectId, keyVaultCertificatesOfficerRoleId)
  properties: {
    principalId: operatorObjectId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultCertificatesOfficerRoleId)
  }
}

// Retained so the DNAT rule's destination never changes between firewall deployments. Its
// ddosSettings show which DDoS tier applies: with no plan, only infrastructure protection.
resource firewallPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: names.firewallPublicIp
  location: location
  tags: hubTags
  sku: { name: 'Standard', tier: 'Regional' }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// Production's NSG admits exactly one thing: the app port, from the firewall's subnet (DNAT
// traffic arrives SNATed to a firewall instance address). Everything else inbound is denied here
// too, so production doesn't depend on the firewall alone.
resource prodNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: names.prodNsg
  location: location
  tags: prodTags
  properties: {
    securityRules: [
      {
        name: 'allow-app-from-firewall'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: addressPlan.hubFirewall
          sourcePortRange: '*'
          destinationAddressPrefix: addressPlan.hosts.prodApp
          destinationPortRange: string(ports.app)
          description: 'The published status page reaches production only through the firewall.'
        }
      }
      {
        name: 'deny-all-other-inbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Sits above AllowVnetInBound, so peered and routed sources are not trusted by default.'
        }
      }
    ]
  }
}

// Test keeps only the default rules, the way a lot of dev subscriptions look. The firewall is the
// only thing between it and production, which Network Watcher shows in 7.3.
resource testNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: names.nonprodNsg
  location: location
  tags: testTags
  properties: { securityRules: [] }
}

resource prodRoutes 'Microsoft.Network/routeTables@2024-05-01' = {
  name: names.prodRouteTable
  location: location
  tags: prodTags
  properties: {
    disableBgpRoutePropagation: true
    routes: [
      {
        name: 'default-to-hub-firewall'
        properties: { addressPrefix: '0.0.0.0/0', nextHopType: 'VirtualAppliance', nextHopIpAddress: firewallIp }
      }
    ]
  }
}

resource testRoutes 'Microsoft.Network/routeTables@2024-05-01' = {
  name: names.nonprodRouteTable
  location: location
  tags: testTags
  properties: {
    disableBgpRoutePropagation: true
    routes: [
      {
        name: 'default-to-hub-firewall'
        properties: { addressPrefix: '0.0.0.0/0', nextHopType: 'VirtualAppliance', nextHopIpAddress: firewallIp }
      }
    ]
  }
}

resource hub 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: names.hubVnet
  location: location
  tags: hubTags
  properties: {
    addressSpace: { addressPrefixes: [addressPlan.hub] }
    subnets: [
      {
        // The name is fixed by the platform, the minimum size is /26, and nothing else may live
        // here. The firewall takes the first usable address, 10.70.0.4.
        name: 'AzureFirewallSubnet'
        properties: { addressPrefix: addressPlan.hubFirewall }
      }
    ]
  }
}

resource prod 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: names.prodVnet
  location: location
  tags: prodTags
  properties: {
    addressSpace: { addressPrefixes: [addressPlan.prod] }
    subnets: [
      {
        name: names.appSubnet
        properties: {
          addressPrefix: addressPlan.prodApp
          networkSecurityGroup: { id: prodNsg.id }
          routeTable: { id: prodRoutes.id }
          defaultOutboundAccess: false
        }
      }
    ]
  }
}

resource test 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: names.nonprodVnet
  location: location
  tags: testTags
  properties: {
    addressSpace: { addressPrefixes: [addressPlan.nonprod] }
    subnets: [
      {
        name: names.appSubnet
        properties: {
          addressPrefix: addressPlan.nonprodApp
          networkSecurityGroup: { id: testNsg.id }
          routeTable: { id: testRoutes.id }
          defaultOutboundAccess: false
        }
      }
    ]
  }
}

// Spokes peer to the hub and never to each other. allowForwardedTraffic lets the firewall hand a
// spoke traffic that started somewhere other than the hub. Peerings on one VNet are serialized
// with explicit dependsOn, because parallel peering updates on the same VNet can collide.
resource hubToProd 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: hub
  name: names.hubToProd
  properties: {
    remoteVirtualNetwork: { id: prod.id }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
  }
}

resource hubToTest 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: hub
  name: names.hubToNonprod
  dependsOn: [hubToProd]
  properties: {
    remoteVirtualNetwork: { id: test.id }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
  }
}

resource prodToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: prod
  name: names.prodToHub
  dependsOn: [hubToProd]
  properties: {
    remoteVirtualNetwork: { id: hub.id }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
  }
}

resource testToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: test
  name: names.nonprodToHub
  dependsOn: [hubToTest]
  properties: {
    remoteVirtualNetwork: { id: hub.id }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
  }
}

// The probe's test list. The production VM runs it once a minute through the firewall.
var probeTests = [
  { name: 'allowed-url', scheme: 'https', host: 'learn.microsoft.com', path: tests.allowedProbePath }
  { name: 'same-site-other-path', scheme: 'https', host: 'learn.microsoft.com', path: tests.otherProbePath }
  { name: 'unlisted-site', scheme: 'https', host: tests.unlistedHost, path: '/' }
  { name: 'threat-intel-test', scheme: 'http', host: tests.threatIntelTestFqdn, path: '/' }
  { name: 'prod-to-nonprod', scheme: 'tcp', host: addressPlan.hosts.nonprodApp, port: ports.app }
]
var initTemplate = loadTextContent('app-cloud-init.yaml')
var initCommon = replace(replace(replace(replace(initTemplate, '__PORT__', string(ports.app)), '__ROOT_CA_B64__', rootCaB64), '__INTER_CA_B64__', interCaB64), '__TI_FQDN__', tests.threatIntelTestFqdn)
var initProd = replace(replace(replace(initCommon, '__ROLE__', 'ServiceHub production'), '__PROBE__', 'true'), '__TESTS_B64__', base64(string(probeTests)))
var initTest = replace(replace(replace(initCommon, '__ROLE__', 'ServiceHub non-production'), '__PROBE__', 'false'), '__TESTS_B64__', base64('[]'))

module prodVm 'vm.bicep' = {
  name: 'contoso-perimeter-vm-prod'
  params: {
    name: names.prodVm
    location: location
    tags: prodTags
    subnetId: prod.properties.subnets[0].id
    privateIp: addressPlan.hosts.prodApp
    customData: base64(initProd)
    vmSize: vmSize
    sshPublicKey: sshPublicKey
    imageVersion: imageVersion
    autoShutdown: autoShutdown
  }
}

module testVm 'vm.bicep' = {
  name: 'contoso-perimeter-vm-test'
  params: {
    name: names.nonprodVm
    location: location
    tags: testTags
    subnetId: test.properties.subnets[0].id
    privateIp: addressPlan.hosts.nonprodApp
    customData: base64(initTest)
    vmSize: vmSize
    sshPublicKey: sshPublicKey
    imageVersion: imageVersion
    autoShutdown: autoShutdown
  }
}

@description('Resource IDs, names and addresses the lesson scripts read back from the deployment record. No secrets.')
output lab object = {
  resourceGroup: resourceGroup().name
  keyVaultName: vault.name
  keyVaultUri: vault.properties.vaultUri
  firewallIdentityId: firewallIdentity.id
  firewallIdentityPrincipalId: firewallIdentity.properties.principalId
  workspaceId: workspace.id
  workspaceCustomerId: workspace.properties.customerId
  firewallPublicIpId: firewallPublicIp.id
  firewallPublicIpAddress: firewallPublicIp.properties.ipAddress
  hubVnetId: hub.id
  firewallSubnetId: hub.properties.subnets[0].id
  prodVmId: prodVm.outputs.vmId
  prodNicId: prodVm.outputs.nicId
  nonprodVmId: testVm.outputs.vmId
  nonprodNicId: testVm.outputs.nicId
}
