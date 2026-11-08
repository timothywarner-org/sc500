// SC-500 Lesson 9 retained baseline (CTSO-L09-BASELINE): Contoso ServiceHub's application platform.
//
// Subscription scope, so one deployment creates the resource group, its budget and everything in
// it, and the what-if shows the whole change. Names come from infra/lesson-09/config.json (one
// source of names, Cloud Adoption Framework naming guidance, https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming); docs/CONTOSO-AZURE-DEPLOYMENT.md says what every
// lab template carries. Deploy-L09Lab.ps1 supplies every parameter and runs the preflight,
// validation and what-if first. The public edge is bounded: edge.bicep, through Deploy-L09Edge.ps1.
targetScope = 'subscription'

@description('Azure region for every retained resource, from config.json.')
param location string

@description('Azure region for the AKS cluster, from config.json (eastus2 since November 1, 2026).')
param aksLocation string

@description('Resource group name, from config.json: rg-{workload}-{env}-{region}.')
@minLength(1)
@maxLength(90)
param resourceGroupName string

@description('Every resource name, from config.json.')
param names object

@description('Address plan, from config.json.')
param addressPlan object

@description('AKS node size, from config.json. The deploy script checks restrictions and quota.')
param aksNodeSize string

@description('Operator workstation public IPv4, for allow lists. Never shown on slides.')
param operatorIp string

@description('Object ID of the operator (you), for the AKS data-plane role.')
param operatorObjectId string

@description('Microsoft Entra tenant ID, from config.json.')
param tenantId string

@description('Application (client) ID of the lab API app registration.')
param apiAppId string

@description('The lab API\'s delegated scope, from config.json.')
param apiScope string

@description('Built-in policy definition GUIDs, from config.json.')
param policyDefinitions object

@description('API Management rate limit: calls per period, from config.json.')
param rateLimitCalls int

@description('API Management rate limit period in seconds, from config.json.')
param rateLimitPeriodSeconds int

@description('False on the first pass, before the images exist; true afterward.')
param deployApps bool

@description('Common tags from config.json. Every resource gets them, plus its own workload and env.')
param tags object

@description('Budget settings from config.json.')
param budget object

@description('First day of the current month. A budget must start on the first of a month.')
param budgetStartDate string = utcNow('yyyy-MM-01')

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: union(tags, { workload: 'appplatform', env: 'prod' })
}

module retained 'retained.bicep' = {
  name: 'contoso-appplatform-retained-rg'
  scope: rg
  params: {
    location: location
    aksLocation: aksLocation
    names: names
    addressPlan: addressPlan
    aksNodeSize: aksNodeSize
    operatorIp: operatorIp
    operatorObjectId: operatorObjectId
    tenantId: tenantId
    apiAppId: apiAppId
    apiScope: apiScope
    policyDefinitions: policyDefinitions
    rateLimitCalls: rateLimitCalls
    rateLimitPeriodSeconds: rateLimitPeriodSeconds
    deployApps: deployApps
    tags: tags
  }
}

module groupBudget 'budget.bicep' = if (budget.enabled) {
  scope: rg
  name: 'contoso-appplatform-budget'
  params: {
    name: names.budget
    amount: budget.monthlyAmountUsd
    startDate: budgetStartDate
    actualThresholds: budget.actualThresholds
    forecastThreshold: budget.forecastThreshold
    contactRoles: budget.contactRoles
  }
}

@description('Resource IDs, names and endpoints the lesson scripts read back from the deployment record.')
output lab object = retained.outputs.lab
