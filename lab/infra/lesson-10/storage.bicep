// The knowledge store behind ServiceHub's internal assistant, with the access mistake built in.
//
// The assistant's agent identity gets Storage Blob Data Reader on the WHOLE account. That's the
// overexposure the lesson finds and fixes: the assistant needs only the knowledge container, but
// an account-scope grant also reaches the finance container. The triage agent is scoped
// correctly, to the tickets container only, so the two agents from one blueprint show different
// reach. Invoke-L10AgentDemo.ps1 -Mode Scope narrows the assistant during the demo, and
// Reset-L10Lab.ps1 (or a redeploy) puts the mistake back for the next run.
param location string
@description('Storage account name (CAF, Contoso): stservicehubkbprod<your-name-suffix>.')
param storageName string
param containers array
param assistantPrincipalId string
param triagePrincipalId string
param operatorObjectId string
param roles object
param managedBy string

// The name comes from config.json names.storageAccount, so the demo's portal link can name it exactly.

resource st 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  tags: { managedBy: managedBy }
  properties: {
    // Identities only: no account keys, no SAS, no anonymous blobs.
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
  }
}

// Lab economy, as in Lesson 9: turn the subscription's Defender for Storage plan off for this one
// account, so a few kilobytes of fixtures don't add a per-account meter. The subscription plan
// itself is unchanged.
resource defenderOff 'Microsoft.Security/defenderForStorageSettings@2022-12-01-preview' = {
  name: 'current'
  scope: st
  properties: { isEnabled: false, overrideSubscriptionLevelSettings: true }
}

resource blob 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: st
  name: 'default'
}

resource cont 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [for c in containers: {
  parent: blob
  name: c
  properties: { publicAccess: 'None' }
}]

// The overbroad grant: the whole account.
resource assistantReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(st.id, assistantPrincipalId, roles.blobDataReader)
  scope: st
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.blobDataReader)
    principalId: assistantPrincipalId
    principalType: 'ServicePrincipal'
    description: 'SC-500 L10: the assistant, scoped too broadly on purpose'
  }
}

// The correct grant: one container. The tickets container is the last in the list.
resource ticketsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' existing = {
  parent: blob
  name: 'tickets'
}

resource triageReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(st.id, 'tickets', triagePrincipalId, roles.blobDataReader)
  scope: ticketsContainer
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.blobDataReader)
    principalId: triagePrincipalId
    principalType: 'ServicePrincipal'
    description: 'SC-500 L10: the triage agent, scoped to its container'
  }
  dependsOn: [ cont ]
}

resource operatorContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(st.id, operatorObjectId, roles.blobDataContributor)
  scope: st
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.blobDataContributor)
    principalId: operatorObjectId
    principalType: 'User'
    description: 'SC-500 L10: the operator uploads the fixture files'
  }
}

output lab object = {
  resourceGroup: resourceGroup().name
  storage: st.name
  storageId: st.id
  blobEndpoint: st.properties.primaryEndpoints.blob
  assistantRoleAssignmentId: assistantReader.id
}
