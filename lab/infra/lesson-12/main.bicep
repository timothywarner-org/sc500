// SC-500 Lesson 12 lab (subscription scope). Two resource groups, both retained through Lesson 14:
//   rg-servicehub-prod-eastus2 (eastus2): ServiceHub's parts-export store, the fixture that demo 12.1
//     remediates and demo 12.2 configures, plus the archive store that carries the same finding with
//     public network access disabled. Both start with Shared Key authorization allowed, the
//     configuration drift Defender for Cloud should flag, so one recommendation shows two risk levels.
//   rg-attacksurface-shared-eastus (eastus): the Defender EASM workspace for the outside-in demo.
//     Defender EASM runs in a short list of regions, and eastus2 isn't one of them, so it gets its own group.
// Names follow Cloud Adoption Framework naming guidance, https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming (CAF applied to Contoso); the course and lesson live in tags.
// Nothing here changes a Defender plan: Set-L12DefenderWindow.ps1 owns the subscription plans.
// Deploy-L12Lab.ps1 supplies every parameter from infra/lesson-12/config.json.
targetScope = 'subscription'

@description('Region for the posture fixture group and its stores.')
param location string
@description('Region for the Defender EASM workspace (EASM supports a short list of regions).')
param easmLocation string
param resourceGroupName string
param easmResourceGroupName string
@description('names object from config.json: exportStorage, archiveStorage, container, easmWorkspace, ...')
param names object
@description('Object ID of the operator (you), who gets Storage Blob Data Owner on the export store only.')
param operatorObjectId string
param roles object
@description('CAF tag set from config.json; every taggable resource carries it.')
param tags object
param baseline string

// The baseline name rides along as a tag so Reset and Test can say which state they restore.
var allTags = union(tags, { baseline: baseline })
// The EASM group serves the whole company's external footprint, so its env and region tags differ.
var easmTags = union(allTags, { env: 'shared', region: easmLocation, workload: 'attacksurface' })

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: allTags
}

resource easmRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: easmResourceGroupName
  location: easmLocation
  tags: easmTags
}

module posture 'posture.bicep' = {
  name: 'sc500-lesson12-posture'
  scope: rg
  params: {
    location: location
    names: names
    operatorObjectId: operatorObjectId
    roles: roles
    tags: allTags
  }
}

module easm 'easm.bicep' = {
  name: 'sc500-lesson12-easm'
  scope: easmRg
  params: {
    location: easmLocation
    workspaceName: names.easmWorkspace
    tags: easmTags
  }
}

output lab object = union(posture.outputs.lab, easm.outputs.lab)
