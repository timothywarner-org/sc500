// SC-500 Lesson 13 lab (subscription scope). One resource group, retained through Lesson 14:
//   rg-secops-shared-eastus2 (eastus2): the Log Analytics workspace with Microsoft Sentinel enabled,
//     the data collection rules for every ingestion route in demo 13.3 and 13.4, the ServiceHubAudit_CL
//     custom table, a Linux log forwarder and a Windows event collector (both private, deallocated at
//     idle), and your data role on the ServiceHub DCR.
// It also sends the subscription's Activity log to that workspace (demo 13.2's Azure resources route).
// Nothing here is tenant scoped: Microsoft Entra, Microsoft 365, Defender XDR, and the Defender portal
// connection are your steps. Deploy-L13Lab.ps1 supplies every parameter.
targetScope = 'subscription'

param location string
param resourceGroupName string
param names object
param workspace object
param customTable object
param collection object
param vm object
param operatorObjectId string
param roles object
@description('The CAF tag set from config.json (lowercase keys). Every resource carries it.')
param tags object
param baseline string
param linuxPublicKey string
@secure()
param windowsAdminPassword string
@description('False when both VMs already exist: a VM\'s admin credentials can\'t change after creation, and Deploy-L13Lab.ps1 generates new ones every run.')
param deployHosts bool = true

// The baseline label rides with the CAF set so a readback can tell this build from a September one.
var labTags = union(tags, { baseline: baseline })

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: labTags
}

module sentinel 'sentinel.bicep' = {
  name: 'sc500-lesson13-sentinel'
  scope: rg
  params: {
    location: location
    names: names
    workspace: workspace
    customTable: customTable
    collection: collection
    operatorObjectId: operatorObjectId
    roles: roles
    tags: labTags
  }
}

module hosts 'hosts.bicep' = if (deployHosts) {
  name: 'sc500-lesson13-hosts'
  scope: rg
  params: {
    location: location
    names: names
    vm: vm
    tags: labTags
    linuxPublicKey: linuxPublicKey
    windowsAdminPassword: windowsAdminPassword
    dcrs: sentinel.outputs.dcrs
  }
}

// Azure resources route: the subscription's Activity log goes to the lesson workspace. Sentinel's
// Azure Activity connector does the same thing through an Azure Policy assignment; for one
// subscription, a direct diagnostic setting is the smaller change. AzureActivity ingestion is free.
resource activity 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: names.activityDiagnosticSetting
  properties: {
    workspaceId: sentinel.outputs.lab.workspaceId
    logs: [
      { category: 'Administrative', enabled: true }
      { category: 'Security', enabled: true }
      { category: 'Policy', enabled: true }
      { category: 'Alert', enabled: true }
    ]
  }
}

output lab object = union(sentinel.outputs.lab, deployHosts ? hosts!.outputs.lab : {}, { activityDiagnosticSetting: activity.name })
