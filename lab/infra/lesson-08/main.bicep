// SC-500 Lesson 8 retained baseline (CTSO-L08-BASELINE): Contoso's servers.
//
// Subscription scope, so one deployment creates the resource group, its budget and everything in
// it, and the what-if shows the whole change. Names come from infra/lesson-08/config.json (one
// source of names, Cloud Adoption Framework naming guidance, https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming); docs/CONTOSO-AZURE-DEPLOYMENT.md says what every
// lab template carries. Deploy-L08Lab.ps1 supplies every parameter and runs the preflight,
// validation and what-if first. The legacy app server is bounded: legacy.bicep, through
// Deploy-L08Bounded.ps1.
targetScope = 'subscription'

@description('Azure region for every resource, from config.json.')
param location string

@description('Resource group name, from config.json: rg-{workload}-{env}-{region}.')
@minLength(1)
@maxLength(90)
param resourceGroupName string

@description('Every resource name, from config.json.')
param names object

@description('Address plan, from config.json.')
param addressPlan object

@description('VM sizes by role, from config.json. The deploy script checks restrictions and quota.')
param vmSizes object

@description('Lab admin user name on the Linux servers, from config.json.')
param adminUsername string

@description('Public half of the lab admin key. The private half stays on your workstation, outside the repo and OneDrive.')
param sshPublicKey string

@description('Pinned Ubuntu image version, so a redeploy never changes the OS disk image.')
param imageVersion string

@description('Base64 cloud-init for the ServiceHub app server.')
param appCustomData string

@description('Base64 cloud-init for the field office server (the Arc evaluation preparation).')
param onpremCustomData string

@description('Built-in policy definition GUIDs, from config.json.')
param policyDefinitions object

@description('Common tags from config.json. Every resource gets them, plus its own workload and env.')
param tags object

@description('Budget settings from config.json.')
param budget object

@description('Auto-shutdown settings from config.json (enabled is false during a pre-demo soak).')
param autoShutdown object

@description('First day of the current month. A budget must start on the first of a month.')
param budgetStartDate string = utcNow('yyyy-MM-01')

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: union(tags, { workload: 'servers', env: 'prod' })
}

module retained 'retained.bicep' = {
  name: 'contoso-servers-retained-rg'
  scope: rg
  params: {
    location: location
    names: names
    addressPlan: addressPlan
    vmSizes: vmSizes
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    imageVersion: imageVersion
    appCustomData: appCustomData
    onpremCustomData: onpremCustomData
    policyDefinitions: policyDefinitions
    tags: tags
    autoShutdown: autoShutdown
  }
}

module groupBudget 'budget.bicep' = if (budget.enabled) {
  scope: rg
  name: 'contoso-servers-budget'
  params: {
    name: names.budget
    amount: budget.monthlyAmountUsd
    startDate: budgetStartDate
    actualThresholds: budget.actualThresholds
    forecastThreshold: budget.forecastThreshold
    contactRoles: budget.contactRoles
  }
}

@description('Resource IDs, names and addresses the lesson scripts read back from the deployment record.')
output lab object = retained.outputs.lab
