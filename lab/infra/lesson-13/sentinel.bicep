// Lesson 13 security data plane: workspace, Microsoft Sentinel, custom table, and collection rules.
targetScope = 'resourceGroup'

param location string
param names object
param workspace object
param customTable object
param collection object
param operatorObjectId string
param roles object
param tags object

// ---- 13.1 The workspace and Microsoft Sentinel ----------------------------------------------------
resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: names.workspace
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: workspace.retentionInDays
    workspaceCapping: { dailyQuotaGb: workspace.dailyQuotaGb }
    features: { enableLogAccessUsingOnlyResourcePermissions: true }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Enabling Sentinel on a workspace is one resource: its onboarding state.
resource sentinel 'Microsoft.SecurityInsights/onboardingStates@2024-09-01' = {
  scope: law
  name: 'default'
  properties: {}
}

// ---- 13.4 The custom table ---------------------------------------------------------------------
// Created before any data arrives, so the schema is a decision rather than a side effect.
resource audit 'Microsoft.OperationalInsights/workspaces/tables@2023-09-01' = {
  parent: law
  name: names.customTable
  properties: {
    plan: customTable.plan
    retentionInDays: customTable.retentionInDays
    totalRetentionInDays: customTable.totalRetentionInDays
    schema: {
      name: names.customTable
      description: 'ServiceHub application audit events. SC-500 Lesson 13 synthetic fixture.'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'FixtureId', type: 'string', description: 'Unique ID for one synthetic batch' }
        { name: 'EvidenceClass', type: 'string' }
        { name: 'CaseId', type: 'string' }
        { name: 'Actor', type: 'string' }
        { name: 'Operation', type: 'string' }
        { name: 'TargetResource', type: 'string' }
        { name: 'Result', type: 'string' }
        { name: 'ClientIp', type: 'string' }
        { name: 'Detail', type: 'string' }
      ]
    }
  }
}

var la = [ { name: 'la', workspaceResourceId: law.id } ]

// ---- 13.3 Linux: Syslog and CEF on separate facilities -----------------------------------------
resource dcrSyslog 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: names.dcrSyslog
  location: location
  tags: tags
  kind: 'Linux'
  properties: {
    description: 'Syslog from the ServiceHub log forwarder. local4 is left to the CEF rule.'
    dataSources: {
      syslog: [ { name: 'syslog', streams: [ 'Microsoft-Syslog' ], facilityNames: collection.syslogFacilities, logLevels: collection.syslogLevels } ]
    }
    destinations: { logAnalytics: la }
    dataFlows: [ { streams: [ 'Microsoft-Syslog' ], destinations: [ 'la' ] } ]
  }
}

resource dcrCef 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: names.dcrCef
  location: location
  tags: tags
  kind: 'Linux'
  // CommonSecurityLog and SecurityEvent appear in a workspace only once Sentinel is enabled on it.
  dependsOn: [ sentinel ]
  properties: {
    description: 'CEF from appliances that send to the forwarder on local4.'
    dataSources: {
      syslog: [ {
        name: 'cef'
        streams: [ 'Microsoft-CommonSecurityLog' ]
        facilityNames: collection.cefFacilities
        logLevels: [ 'Debug', 'Info', 'Notice', 'Warning', 'Error', 'Critical', 'Alert', 'Emergency' ]
      } ]
    }
    destinations: { logAnalytics: la }
    dataFlows: [ { streams: [ 'Microsoft-CommonSecurityLog' ], destinations: [ 'la' ] } ]
  }
}

// ---- 13.3 Windows: Security events direct, and forwarded events through WEF --------------------
resource dcrWinSec 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: names.dcrWindowsSecurity
  location: location
  tags: tags
  kind: 'Windows'
  dependsOn: [ sentinel ]
  properties: {
    description: 'A narrow set of Windows Security events, filtered at the agent by XPath.'
    dataSources: {
      windowsEventLogs: [ { name: 'security', streams: [ 'Microsoft-SecurityEvent' ], xPathQueries: [ collection.windowsSecurityXPath ] } ]
    }
    destinations: { logAnalytics: la }
    dataFlows: [ { streams: [ 'Microsoft-SecurityEvent' ], destinations: [ 'la' ] } ]
  }
}

resource dcrWef 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: names.dcrForwarded
  location: location
  tags: tags
  kind: 'Windows'
  // WindowsEvent, like SecurityEvent, exists only once Sentinel is on: the first deploy into a new
  // workspace on 2026-11-06 failed InvalidOutputTable without this.
  dependsOn: [ sentinel ]
  properties: {
    description: 'Everything a WEF subscription delivers to the collector ForwardedEvents channel.'
    dataSources: {
      windowsEventLogs: [ { name: 'forwarded', streams: [ 'Microsoft-WindowsEvent' ], xPathQueries: [ collection.forwardedXPath ] } ]
    }
    destinations: { logAnalytics: la }
    dataFlows: [ { streams: [ 'Microsoft-WindowsEvent' ], destinations: [ 'la' ] } ]
  }
}

// ---- 13.4 ServiceHub's application audit, through the Logs Ingestion API -----------------------
// A Direct DCR carries its own logs ingestion endpoint, so no data collection endpoint is needed.
resource dcrServiceHub 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: names.dcrServiceHub
  location: location
  tags: tags
  kind: 'Direct'
  dependsOn: [ audit ]
  properties: {
    description: 'ServiceHub audit events to ServiceHubAudit_CL. Heartbeats are dropped by the transformation.'
    streamDeclarations: {
      'Custom-ServiceHubAudit': {
        columns: [
          { name: 'TimeGenerated', type: 'datetime' }
          { name: 'FixtureId', type: 'string' }
          { name: 'EvidenceClass', type: 'string' }
          { name: 'CaseId', type: 'string' }
          { name: 'Actor', type: 'string' }
          { name: 'Operation', type: 'string' }
          { name: 'TargetResource', type: 'string' }
          { name: 'Result', type: 'string' }
          { name: 'ClientIp', type: 'string' }
          { name: 'Detail', type: 'string' }
        ]
      }
    }
    destinations: { logAnalytics: la }
    dataFlows: [ {
      streams: [ 'Custom-ServiceHubAudit' ]
      destinations: [ 'la' ]
      transformKql: customTable.transformKql
      outputStream: 'Custom-${names.customTable}'
    } ]
  }
}

// You send the fixture with your own Entra identity; the Logs Ingestion API needs this role on the DCR.
resource publisher 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dcrServiceHub.id, operatorObjectId, roles.monitoringMetricsPublisher)
  scope: dcrServiceHub
  properties: {
    principalId: operatorObjectId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.monitoringMetricsPublisher)
  }
}

output dcrs object = {
  syslog: dcrSyslog.id
  cef: dcrCef.id
  windowsSecurity: dcrWinSec.id
  forwarded: dcrWef.id
}

output lab object = {
  resourceGroup: resourceGroup().name
  workspace: law.name
  workspaceId: law.id
  workspaceCustomerId: law.properties.customerId
  customTable: audit.name
  dcrServiceHubId: dcrServiceHub.id
  dcrServiceHubImmutableId: dcrServiceHub.properties.immutableId
  logsIngestionEndpoint: dcrServiceHub.properties.endpoints.logsIngestion
  dcrSyslogId: dcrSyslog.id
  dcrCefId: dcrCef.id
  dcrWindowsSecurityId: dcrWinSec.id
  dcrForwardedId: dcrWef.id
}
