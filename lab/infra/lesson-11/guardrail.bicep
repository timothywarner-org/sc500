// SC-500 Lesson 11: the guardrail and the model deployment that carries it.
// This is a separate module on purpose. ARM preflight checks that every blocklist a guardrail
// names already exists, and a nested deployment's preflight runs only after the parent has
// created the blocklist. Put the guardrail in foundry.bicep and preflight rejects it with
// "One or more of blocklists referenced in this policy are invalid" (seen 2026-09-28).

param foundryName string
param names object
param model object

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryName
}

// Harm categories block at Medium on input and output. Prompt Shields block user prompt attacks
// on input and indirect attacks on input and on tool responses (PostToolCall, the agent's tool
// response intervention point). Protected material for code only annotates, so the lesson can
// contrast annotate with annotate-and-block. The blocklist blocks in both directions.
var harms = [ 'Hate', 'Sexual', 'Selfharm', 'Violence' ]
var harmFilters = [for h in harms: [
  { name: h, enabled: true, blocking: true, severityThreshold: 'Medium', source: 'Prompt' }
  { name: h, enabled: true, blocking: true, severityThreshold: 'Medium', source: 'Completion' }
]]

resource guardrail 'Microsoft.CognitiveServices/accounts/raiPolicies@2026-07-01' = {
  parent: foundry
  name: names.guardrail
  properties: {
    basePolicyName: 'Microsoft.DefaultV2'
    mode: 'Default'
    contentFilters: concat(flatten(harmFilters), [
      { name: 'Jailbreak', enabled: true, blocking: true, source: 'Prompt' }
      { name: 'Indirect Attack', enabled: true, blocking: true, source: 'Prompt' }
      { name: 'Indirect Attack', enabled: true, blocking: true, source: 'PostToolCall' }
      { name: 'Protected Material Text', enabled: true, blocking: true, source: 'Completion' }
      { name: 'Protected Material Code', enabled: true, blocking: false, source: 'Completion' }
    ])
    customBlocklists: [
      { blocklistName: names.blocklist, blocking: true, source: 'Prompt' }
      { blocklistName: names.blocklist, blocking: true, source: 'Completion' }
    ]
  }
}

// One pay-per-token deployment. raiPolicyName attaches the guardrail; an agent built on this
// deployment inherits it unless the agent is given a guardrail of its own.
resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: foundry
  name: names.modelDeployment
  dependsOn: [ guardrail ]
  sku: { name: model.sku, capacity: model.capacityThousandTpm }
  properties: {
    model: { format: 'OpenAI', name: model.name, version: model.version }
    raiPolicyName: names.guardrail
    versionUpgradeOption: 'NoAutoUpgrade'
  }
}

output guardrail string = guardrail.name
output deployment string = deployment.name
