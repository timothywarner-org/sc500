@description('Same harmless resource name for violating and compliant requests.')
param name string = 'id-sc500-l03-policy-probe'
@description('Configured lab region.')
param location string = 'eastus2'
@description('True supplies the tag required by the lab policy.')
param compliant bool = true
// The fault changes metadata on an identity that has no roles or credentials.
resource fixture 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: name
  location: location
  tags: compliant ? { course: 'SC500', lesson: '03', managedBy: 'sc500-l03-iac' } : { lesson: '03', managedBy: 'sc500-l03-iac' }
}
output fixtureId string = fixture.id
