// Lesson 4 resources at resource-group scope.
//
// Two storage accounts play two different roles in the Contoso ServiceHub story:
//   records  holds service records and restricted customer documents. It starts in a
//            deliberately legacy state (Shared Key allowed, firewall with no rule for the
//            operator) so demo 4.1 can show each control change and its effect live.
//   intake   is where customers' uploaded files land. It is Entra-only from the start and
//            reachable from public networks, because untrusted uploads are exactly where
//            Defender for Storage malware scanning earns its cost (demo 4.2).
// One logical SQL server with a Basic database carries demo 4.3 (Entra-only
// authentication, TLS, firewall, TDE, server-level auditing) and demo 4.4 (Defender for
// Azure SQL coverage, inherited from the subscription plan).

param location string
param tags object
param operatorObjectId string
param operatorUpn string
param operatorIp string
@description('Region for the logical SQL server and database.')
param sqlLocation string = location
param blobDataReaderRoleId string
param blobDataOwnerRoleId string
@description('Declare the express vulnerability assessment scanner. Express configuration needs the Defender for Azure SQL plan on first, so Deploy-L04Lab.ps1 passes false while that plan is Free (parked) and the Defender window turns the scanner on later with sql-vulnerability-assessment.bicep.')
param vulnerabilityAssessmentEnabled bool = true

// Deterministic suffix: the same subscription always produces the same globally unique
// names, so a redeploy updates the lab instead of creating a second copy.
var suffix = take(uniqueString(subscription().id, 'sc500-l04'), 6)
var recordsName = 'stsc500l04rec${suffix}'
var intakeName = 'stsc500l04in${suffix}'
// The region is part of the SQL name because ARM keeps a failed create's name bound to
// its original region (InvalidResourceLocation on retry), so a region change needs a new name.
var sqlName = 'sql-sc500-l04-${suffix}-${sqlLocation}'

// ---------------------------------------------------------------- records account
resource records 'Microsoft.Storage/storageAccounts@2025-06-01' = {
  name: recordsName
  location: location
  tags: union(tags, { role: 'service-records' })
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    accessTier: 'Hot'
    // Baseline settings every account should carry. Demo 4.1 reads them back on screen.
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    // INTRODUCED FAULT for demo 4.1: account keys still work. The demo disables Shared Key
    // live; Reset-L04Lab.ps1 restores this baseline for the next take.
    allowSharedKeyAccess: true
    // Double encryption at rest. It can only be chosen when the account is created.
    encryption: {
      requireInfrastructureEncryption: true
      keySource: 'Microsoft.Storage'
      services: {
        blob: { enabled: true, keyType: 'Account' }
        file: { enabled: true, keyType: 'Account' }
      }
    }
    // Enabled from selected networks, with no IP rule yet: every data-plane request from
    // the internet is rejected until demo 4.1 adds the workstation's address. Setting
    // defaultAction explicitly avoids the template gotcha where publicNetworkAccess alone
    // leaves the firewall at Allow.
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

resource recordsBlob 'Microsoft.Storage/storageAccounts/blobServices@2025-06-01' = {
  parent: records
  name: 'default'
}

resource serviceRecords 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01' = {
  parent: recordsBlob
  name: 'service-records'
  properties: { publicAccess: 'None' }
}

resource customerDocuments 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01' = {
  parent: recordsBlob
  name: 'customer-documents'
  properties: { publicAccess: 'None' }
}

// Kim may read service records and nothing else. Scoping the data role to one container
// is the point of demo 4.1's allowed-versus-rejected read. Subscription Owner grants no
// data access at all once account keys stop working.
resource kimReadsServiceRecords 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: serviceRecords
  name: guid(serviceRecords.id, operatorObjectId, blobDataReaderRoleId)
  properties: {
    principalId: operatorObjectId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobDataReaderRoleId)
    description: 'SC-500 Lesson 4: Kim Akers reads Contoso service records only'
  }
}

// ---------------------------------------------------------------- intake account
resource intake 'Microsoft.Storage/storageAccounts@2025-06-01' = {
  name: intakeName
  location: location
  tags: union(tags, { role: 'customer-upload-intake' })
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    // Entra-only from day one; the portal also defaults to Entra authorization.
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    // Reachable from public networks on purpose: uploads come from outside, and the test
    // upload in demo 4.2 comes from Azure Cloud Shell. Identity, not network, is the gate.
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource intakeBlob 'Microsoft.Storage/storageAccounts/blobServices@2025-06-01' = {
  parent: intake
  name: 'default'
}

resource intakeUploads 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01' = {
  parent: intakeBlob
  name: 'intake-uploads'
  properties: { publicAccess: 'None' }
}

