targetScope = 'resourceGroup'

@description('Existing training SQL Managed Instance. This template does not create compute.')
param managedInstanceName string
@description('Resource ID of the existing destination Log Analytics workspace.')
param workspaceId string

resource instance 'Microsoft.Sql/managedInstances@2023-08-01' existing = {
  name: managedInstanceName
}
// EXTERNAL_MONITOR needs a separate diagnostic route before its records reach Log Analytics.
resource auditRoute 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'sc500-servicehub-audit'
  scope: instance
  properties: {
    workspaceId: workspaceId
    logs: [{ category: 'SQLSecurityAuditEvents', enabled: true }]
  }
}
