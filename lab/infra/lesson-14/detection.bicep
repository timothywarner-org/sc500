// Lesson 14 detection resources, deployed onto Lesson 13's workspace: the scheduled analytics
// rule, two saved hunting queries, the playbook's permission to comment on incidents, and the
// automation rule that tags each new incident and runs the playbook.

@description('Lesson 13 Log Analytics workspace with Microsoft Sentinel enabled.')
param workspaceName string

@description('Resource names and IDs from config.json.')
param names object

@description('Rule schedule, severity, and MITRE mapping from config.json.')
param detection object

@description('Built-in role definition IDs from config.json.')
param roles object

@description('Resource ID of the response playbook.')
param playbookId string

@description('Object ID of the playbook\'s system-assigned managed identity.')
param playbookPrincipalId string

@description('Tenant ID, which the RunPlaybook action requires.')
param tenantId string

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

// The scheduled rule. One alert per matching row, so each export gets its own entities, and an
// incident for every alert (Defender XDR takes this instruction once the workspace is connected).
resource exportRule 'Microsoft.SecurityInsights/alertRules@2025-09-01' = {
  scope: workspace
  name: names.analyticsRuleId
  kind: 'Scheduled'
  properties: {
    displayName: names.analyticsRule
    description: 'A ServiceHub service account read a full parts export with no service case attached. Approved export jobs are excluded in the query. Synthetic fixture data.'
    enabled: true
    severity: detection.severity
    query: loadTextContent('kql/rule-export-no-case.kql')
    queryFrequency: detection.queryFrequency
    queryPeriod: detection.queryPeriod
    triggerOperator: 'GreaterThan'
    triggerThreshold: 0
    suppressionEnabled: false
    suppressionDuration: 'PT5H'
    tactics: detection.tactics
    techniques: detection.techniques
    eventGroupingSettings: {
      aggregationKind: 'AlertPerResult'
    }
    entityMappings: [
      {
        entityType: 'Account'
        fieldMappings: [
          {
            identifier: 'Name'
            columnName: 'Actor'
          }
        ]
      }
      {
        entityType: 'IP'
        fieldMappings: [
          {
            identifier: 'Address'
            columnName: 'ClientIp'
          }
        ]
      }
      {
        entityType: 'File'
        fieldMappings: [
          {
            identifier: 'Name'
            columnName: 'FileName'
          }
        ]
      }
    ]
    customDetails: {
      FixtureId: 'FixtureId'
      ExportDetail: 'Detail'
    }
    alertDetailsOverride: {
      alertDisplayNameFormat: 'Parts export with no service case by {{Actor}}'
      alertDescriptionFormat: '{{Actor}} read {{FileName}} from {{ClientIp}} with no service case attached.'
    }
    incidentConfiguration: {
      createIncident: true
      groupingConfiguration: {
        enabled: true
        reopenClosedIncident: false
        lookbackDuration: detection.groupingLookback
        matchingMethod: 'AllEntities'
        groupByEntities: []
        groupByAlertDetails: []
        groupByCustomDetails: []
      }
    }
  }
}

// Saved hunting queries. Microsoft Sentinel's Hunting page lists workspace saved searches in the
// "Hunting Queries" category, with tactics and techniques read from the tags.
resource huntExportActor 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspace
  name: names.huntExportActor
  properties: {
    category: 'Hunting Queries'
    displayName: 'ServiceHub exports with no service case, by actor'
    query: loadTextContent('kql/hunt-export-actor.kql')
    version: 2
    tags: [
      {
        name: 'description'
        value: 'Which ServiceHub accounts read full parts exports without a service case, how often, and from where.'
      }
      {
        name: 'tactics'
        value: 'Collection,Exfiltration'
      }
      {
        name: 'techniques'
        value: 'T1530'
      }
    ]
  }
}

resource huntStoreKeys 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspace
  name: names.huntStoreKeys
  properties: {
    category: 'Hunting Queries'
    displayName: 'Key reads on the parts-export store'
    query: loadTextContent('kql/hunt-store-keys.kql')
    version: 2
    tags: [
      {
        name: 'description'
        value: 'Successful listKeys calls on the ServiceHub parts-export storage account, from the Azure Activity log.'
      }
      {
        name: 'tactics'
        value: 'CredentialAccess'
      }
      {
        name: 'techniques'
        value: 'T1552'
      }
    ]
  }
}

// The playbook's managed identity may comment on incidents in this workspace, and nothing more.
resource playbookCanComment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: workspace
  name: guid(workspace.id, playbookPrincipalId, roles.sentinelResponder)
  properties: {
    principalId: playbookPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.sentinelResponder)
    description: 'Lets the ServiceHub response playbook comment on incidents.'
  }
}

// The automation rule: only incidents from the export rule, tag first, then run the playbook.
resource exportAutomation 'Microsoft.SecurityInsights/automationRules@2025-09-01' = {
  scope: workspace
  name: names.automationRuleId
  properties: {
    displayName: names.automationRule
    order: 1
    triggeringLogic: {
      isEnabled: true
      triggersOn: 'Incidents'
      triggersWhen: 'Created'
      conditions: [
        {
          conditionType: 'Property'
          conditionProperties: {
            propertyName: 'IncidentRelatedAnalyticRuleIds'
            operator: 'Contains'
            propertyValues: [
              exportRule.id
            ]
          }
        }
      ]
    }
    actions: [
      {
        order: 1
        actionType: 'ModifyProperties'
        actionConfiguration: {
          labels: [for tag in names.incidentTags: {
            labelName: tag
          }]
        }
      }
      {
        order: 2
        actionType: 'RunPlaybook'
        actionConfiguration: {
          logicAppResourceId: playbookId
          tenantId: tenantId
        }
      }
    ]
  }
  dependsOn: [
    playbookCanComment
  ]
}

output analyticsRuleId string = exportRule.id
output automationRuleId string = exportAutomation.id
output huntingQueryIds array = [
  huntExportActor.id
  huntStoreKeys.id
]
