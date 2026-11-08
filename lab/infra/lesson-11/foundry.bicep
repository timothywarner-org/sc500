// SC-500 Lesson 11 retained resources (resource group scope). See main.bicep for the overview.
// Every name is derived from the group ID, so a redeploy lands on the same resources.

param location string
param names object
param model object
param blocklistItems array
param operatorObjectId string
param roles object
param managedBy string

// CAF name from config.json (Cloud Adoption Framework naming guidance, https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming); globally unique, checked with checkDomainAvailability.
var foundryName = names.foundryAccount
var tags = { managedBy: managedBy, lesson: '11' }

// Resource logs for the Foundry resource land here, and gateway.bicep sends the gateway's there too.
resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: names.workspace
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

// ServiceHub's Foundry resource. disableLocalAuth refuses every key, so the only way in is a
// Microsoft Entra token, and only identities with a data role on this resource can get an answer.
resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: foundryName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: { name: 'S0' }
  identity: { type: 'SystemAssigned' }
  properties: {
    customSubDomainName: foundryName
    allowProjectManagement: true
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

// The Foundry resource takes one child operation at a time; running the project beside the
// blocklist returned "Another operation is in progress" on 2026-09-28. So the project waits for
// the guardrail module, which itself waits for the blocklist.
resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: foundry
  name: names.project
  location: location
  dependsOn: [ guardrail ]
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    displayName: 'Contoso ServiceHub'
    description: 'SC-500 Lesson 11: ServiceHub assistant, its model deployment, and its guardrail.'
  }
}

// A regex blocklist for Contoso customer account IDs, so the assistant never takes one in or
// hands one out. The IDs are fictional: CTSO-CUST- followed by six digits.
resource blocklist 'Microsoft.CognitiveServices/accounts/raiBlocklists@2026-07-01' = {
  parent: foundry
  name: names.blocklist
  properties: {
    description: 'Contoso customer account IDs (fictional format CTSO-CUST-000000). SC-500 Lesson 11.'
  }
}

resource blocklistItem 'Microsoft.CognitiveServices/accounts/raiBlocklists/raiBlocklistItems@2026-07-01' = [for item in blocklistItems: {
  parent: blocklist
  name: item.name
  properties: {
    pattern: item.pattern
    isRegex: item.isRegex
  }
}]

// The guardrail and the model deployment are a nested module so ARM preflight sees the blocklist
// first; guardrail.bicep explains why.
module guardrail 'guardrail.bicep' = {
  name: 'sc500-lesson11-guardrail'
  dependsOn: [ blocklistItem ]
  params: {
    foundryName: foundry.name
    names: names
    model: model
  }
}
// Defender for AI Services is on for the subscription, but this resource's own setting was
// created as Disabled on 2026-09-28 and no AI alert arrived for its blocked jailbreaks. Setting it
// here keeps threat protection on for the lab resource without touching the subscription plan.
// It's a child operation, so it waits for the project like everything else on this resource.
resource defenderForAI 'Microsoft.CognitiveServices/accounts/defenderForAISettings@2025-06-01' = {
  parent: foundry
  name: 'Default'
  dependsOn: [ project ]
  properties: { state: 'Enabled' }
}

resource foundryDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-${names.workspace}'
  scope: foundry
  properties: {
    workspaceId: law.id
    logs: [ { categoryGroup: 'allLogs', enabled: true } ]
    metrics: [ { category: 'AllMetrics', enabled: true } ]
  }
}

// You build and call the agent, so you need a data role on the project. Foundry User is the
// least privileged built-in role that can create agents and call the project's models.
resource operatorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(project.id, operatorObjectId, roles.foundryUser)
  scope: project
  properties: {
    principalId: operatorObjectId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.foundryUser)
  }
}

output lab object = {
  resourceGroup: resourceGroup().name
  foundry: foundry.name
  foundryId: foundry.id
  openAiEndpoint: 'https://${foundryName}.openai.azure.com/'
  projectEndpoint: 'https://${foundryName}.services.ai.azure.com/api/projects/${names.project}'
  project: project.name
  projectPrincipalId: project.identity.principalId
  deployment: guardrail.outputs.deployment
  guardrail: guardrail.outputs.guardrail
  blocklist: blocklist.name
  workspace: law.name
  workspaceId: law.id
  workspaceCustomerId: law.properties.customerId
}
