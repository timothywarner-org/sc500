// The capacity reaper: a Consumption logic app with a system-assigned managed identity.
//
// Every recurrenceMinutes it lists targetResourceType in this resource group (with createdTime),
// and deletes each one whose deadline has passed. The deadline is the expiryTag value when the tag
// is present, otherwise createdTime plus defaultMaxHours. The workflow text lives in
// reaper-workflow.json so it can be read and diffed as plain JSON; this file only fills its tokens.
param location string
param tags object
param name string
param roleDefinitionId string
param targetResourceType string
param targetApiVersion string
param expiryTag string
param defaultMaxHours int
param recurrenceMinutes int

// $expand=createdTime makes ARM return each resource's creation time, which the untagged rule needs.
var listUri = '${environment().resourceManager}subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/resources?api-version=2021-04-01&$filter=resourceType%20eq%20%27${targetResourceType}%27&$expand=createdTime'

var definition = json(replace(replace(replace(replace(replace(loadTextContent('reaper-workflow.json'),
  '__LIST_URI__', listUri),
  '__API_VERSION__', targetApiVersion),
  '__EXPIRY_TAG__', expiryTag),
  '__MAX_HOURS__', string(defaultMaxHours)),
  '__RECURRENCE__', string(recurrenceMinutes)))

resource reaper 'Microsoft.Logic/workflows@2019-05-01' = {
  name: name
  location: location
  tags: union(tags, { purpose: 'deletes the security copilot capacity after its expiry' })
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: definition
    parameters: {}
  }
}

// The custom role is assignable only in this group, so this is the widest scope it can ever have.
resource reaperAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, reaper.id, roleDefinitionId)
  properties: {
    principalId: reaper.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleDefinitionId
    description: 'Contoso Security Copilot capacity reaper'
  }
}

output reaperId string = reaper.id
output principalId string = reaper.identity.principalId
