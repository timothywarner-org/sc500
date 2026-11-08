// Defender for Cloud plans that Lesson 4's sections 4.2 and 4.4 depend on (subscription scope).
//
//
// Set-L04DefenderWindow.ps1 deploys this; run it directly only to preview:
//   az deployment sub what-if --location eastus2 --template-file infra/lesson-04/defender-plans.bicep \
//     --parameters state=TakeReady
//
// Sources (checked 2026-10-10):
//   https://learn.microsoft.com/azure/templates/microsoft.security/2024-01-01/pricings
//   https://learn.microsoft.com/azure/defender-for-cloud/defender-for-storage-rest-api-enablement
//   https://learn.microsoft.com/azure/defender-for-cloud/sql-azure-vulnerability-assessment-enable-classic
targetScope = 'subscription'

@description('TakeReady for a demo window, Parked otherwise.')
@allowed([
  'TakeReady'
  'Parked'
])
param state string = 'Parked'

var takeReady = state == 'TakeReady'
var standard = {
  pricingTier: 'Standard'
}
var free = {
  pricingTier: 'Free'
}

resource storageAccounts 'Microsoft.Security/pricings@2024-01-01' = {
  name: 'StorageAccounts'
  properties: takeReady ? {
    pricingTier: 'Standard'
    subPlan: 'DefenderForStorageV2'
    extensions: [
      {
        name: 'OnUploadMalwareScanning'
        isEnabled: 'True'
        additionalExtensionProperties: {
          CapGBPerMonthPerStorageAccount: '10000'
          BlobScanResultsOptions: 'BlobIndexTags'
          AutomatedResponse: 'None'
        }
      }
      {
        name: 'SensitiveDataDiscovery'
        isEnabled: 'True'
      }
    ]
  } : free
}

// Pricing updates are applied one plan at a time, so each plan waits for the one before it.
resource sqlServers 'Microsoft.Security/pricings@2024-01-01' = {
  name: 'SqlServers'
  properties: takeReady ? standard : free
  dependsOn: [
    storageAccounts
  ]
}

resource sqlServerVirtualMachines 'Microsoft.Security/pricings@2024-01-01' = {
  name: 'SqlServerVirtualMachines'
  properties: takeReady ? standard : free
  dependsOn: [
    sqlServers
  ]
}

resource openSourceRelationalDatabases 'Microsoft.Security/pricings@2024-01-01' = {
  name: 'OpenSourceRelationalDatabases'
  properties: takeReady ? standard : free
  dependsOn: [
    sqlServerVirtualMachines
  ]
}

resource cosmosDbs 'Microsoft.Security/pricings@2024-01-01' = {
  name: 'CosmosDbs'
  properties: takeReady ? standard : free
  dependsOn: [
    openSourceRelationalDatabases
  ]
}

output state string = state