// Owner, not Contributor, because reading the malware-scan result tags needs
// blobs/tags/read, which Storage Blob Data Contributor doesn't include.
resource kimOwnsIntake 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: intakeUploads
  name: guid(intakeUploads.id, operatorObjectId, blobDataOwnerRoleId)
  properties: {
    principalId: operatorObjectId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobDataOwnerRoleId)
    description: 'SC-500 Lesson 4: upload the malware test file and read its scan-result tags'
  }
}

// ---------------------------------------------------------------- audit destination
resource workspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: 'law-sc500-l04'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

// ---------------------------------------------------------------- SQL
resource sql 'Microsoft.Sql/servers@2025-01-01' = {
  name: sqlName
  location: sqlLocation
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    // TLS 1.0 and 1.1 are retired for Azure SQL; 1.2 is the lowest value accepted.
    minimalTlsVersion: '1.2'
    // Selected networks: public endpoint on, but only the firewall rule below can reach it.
    publicNetworkAccess: 'Enabled'
    // Entra-only from creation, so no SQL authentication login or password ever exists.
    administrators: {
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: true
      login: operatorUpn
      sid: operatorObjectId
      tenantId: tenant().tenantId
      principalType: 'User'
    }
  }
}

resource workstationRule 'Microsoft.Sql/servers/firewallRules@2025-01-01' = {
  parent: sql
  name: 'kim-akers-workstation'
  properties: {
    startIpAddress: operatorIp
    endIpAddress: operatorIp
  }
}

resource db 'Microsoft.Sql/servers/databases@2025-01-01' = {
  parent: sql
  name: 'servicehub-records'
  location: sqlLocation
  tags: tags
  sku: { name: 'Basic', tier: 'Basic', capacity: 5 }
  properties: {
    maxSizeBytes: 2147483648
    requestedBackupStorageRedundancy: 'Local'
  }
}

// TDE is on by default for new databases. Declaring it keeps the intent in code and makes
// what-if flag any drift.
resource tde 'Microsoft.Sql/servers/databases/transparentDataEncryption@2025-01-01' = {
  parent: db
  name: 'current'
  properties: { state: 'Enabled' }
}

// Server-level auditing to Log Analytics. The audit records flow through a diagnostic
// setting on the master database, which is why that setting must exist first.
resource master 'Microsoft.Sql/servers/databases@2025-01-01' existing = {
  parent: sql
  name: 'master'
}

resource auditToWorkspace 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: master
  name: 'SQLSecurityAuditEvents_sc500-l04'
  properties: {
    workspaceId: workspace.id
    logs: [
      { category: 'SQLSecurityAuditEvents', enabled: true }
    ]
  }
  dependsOn: [ db ]
}

resource serverAudit 'Microsoft.Sql/servers/auditingSettings@2025-01-01' = {
  parent: sql
  name: 'default'
  properties: {
    state: 'Enabled'
    isAzureMonitorTargetEnabled: true
    auditActionsAndGroups: [
      'BATCH_COMPLETED_GROUP'
      'SUCCESSFUL_DATABASE_AUTHENTICATION_GROUP'
      'FAILED_DATABASE_AUTHENTICATION_GROUP'
    ]
  }
  dependsOn: [ auditToWorkspace ]
}

// Vulnerability assessment, express configuration: no storage account, results kept by
// the service. Defender for Azure SQL (subscription plan) covers the server; this switches
// on the scanner for it explicitly so findings exist before the demo. Skipped while the plan is
// parked (see vulnerabilityAssessmentEnabled); incremental mode leaves an existing scanner as it is.
resource vulnerabilityAssessment 'Microsoft.Sql/servers/sqlVulnerabilityAssessments@2023-08-01' = if (vulnerabilityAssessmentEnabled) {
  parent: sql
  name: 'default'
  properties: { state: 'Enabled' }
  dependsOn: [ db ]
}

output lab object = {
  resourceGroup: resourceGroup().name
  recordsAccount: records.name
  recordsId: records.id
  intakeAccount: intake.name
  intakeId: intake.id
  sqlServer: sql.name
  sqlServerId: sql.id
  sqlFqdn: sql.properties.fullyQualifiedDomainName
  sqlDatabase: db.name
  workspaceName: workspace.name
  workspaceId: workspace.id
  workspaceCustomerId: workspace.properties.customerId
}
