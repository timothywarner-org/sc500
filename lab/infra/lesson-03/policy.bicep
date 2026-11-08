@description('The permitted region for the isolated policy fixture.')
param location string
@description('The L3-only custom definition.')
param ownershipDefinitionId string
@description('Exact built-in Allowed locations definition resolved from Azure.')
param allowedLocationsPolicyId string

resource locationRule 'Microsoft.Authorization/policyAssignments@2025-03-01' = {
  name: 'sc500-l03-locations'
  properties: {
    displayName: 'SC500 L03 allowed lab location'
    policyDefinitionId: allowedLocationsPolicyId
    enforcementMode: 'Default'
    parameters: { listOfAllowedLocations: { value: [location] } }
    nonComplianceMessages: [{ message: 'The isolated Lesson 3 fixture must remain in its configured region.' }]
  }
}
resource ownerRule 'Microsoft.Authorization/policyAssignments@2025-03-01' = {
  name: 'sc500-l03-course-tag'
  properties: {
    displayName: 'SC500 L03 course ownership'
    policyDefinitionId: ownershipDefinitionId
    enforcementMode: 'Default'
    nonComplianceMessages: [{ message: 'Lesson 3 managed identity fixtures require course=SC500.' }]
  }
}
