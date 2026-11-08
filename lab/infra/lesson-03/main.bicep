targetScope = 'subscription'

@description('Azure region already checked for this lesson.')
param location string = 'eastus2'
@description('A valid SSH public key. No private key is required for Run Command.')
param sshPublicKey string
@description('Pinned Ubuntu image version resolved in the target region.')
param imageVersion string
@description('Small Gen2-capable VM size confirmed in this subscription.')
param vmSize string = 'Standard_B2s'
@description('Built-in location policy ID resolved by exact display name during preparation.')
param allowedLocationsPolicyId string
@description('Built-in Key Vault Secrets User role ID resolved during preparation.')
param secretsUserRoleId string

var tags = { course: 'SC500', lesson: '03', company: 'Contoso', managedBy: 'sc500-l03-iac' }
resource platform 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-sc500-l03-platform'
  location: location
  tags: tags
}
resource policyLab 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-sc500-l03-policy'
  location: location
  tags: tags
}
// Definition scope does not impose an effect until the narrow assignment below exists.
resource ownership 'Microsoft.Authorization/policyDefinitions@2025-03-01' = {
  name: 'sc500-l03-identity-course-tag'
  properties: {
    policyType: 'Custom'
    mode: 'All'
    displayName: 'SC500 L03 identities require the course ownership tag'
    description: 'Applies only where explicitly assigned. Training fixture, not a company-wide policy.'
    metadata: { category: 'SC500 training', lesson: '03' }
    policyRule: {
      if: {
        allOf: [
          { field: 'type', equals: 'Microsoft.ManagedIdentity/userAssignedIdentities' }
          { field: 'tags[course]', notEquals: 'SC500' }
        ]
      }
      then: { effect: 'deny' }
    }
  }
}
module lab './platform.bicep' = {
  name: 'sc500-l03-platform'
  scope: platform
  params: { location: location, tags: tags, sshPublicKey: sshPublicKey, imageVersion: imageVersion, vmSize: vmSize, secretsUserRoleId: secretsUserRoleId }
}
module controls './policy.bicep' = {
  name: 'sc500-l03-policy'
  scope: policyLab
  params: { location: location, ownershipDefinitionId: ownership.id, allowedLocationsPolicyId: allowedLocationsPolicyId }
}
output lab object = lab.outputs.lab
output policyScope string = policyLab.id
