param location string = 'eastus2'

// Azure Backup stores only restored VM configuration here; the firewall permits trusted services.
resource staging 'Microsoft.Storage/storageAccounts@2025-08-01' = {
  name: 'stsc500l03restore${take(uniqueString(subscription().id, resourceGroup().id), 6)}'
  location: location
  tags: { course: 'SC500', lesson: '03', managedBy: 'sc500-l03-iac', lifecycle: 'retained' }
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    publicNetworkAccess: 'Enabled'
    networkAcls: { defaultAction: 'Deny', bypass: 'AzureServices', ipRules: [], virtualNetworkRules: [] }
    accessTier: 'Hot'
  }
}
output storageId string = staging.id
output storageName string = staging.name
