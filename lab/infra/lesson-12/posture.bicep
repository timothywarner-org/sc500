// ServiceHub's storage for Lesson 12: the nightly parts-export store (the posture fixture) and the
// archive store beside it.
// The fault is deliberate and bounded: allowSharedKeyAccess is true on both, so anyone holding an account
// key or a key-signed SAS could read them with no Microsoft Entra identity behind the request. That's the
// drift Lesson 4 removed from the records store, reappearing on stores another team created later.
// Everything else is set the way a careful team would set it (TLS 1.2, HTTPS only, no anonymous blob
// access), so the recommendation Defender for Cloud raises is about the one thing demo 12.1 fixes.
// The two stores differ in one way on purpose: the export store accepts traffic from the internet and
// the archive store disables public network access. Defender CSPM weighs exposure when it calculates a
// risk level, so the same Medium-severity recommendation can carry a different risk level on each.
param location string
param names object
param operatorObjectId string
param roles object
param tags object

var storeSecurity = {
  allowSharedKeyAccess: true
  allowBlobPublicAccess: false
  minimumTlsVersion: 'TLS1_2'
  supportsHttpsTrafficOnly: true
}

resource store 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: names.exportStorage
  location: location
  tags: union(tags, { purpose: 'parts exports' })
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: union(storeSecurity, {
    publicNetworkAccess: 'Enabled'
    networkAcls: { defaultAction: 'Allow', bypass: 'AzureServices' }
  })
}

resource archive 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: names.archiveStorage
  location: location
  tags: union(tags, { purpose: 'parts archive' })
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: union(storeSecurity, {
    publicNetworkAccess: 'Disabled'
    networkAcls: { defaultAction: 'Deny', bypass: 'AzureServices' }
  })
}

// No blob container here on purpose. Defender CSPM doesn't bill a storage account that has no
// containers, so the idle baseline costs nothing; Deploy-L12Lab.ps1 -Stage creates the export store's
// container and the fictional export before a take, and Reset-L12Lab.ps1 removes them again.

// Idle baseline: the export store opts out of the subscription's Defender for Storage plan, which bills
// per storage account. The plan demo turns it back on for this account with a small malware-scanning cap,
// which is the resource-level override the lesson teaches, and Reset puts the opt-out back. The archive
// store sets nothing here, so it inherits whatever the subscription plan says.
resource defenderForStorage 'Microsoft.Security/defenderForStorageSettings@2025-01-01' = {
  name: 'current'
  scope: store
  properties: {
    isEnabled: false
    overrideSubscriptionLevelSettings: true
  }
}

// You upload the fictional export with your own Entra identity, never a key, so the demo's own data
// path doesn't depend on the setting it's about to turn off. Storage Blob Data Owner, scoped to this
// one store, because reading blob index tags (where Defender for Storage writes its malware scan
// verdict) needs blobs/tags/read, and Owner is the least-privileged built-in role that has it.
resource operatorData 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(store.id, operatorObjectId, roles.storageBlobDataOwner)
  scope: store
  properties: {
    principalId: operatorObjectId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageBlobDataOwner)
  }
}

output lab object = {
  resourceGroup: resourceGroup().name
  storage: store.name
  storageId: store.id
  archiveStorage: archive.name
  archiveStorageId: archive.id
  container: names.container
}
