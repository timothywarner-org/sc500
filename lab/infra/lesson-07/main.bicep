// SC-500 Lesson 7 retained baseline (CTSO-L07-BASELINE): Contoso's perimeter hub and the two
// ServiceHub spokes it protects.
//
// Subscription scope, so one deployment creates the resource group, its budget, and everything in
// it, and the what-if shows the whole change. Names come from infra/lesson-07/config.json (one
// source of names, Cloud Adoption Framework naming guidance, https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming). The firewall policy deploys next with
// policy.bicep (it needs the inspection CA imported into Key Vault first), and the firewall itself
// is bounded: firewall.bicep, through Deploy-L07Bounded.ps1.
//
// Why one resource group: Azure Firewall must sit in the same resource group as its virtual
// network, and the lab is created and removed as one unit. Slide 19 says the production design
// separates environments by subscription; the lab says so out loud instead of pretending.
targetScope = 'subscription'

@description('Azure region for every resource, from config.json.')
param location string

@description('Resource group name, from config.json: rg-{workload}-{env}-{region}.')
@minLength(1)
@maxLength(90)
param resourceGroupName string

@description('Object ID of the operator (you) who imports the inspection CA into Key Vault.')
param operatorObjectId string

@description('The operator\'s current public IPv4 address. The Key Vault firewall admits it for the CA import.')
param operatorPublicIp string

@description('SSH public key for the Linux VMs. Nobody signs in; the private half is never saved.')
param sshPublicKey string

@description('Pinned Ubuntu image version, so a redeploy never changes the OS disk image.')
param imageVersion string

@description('VM size, checked against SKU restrictions and quota by the deploy script.')
param vmSize string

@description('Every resource name, from config.json.')
param names object

@description('Address plan, from config.json.')
param addressPlan object

@description('Listener ports, from config.json.')
param ports object

@description('Probe targets, from config.json.')
param tests object

@description('Base64 of the lab root CA public certificate (PEM). Public data.')
param rootCaB64 string

@description('Base64 of the inspection CA public certificate (PEM). Public data.')
param interCaB64 string

@description('Role definition ID (GUID) of Key Vault Secrets User, resolved by the deploy script.')
#disable-next-line secure-secrets-in-params // A role definition GUID, public data; the rule matches 'Secrets' in the role's name.
param keyVaultSecretsUserRoleId string

@description('Role definition ID (GUID) of Key Vault Certificates Officer, resolved by the deploy script.')
param keyVaultCertificatesOfficerRoleId string

@description('Common tags from config.json. Every resource gets them, plus its own workload and env.')
param tags object

@description('Budget settings from config.json.')
param budget object

@description('Auto-shutdown settings from config.json.')
param autoShutdown object

@description('First day of the current month. A budget must start on the first of a month.')
param budgetStartDate string = utcNow('yyyy-MM-01')

// The group serves both environments, so its own tags say shared.
var groupTags = union(tags, { workload: 'perimeter', env: 'shared' })

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: groupTags
}

module retained 'retained.bicep' = {
  scope: rg
  name: 'contoso-perimeter-retained-rg'
  params: {
    location: location
    tags: tags
    operatorObjectId: operatorObjectId
    operatorPublicIp: operatorPublicIp
    sshPublicKey: sshPublicKey
    imageVersion: imageVersion
    vmSize: vmSize
    names: names
    addressPlan: addressPlan
    ports: ports
    tests: tests
    rootCaB64: rootCaB64
    interCaB64: interCaB64
    keyVaultSecretsUserRoleId: keyVaultSecretsUserRoleId
    keyVaultCertificatesOfficerRoleId: keyVaultCertificatesOfficerRoleId
    autoShutdown: autoShutdown
  }
}

module groupBudget 'budget.bicep' = if (budget.enabled) {
  scope: rg
  name: 'contoso-perimeter-budget'
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
