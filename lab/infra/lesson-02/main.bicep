targetScope = 'subscription'

@description('Keep the isolated Lesson 2 resources in the approved course region.')
param location string = 'eastus2'

@description('The probe source contains no credentials. Encoding preserves its exact Python syntax.')
param probeSourceBase64 string

@description('Create the GitHub environment trust only when the workflow is ready to use it.')
param includeFederation bool = false

@description('SystemAssigned tests the same container without the UAMI attachment; the UAMI resource and grants remain.')
@allowed(['Both', 'UserAssigned', 'SystemAssigned'])
param probeIdentity string = 'Both'

var tags = {
  course: 'SC500'
  lesson: '02'
  workload: 'ContosoServiceHub'
  managedBy: 'sc500-l02-iac'
  lifecycle: 'retain-until-recording-complete'
}

resource identityGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-sc500-l02-identity'
  location: location
  tags: tags
}

resource targetGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-sc500-l02-target'
  location: location
  tags: tags
}

module workload './workload.bicep' = {
  name: 'sc500-l02-workload'
  scope: identityGroup
  params: {
    location: location
    tags: tags
    targetGroupId: targetGroup.id
    probeSourceBase64: probeSourceBase64
    includeFederation: includeFederation
    probeIdentity: probeIdentity
  }
}

// A dedicated empty target proves the permission boundary without exposing course data.
module grants './reader-grants.bicep' = {
  name: 'sc500-l02-reader-grants'
  scope: targetGroup
  params: {
    systemPrincipalId: workload.outputs.systemPrincipalId
    userPrincipalId: workload.outputs.userPrincipalId
  }
}

output containerGroupId string = workload.outputs.containerGroupId
output systemPrincipalId string = workload.outputs.systemPrincipalId
output userPrincipalId string = workload.outputs.userPrincipalId
output userClientId string = workload.outputs.userClientId
output userIdentityId string = workload.outputs.userIdentityId
output targetGroupId string = targetGroup.id
output federationEnabled bool = includeFederation
