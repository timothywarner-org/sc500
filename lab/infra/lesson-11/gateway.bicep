// SC-500 Lesson 11 bounded half (resource group scope): the AI gateway. API Management Basic v2
// bills by the hour, so Deploy-L11Lab.ps1 -Gateway creates it while you work through the demo and
// Reset-L11Lab.ps1 removes it and purges the soft-deleted instance afterward.
//
// What it builds, and why:
//   - Basic v2, the tier Foundry's own "Create new" AI Gateway option provisions. A v2 tier is
//     required for Foundry's "Use existing" option, and llm-token-limit doesn't run on Consumption.
//   - A system-assigned identity with Cognitive Services OpenAI User on the Foundry resource. It's
//     the backend identity for this route. You retain data access for the direct-call comparison;
//     this template does not force every Foundry or agent request through the gateway.
//   - The servicehub-ai API: POST /deployments/{deployment-id}/chat/completions, forwarded to the
//     Foundry resource with the managed identity and a tokens-per-minute budget (llm-api.xml).
//   - The servicehub-assistant product and subscription. Its key is the caller's credential.
//   - The servicehub-parts API: a synthetic, anonymous parts lookup the agent's OpenAPI tool calls
//     (parts-mock.xml). One part returns a planted indirect prompt injection.
//   - Gateway logs and LLM logs (token counts, prompts, completions) to the lesson's workspace,
//     in the resource-specific tables ApiManagementGatewayLogs and ApiManagementGatewayLlmLog.

param location string
param names object
param gateway object
param foundryName string
param workspaceId string
param publisherEmail string
param roles object
param managedBy string

var apimName = names.apimName // CAF name from config.json; globally unique
var tags = { managedBy: managedBy, lesson: '11', lifecycle: 'bounded' }
var llmPolicy = replace(replace(loadTextContent('policies/llm-api.xml'), '__TPM__', string(gateway.tokensPerMinute)), '__REMAINING_HEADER__', gateway.remainingTokensHeader)

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryName
}

resource apim 'Microsoft.ApiManagement/service@2024-10-01-preview' = {
  name: apimName
  location: location
  tags: tags
  sku: { name: gateway.sku, capacity: 1 }
  identity: { type: 'SystemAssigned' }
  properties: {
    publisherEmail: publisherEmail
    publisherName: 'Contoso, Ltd. (SC-500 lab)'
  }
}

// Recreating a system-assigned identity changes its principal. A nested deployment makes that
// principal available when the role's name is computed, rather than reusing an immutable old role.
module gatewayRole 'gateway-role.bicep' = {
  name: 'gateway-backend-role'
  params: {
    foundryName: foundry.name
    principalId: apim.identity.principalId
    roleId: roles.openAiUser
  }
}

resource backend 'Microsoft.ApiManagement/service/backends@2024-10-01-preview' = {
  parent: apim
  name: 'foundry-openai'
  properties: {
    description: 'ServiceHub Foundry resource, Azure OpenAI surface'
    url: 'https://${foundryName}.openai.azure.com/openai'
    protocol: 'http'
  }
}

resource llmApi 'Microsoft.ApiManagement/service/apis@2024-10-01-preview' = {
  parent: apim
  name: 'servicehub-ai'
  properties: {
    displayName: 'ServiceHub AI (Foundry models)'
    path: names.llmApiPath
    protocols: [ 'https' ]
    subscriptionRequired: true
    subscriptionKeyParameterNames: { header: 'api-key', query: 'subscription-key' }
    serviceUrl: 'https://${foundryName}.openai.azure.com/openai'
  }
}

resource chatOp 'Microsoft.ApiManagement/service/apis/operations@2024-10-01-preview' = {
  parent: llmApi
  name: 'chat-completions'
  properties: {
    displayName: 'Chat completions'
    method: 'POST'
    urlTemplate: '/deployments/{deployment-id}/chat/completions'
    templateParameters: [ { name: 'deployment-id', type: 'string', required: true } ]
  }
}

resource llmPolicyRes 'Microsoft.ApiManagement/service/apis/policies@2024-10-01-preview' = {
  parent: llmApi
  name: 'policy'
  dependsOn: [ backend ]
  properties: { format: 'rawxml', value: llmPolicy }
}

resource product 'Microsoft.ApiManagement/service/products@2024-10-01-preview' = {
  parent: apim
  name: names.product
  properties: {
    displayName: 'ServiceHub assistant'
    description: 'The ServiceHub assistant application. Its subscription key is the only caller credential the gateway accepts.'
    subscriptionRequired: true
    approvalRequired: false
    state: 'published'
  }
}

resource productApi 'Microsoft.ApiManagement/service/products/apis@2024-10-01-preview' = {
  parent: product
  name: llmApi.name
}

resource subscription 'Microsoft.ApiManagement/service/subscriptions@2024-10-01-preview' = {
  parent: apim
  name: names.subscription
  properties: {
    displayName: 'ServiceHub assistant (lab)'
    scope: product.id
    state: 'active'
  }
}

resource partsApi 'Microsoft.ApiManagement/service/apis@2024-10-01-preview' = {
  parent: apim
  name: 'servicehub-parts'
  properties: {
    displayName: 'ServiceHub parts lookup (synthetic fixture)'
    path: names.partsApiPath
    protocols: [ 'https' ]
    subscriptionRequired: false
  }
}

resource partsOp 'Microsoft.ApiManagement/service/apis/operations@2024-10-01-preview' = {
  parent: partsApi
  name: 'get-part'
  properties: {
    displayName: 'Get part'
    method: 'GET'
    urlTemplate: '/parts/{partNumber}'
    templateParameters: [ { name: 'partNumber', type: 'string', required: true } ]
  }
}

resource partsPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-10-01-preview' = {
  parent: partsApi
  name: 'policy'
  properties: { format: 'rawxml', value: loadTextContent('policies/parts-mock.xml') }
}

// Azure Monitor logger and the per-API LLM logging switch ("Log LLM messages" in the portal).
resource monitorLogger 'Microsoft.ApiManagement/service/loggers@2024-10-01-preview' = {
  parent: apim
  name: 'azuremonitor'
  properties: { loggerType: 'azureMonitor', isBuffered: true }
}

resource llmApiDiag 'Microsoft.ApiManagement/service/apis/diagnostics@2024-10-01-preview' = {
  parent: llmApi
  name: 'azuremonitor'
  properties: {
    loggerId: monitorLogger.id
    alwaysLog: 'allErrors'
    sampling: { samplingType: 'fixed', percentage: 100 }
    logClientIp: false
    largeLanguageModel: {
      logs: 'enabled'
      requests: { messages: 'all', maxSizeInBytes: 32768 }
      responses: { messages: 'all', maxSizeInBytes: 32768 }
    }
  }
}

resource apimDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-${names.workspace}'
  scope: apim
  properties: {
    workspaceId: workspaceId
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      { category: 'GatewayLogs', enabled: true }
      { category: 'GatewayLlmLogs', enabled: true }
    ]
    metrics: [ { category: 'AllMetrics', enabled: true } ]
  }
}

output gateway object = {
  apim: apim.name
  apimId: apim.id
  gatewayUrl: apim.properties.gatewayUrl
  principalId: apim.identity.principalId
  llmApiPath: names.llmApiPath
  partsApiPath: names.partsApiPath
  subscription: subscription.name
}
