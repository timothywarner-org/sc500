// SC-500 Lesson 15: the cost guardrail around a Microsoft Security Copilot capacity.
//
// What this deploys, and why only this:
//   * rg-secopscopilot-shared-eastus2, the one resource group you pick when you create the Security Copilot
//     capacity yourself (first-run choices such as data sharing and audit logging are tenant
//     settings, so no script makes them).
//   * A custom role that can list the group's resources and read and delete one resource type,
//     assignable only in that group.
//   * The capacity reaper (reaper.bicep): a Consumption logic app that deletes the capacity when its
//     expiry passes. Provisioned Security Compute Units bill every hour a capacity exists, whether
//     or not anyone uses it, so the lab never relies on someone remembering to delete it.
//
// The capacity itself is never in this template: Microsoft documents creating it in the Security
// Copilot portal or the Azure portal, and Lesson 15 teaches that flow.
//
// Why subscription scope: the resource group and the custom role definition are subscription-level
// resources; the logic app and its role assignment deploy into the group through a module.
targetScope = 'subscription'

@description('Region for the resource group and the reaper logic app.')
param location string

@description('The guarded resource group. The capacity goes here.')
param resourceGroupName string

@description('The CAF tag set from config.json; managedby is the value Remove-L15Lab.ps1 checks before deleting anything.')
param tags object

@description('Baseline tag value for the lab.')
param baseline string

@description('Name of the reaper logic app.')
param reaperName string

@description('Display name prefix of the reaper\'s custom role; the resource type is appended so a test deployment gets its own role.')
param roleName string

@description('Resource type the reaper may delete. Microsoft.SecurityCopilot/capacities for the lab; a free stand-in type for the reaper\'s own live test.')
param targetResourceType string

@description('ARM API version the reaper uses to delete the target type.')
param targetApiVersion string

@description('Tag holding an ISO 8601 UTC expiry time, written by Start-L15CopilotSession.ps1.')
param expiryTag string

@description('Hours after creation when an untagged target is deleted. Zero is allowed only for the reaper test.')
@minValue(0)
@maxValue(8)
param defaultMaxHours int

@description('Minutes between reaper runs.')
@minValue(5)
@maxValue(60)
param recurrenceMinutes int

var allTags = union(tags, {
  baseline: baseline
})

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: allTags
}

// Least privilege: list the group's resources (to find targets), read and delete the one type.
// Nothing else in the subscription, and no other resource type in the group.
resource reaperRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(subscription().id, roleName, targetResourceType, resourceGroupName)
  properties: {
    roleName: '${roleName} (${targetResourceType}, ${resourceGroupName})'
    description: 'Lists resources in ${resourceGroupName} and reads or deletes ${targetResourceType} there. Used only by the Contoso Security Copilot capacity reaper.'
    type: 'CustomRole'
    permissions: [
      {
        actions: [
          'Microsoft.Resources/subscriptions/resourceGroups/resources/read'
          '${targetResourceType}/read'
          '${targetResourceType}/delete'
        ]
        notActions: []
      }
    ]
    assignableScopes: [
      rg.id
    ]
  }
}

module reaper 'reaper.bicep' = {
  scope: rg
  name: 'l15-reaper'
  params: {
    location: location
    tags: allTags
    name: reaperName
    roleDefinitionId: reaperRole.id
    targetResourceType: targetResourceType
    targetApiVersion: targetApiVersion
    expiryTag: expiryTag
    defaultMaxHours: defaultMaxHours
    recurrenceMinutes: recurrenceMinutes
  }
}

output lab object = {
  resourceGroup: rg.name
  resourceGroupId: rg.id
  reaperId: reaper.outputs.reaperId
  reaperName: reaperName
  reaperPrincipalId: reaper.outputs.principalId
  roleDefinitionId: reaperRole.id
  targetResourceType: targetResourceType
  expiryTag: expiryTag
  defaultMaxHours: defaultMaxHours
  recurrenceMinutes: recurrenceMinutes
}
