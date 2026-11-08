// Lesson 14 response resources: the playbook, its Microsoft Sentinel connection, the workbook,
// and Sentinel's permission to run the playbook. All of it lives in the Lesson 14 resource group.

@description('Region for every resource in this module.')
param location string

@description('Tags applied to every resource, including the ownership tag Remove-L14Lab.ps1 checks.')
param tags object

@description('Resource ID of the Lesson 13 Sentinel workspace.')
param workspaceId string

@description('Resource ID of the Lesson 14 analytics rule (the workbook filters incidents on it).')
param ruleId string

@description('Resource names and IDs from config.json.')
param names object

@description('Built-in role definition IDs from config.json.')
param roles object

@description('Object ID of the Azure Security Insights service principal.')
param securityInsightsPrincipalId string

// The Microsoft Sentinel connector, authenticated as the playbook's managed identity.
// parameterValueType Alternative is how Microsoft's own playbook templates select managed identity.
resource sentinelConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: names.sentinelConnection
  location: location
  tags: tags
  kind: 'V1'
  properties: {
    displayName: names.sentinelConnection
    customParameterValues: {}
    parameterValueType: 'Alternative'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azuresentinel')
    }
  }
}

// A Consumption logic app with one job: comment on the incident that ran it. It changes nothing
// else, so a rehearsal can run it as often as it likes. The comment carries the run ID, which ties
// the incident's comment to the exact row in the playbook's run history.
resource playbook 'Microsoft.Logic/workflows@2019-05-01' = {
  name: names.playbook
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        // Don't rename this trigger: Microsoft documents that renaming it breaks the Sentinel link.
        Microsoft_Sentinel_incident: {
          type: 'ApiConnectionWebhook'
          inputs: {
            body: {
              callback_url: '@{listCallbackUrl()}'
            }
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
              }
            }
            path: '/incident-creation'
          }
        }
      }
      actions: {
        'Add_comment_to_incident_(V3)': {
          type: 'ApiConnection'
          runAfter: {}
          inputs: {
            body: {
              incidentArmId: '@triggerBody()?[\'object\']?[\'id\']'
              message: '<p>ServiceHub response playbook. Run @{workflow()?[\'run\']?[\'name\']} received incident @{triggerBody()?[\'object\']?[\'properties\']?[\'incidentNumber\']} and queued it for ServiceHub security review. It changed nothing else: no account was disabled and no message was sent.</p>'
            }
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/Incidents/Comment'
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          azuresentinel: {
            connectionId: sentinelConnection.id
            connectionName: sentinelConnection.name
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azuresentinel')
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
        }
      }
    }
  }
}

// Microsoft Sentinel runs playbooks as its own service account, which needs this role on the
// playbook's resource group. Scoped to this group only.
resource sentinelCanRunPlaybooks 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, securityInsightsPrincipalId, roles.sentinelAutomationContributor)
  properties: {
    principalId: securityInsightsPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.sentinelAutomationContributor)
    description: 'Lets Microsoft Sentinel run the ServiceHub response playbook in this resource group.'
  }
}

// The investigation workbook. category sentinel with the workspace as sourceId is how Microsoft's
// own solution templates register a Sentinel workbook.
resource workbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: names.workbookId
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: names.workbook
    category: 'sentinel'
    sourceId: toLower(workspaceId)
    version: '1.0'
    serializedData: replace(replace(loadTextContent('workbook.json'), '__RULEID__', last(split(ruleId, '/'))), '__WORKSPACEID__', workspaceId)
  }
}

output playbookId string = playbook.id
output playbookPrincipalId string = playbook.identity.principalId
output workbookId string = workbook.id
