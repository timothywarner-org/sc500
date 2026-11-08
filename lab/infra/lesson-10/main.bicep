// SC-500 Lesson 10 lab: the Azure half. Subscription scope, so one deployment creates the
// resource group and everything in it. The directory half (the agent identity blueprint, two
// agent identities, and two report-only Conditional Access policies) is created through
// Microsoft Graph by Deploy-L10Lab.ps1, because Bicep can't create Entra objects. The deploy
// script passes the agent identities' object IDs in, so the role assignments here grant access
// to identities that already exist.
targetScope = 'subscription'

@description('Region for the resource group and the storage account.')
param location string

@description('Resource group name.')
param resourceGroupName string

@description('Storage account name (CAF, Contoso).')
param storageName string

@description('Blob containers: the assistant\'s knowledge, a finance container it should never see, and the triage agent\'s tickets.')
param containers array

@description('Object ID of the ServiceHub Assistant agent identity.')
param assistantPrincipalId string

@description('Object ID of the ServiceHub Triage Agent agent identity.')
param triagePrincipalId string

@description('Object ID of the operator, who uploads the fixture files with a Microsoft Entra token.')
param operatorObjectId string

@description('Built-in role IDs.')
param roles object

param managedBy string
param baseline string

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: { managedBy: managedBy, lesson: '10', baseline: baseline }
}

module lab 'storage.bicep' = {
  name: 'sc500-lesson10-storage'
  scope: rg
  params: {
    location: location
    storageName: storageName
    containers: containers
    assistantPrincipalId: assistantPrincipalId
    triagePrincipalId: triagePrincipalId
    operatorObjectId: operatorObjectId
    roles: roles
    managedBy: managedBy
  }
}

output lab object = lab.outputs.lab
