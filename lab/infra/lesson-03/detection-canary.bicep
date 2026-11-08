targetScope = 'resourceGroup'
param location string = resourceGroup().location
param runnerPrincipalId string
var vaultName = 'kv-sc500-l03-signal-${take(uniqueString(resourceGroup().id), 4)}'
// This separate fixture contains only a labeled synthetic value; the ServiceHub private vault stays closed.
resource vault 'Microsoft.KeyVault/vaults@2026-02-01' = {
  name: vaultName
  location: location
  tags: { course: 'SC500', lesson: '03', managedBy: 'sc500-l03-iac', purpose: 'synthetic-alert-validation' }
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
    networkAcls: { defaultAction: 'Allow', bypass: 'None' }
  }
}
resource fixture 'Microsoft.KeyVault/vaults/secrets@2026-02-01' = {
  parent: vault
  name: 'servicehub-maintenance-demo'
  properties: {
    value: 'Fictional Contoso detection fixture. This value authenticates nowhere.'
    contentType: 'text/plain'
  }
}
resource readRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, runnerPrincipalId, 'detection-read')
  scope: vault
  properties: {
    principalId: runnerPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
  }
}
output vaultId string = vault.id
output vaultName string = vault.name
output grantId string = readRole.id
