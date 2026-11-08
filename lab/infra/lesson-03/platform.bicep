@description('Region for all regional resources.')
param location string
@description('Course ownership labels used by the script allowlist.')
param tags object
@description('Public key only, for password-disabled VM provisioning.')
param sshPublicKey string
@description('Exact marketplace image version, not latest.')
param imageVersion string
@description('Small supported runner size.')
param vmSize string
@description('Resolved built-in role definition ID.')
param secretsUserRoleId string

var vaultName = 'kv-sc500-l03-${take(uniqueString(subscription().id, resourceGroup().id), 8)}'
resource bootstrap 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'id-sc500-l03-bootstrap'
  location: location
  tags: tags
}
resource egressIp 'Microsoft.Network/publicIPAddresses@2025-09-01' = {
  name: 'pip-sc500-l03-egress'
  location: location
  tags: union(tags, { lifecycle: 'rehearsal-only' })
  sku: { name: 'Standard', tier: 'Regional' }
  properties: { publicIPAllocationMethod: 'Static', publicIPAddressVersion: 'IPv4' }
}
// NAT provides VM Agent egress without opening an inbound path to the guest.
resource nat 'Microsoft.Network/natGateways@2025-09-01' = {
  name: 'nat-sc500-l03-egress'
  location: location
  tags: union(tags, { lifecycle: 'rehearsal-only' })
  sku: { name: 'Standard' }
  properties: { idleTimeoutInMinutes: 4, publicIpAddresses: [{ id: egressIp.id }] }
}
resource nsg 'Microsoft.Network/networkSecurityGroups@2025-09-01' = {
  name: 'nsg-sc500-l03-runner'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'DenyInbound'
        properties: { priority: 4000, direction: 'Inbound', access: 'Deny', protocol: '*', sourcePortRange: '*', destinationPortRange: '*', sourceAddressPrefix: '*', destinationAddressPrefix: '*' }
      }
    ]
  }
}
resource vnet 'Microsoft.Network/virtualNetworks@2025-09-01' = {
  name: 'vnet-sc500-l03'
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: ['10.53.0.0/24'] }
    subnets: [
      { name: 'runner', properties: { addressPrefix: '10.53.0.0/26', defaultOutboundAccess: false, networkSecurityGroup: { id: nsg.id }, natGateway: { id: nat.id } } }
      { name: 'endpoints', properties: { addressPrefix: '10.53.0.64/26', defaultOutboundAccess: false, privateEndpointNetworkPolicies: 'Disabled' } }
    ]
  }
}
resource nic 'Microsoft.Network/networkInterfaces@2025-09-01' = {
  name: 'nic-sc500-l03-runner'
  location: location
  tags: tags
  properties: {
    enableIPForwarding: false
    ipConfigurations: [{ name: 'primary', properties: { primary: true, privateIPAllocationMethod: 'Dynamic', privateIPAddressVersion: 'IPv4', subnet: { id: '${vnet.id}/subnets/runner' } } }]
  }
}
resource runner 'Microsoft.Compute/virtualMachines@2026-04-01' = {
  //checkov:skip=CKV_AZURE_50:Run Command requires the VM Agent and extension operations; this private lab VM has no inbound management port and is deallocated after rehearsal.
  name: 'vm-sc500-l03-runner'
  location: location
  tags: tags
  identity: { type: 'SystemAssigned, UserAssigned', userAssignedIdentities: { '${bootstrap.id}': {} } }
  properties: {
    hardwareProfile: { vmSize: vmSize }
    securityProfile: { securityType: 'TrustedLaunch', encryptionAtHost: true, uefiSettings: { secureBootEnabled: true, vTpmEnabled: true } }
    osProfile: {
      computerName: 'sc500-l03-runner'
      adminUsername: 'contosolab'
      allowExtensionOperations: true
      linuxConfiguration: {
        disablePasswordAuthentication: true
        provisionVMAgent: true
        ssh: { publicKeys: [{ path: '/home/contosolab/.ssh/authorized_keys', keyData: sshPublicKey }] }
      }
    }
    storageProfile: {
      imageReference: { publisher: 'Canonical', offer: 'ubuntu-24_04-lts', sku: 'server', version: imageVersion }
      osDisk: {
        name: 'disk-sc500-l03-runner'
        createOption: 'FromImage'
        deleteOption: 'Detach'
        caching: 'ReadWrite'
        // The service rejected the advertised additionalDiskProperties payload. The deployment script hardens export on the resulting disk.
        managedDisk: { storageAccountType: 'StandardSSD_LRS' }
      }
    }
    networkProfile: { networkInterfaces: [{ id: nic.id, properties: { primary: true, deleteOption: 'Detach' } }] }
    diagnosticsProfile: { bootDiagnostics: { enabled: true } }
  }
}
resource vault 'Microsoft.KeyVault/vaults@2026-02-01' = {
  name: vaultName
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    sku: { name: 'standard', family: 'A' }
    accessPolicies: []
    enableRbacAuthorization: true
    enableSoftDelete: true
    enablePurgeProtection: true
    softDeleteRetentionInDays: 7
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    publicNetworkAccess: 'Disabled'
    networkAcls: { defaultAction: 'Deny', bypass: 'None' }
  }
}
resource endpoint 'Microsoft.Network/privateEndpoints@2025-09-01' = {
  name: 'pe-sc500-l03-vault'
  location: location
  tags: tags
  properties: {
    subnet: { id: '${vnet.id}/subnets/endpoints' }
    privateLinkServiceConnections: [{ name: 'contoso-vault', properties: { privateLinkServiceId: vault.id, groupIds: ['vault'] } }]
  }
}
resource zone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
  tags: tags
}
resource link 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: zone
  name: 'sc500-l03'
  location: 'global'
  properties: { registrationEnabled: false, virtualNetwork: { id: vnet.id } }
}
resource zoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2025-09-01' = {
  parent: endpoint
  name: 'default'
  properties: { privateDnsZoneConfigs: [{ name: 'keyvault', properties: { privateDnsZoneId: zone.id } }] }
}
// Persistent workload access is read-only. Temporary object administration is removed in finally.
resource readRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: vault
  name: guid(vault.id, runner.id, secretsUserRoleId)
  properties: { roleDefinitionId: secretsUserRoleId, principalId: runner.identity.principalId, principalType: 'ServicePrincipal' }
}
resource recovery 'Microsoft.RecoveryServices/vaults@2026-07-01' = {
  name: 'rsv-sc500-l03'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  identity: { type: 'SystemAssigned' }
  properties: {
    publicNetworkAccess: 'Disabled'
    redundancySettings: { standardTierStorageRedundancy: 'LocallyRedundant', crossRegionRestore: 'Disabled' }
    securitySettings: {
      immutabilitySettings: { state: 'Unlocked', configuration: { type: 'AsPerPolicy' } }
      // The current service requires AlwaysON for both secure-by-default soft-delete controls.
      softDeleteSettings: { softDeleteState: 'AlwaysON', softDeleteRetentionPeriodInDays: 14, enhancedSecurityState: 'AlwaysON' }
    }
  }
}
output lab object = {
  resourceGroup: resourceGroup().name
  vaultId: vault.id
  vaultName: vault.name
  vaultUri: vault.properties.vaultUri
  runnerId: runner.id
  runnerName: runner.name
  runnerPrincipalId: runner.identity.principalId
  bootstrapPrincipalId: bootstrap.properties.principalId
  bootstrapClientId: bootstrap.properties.clientId
  recoveryVaultId: recovery.id
  recoveryVaultName: recovery.name
  endpointId: endpoint.id
  dnsZoneId: zone.id
}
