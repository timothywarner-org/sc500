// SC-500 Lesson 11 lab, retained half (subscription scope): the resource group and ServiceHub's
// Foundry implementation. Everything here bills per token or per GB, so it costs nothing idle:
//   - a Log Analytics workspace for the gateway and Foundry resource logs
//   - a Foundry resource with key authentication disabled, and the ServiceHub project
//   - a custom blocklist and a custom guardrail (RAI policy) that uses it
//   - one GlobalStandard model deployment that carries the guardrail
//   - the operator's Foundry User role on the project, so you can build and call the agent
// The gateway (API Management Basic v2) bills by the hour, so it lives in gateway.bicep and is
// deployed only while you work through the demo. Deploy-L11Lab.ps1 supplies every parameter.
targetScope = 'subscription'

param location string
param resourceGroupName string
param names object
param model object
param blocklistItems array
param operatorObjectId string
param roles object
param managedBy string
param baseline string

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: { managedBy: managedBy, lesson: '11', baseline: baseline, workload: 'servicehubai', env: 'prod', region: location, criticality: 'low', dataclass: 'synthetic', costcenter: 'sc500-video-course', scenario: 'Contoso ServiceHub' }
}

module foundry 'foundry.bicep' = {
  name: 'sc500-lesson11-foundry'
  scope: rg
  params: {
    location: location
    names: names
    model: model
    blocklistItems: blocklistItems
    operatorObjectId: operatorObjectId
    roles: roles
    managedBy: managedBy
  }
}

output lab object = foundry.outputs.lab
