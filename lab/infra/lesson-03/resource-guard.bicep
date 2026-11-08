@description('Must match the protected vault region.')
param location string = 'eastus2'

// The backup operator receives no authority on this separate resource-group boundary.
resource guard 'Microsoft.DataProtection/resourceGuards@2025-09-01' = {
  name: 'guard-sc500-l03'
  location: location
  tags: { course: 'SC500', lesson: '03', managedBy: 'sc500-l03-iac', lifecycle: 'retained' }
  properties: { vaultCriticalOperationExclusionList: [] }
}
output guardId string = guard.id
