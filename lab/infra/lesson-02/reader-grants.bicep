param systemPrincipalId string
param userPrincipalId string

var readerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')

// Including scope, principal and role keeps a redeployment from creating duplicate grants.
resource systemReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, systemPrincipalId, readerRoleId)
  properties: {
    roleDefinitionId: readerRoleId
    principalId: systemPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource userReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, userPrincipalId, readerRoleId)
  properties: {
    roleDefinitionId: readerRoleId
    principalId: userPrincipalId
    principalType: 'ServicePrincipal'
  }
}
