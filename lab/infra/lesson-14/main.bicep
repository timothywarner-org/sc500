// Lesson 14 lab: detection and response on Lesson 13's Microsoft Sentinel workspace.
//
// Why subscription scope: the lab touches two resource groups. The response pieces (playbook,
// its Sentinel connection, the workbook) live in a Lesson 14 group that Lesson 14 owns outright.
// The detection pieces (analytics rule, automation rule, hunting queries) are extension resources
// on the Lesson 13 workspace, so they have to deploy into the Lesson 13 group.
targetScope = 'subscription'

@description('Region for the Lesson 14 response resource group (match the workspace region).')
param location string

@description('Lesson 14 resource group for the playbook, its connection, and the workbook.')
param resourceGroupName string

@description('Lesson 13 resource group that holds the Sentinel workspace.')
param l13ResourceGroupName string

@description('Lesson 13 Log Analytics workspace with Microsoft Sentinel enabled.')
param workspaceName string

@description('The Contoso CAF tag set from config.json, lowercase keys, including managedby, which Remove-L14Lab.ps1 checks before deleting anything.')
param tags object

@description('Baseline tag value for the lab.')
param baseline string

@description('Object ID of the Azure Security Insights service principal in this tenant, looked up by Deploy-L14Lab.ps1 from Microsoft\'s documented app ID. Microsoft Sentinel uses it to run playbooks.')
param securityInsightsPrincipalId string

@description('Resource names and IDs from config.json.')
param names object

@description('Rule schedule, severity, and MITRE mapping from config.json.')
param detection object

@description('Built-in role definition IDs from config.json.')
param roles object

// The course and lesson live in tags, never in names (Cloud Adoption Framework naming guidance, https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming).
var labTags = union(tags, { baseline: baseline })

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: labTags
}

resource l13rg 'Microsoft.Resources/resourceGroups@2024-03-01' existing = {
  name: l13ResourceGroupName
}

var workspaceId = '${l13rg.id}/providers/Microsoft.OperationalInsights/workspaces/${workspaceName}'
var ruleId = '${workspaceId}/providers/Microsoft.SecurityInsights/alertRules/${names.analyticsRuleId}'

module responseModule 'response.bicep' = {
  scope: rg
  name: 'l14-response'
  params: {
    location: location
    tags: labTags
    workspaceId: workspaceId
    ruleId: ruleId
    names: names
    roles: roles
    securityInsightsPrincipalId: securityInsightsPrincipalId
  }
}

module detectionModule 'detection.bicep' = {
  scope: l13rg
  name: 'l14-detection'
  params: {
    workspaceName: workspaceName
    names: names
    detection: detection
    roles: roles
    // Reading these outputs makes ARM finish the response module first, so the playbook and
    // Sentinel's permission to run it exist before the automation rule points at them.
    playbookId: responseModule.outputs.playbookId
    playbookPrincipalId: responseModule.outputs.playbookPrincipalId
    tenantId: tenant().tenantId
  }
}

output lab object = {
  resourceGroup: rg.name
  workspaceId: workspaceId
  analyticsRuleId: detectionModule.outputs.analyticsRuleId
  automationRuleId: detectionModule.outputs.automationRuleId
  playbookId: responseModule.outputs.playbookId
  playbookName: names.playbook
  playbookPrincipalId: responseModule.outputs.playbookPrincipalId
  workbookId: responseModule.outputs.workbookId
  huntingQueryIds: detectionModule.outputs.huntingQueryIds
}
