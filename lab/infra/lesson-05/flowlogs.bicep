// Virtual network flow logs for the Lesson 5 hub and spoke, with traffic analytics.
//
// Flow logs are child resources of the regional Network Watcher, which Azure keeps in the
// shared NetworkWatcherRG, so this module deploys there. VNet flow logs replace NSG flow
// logs: new NSG flow logs can't be created after June 30, 2025, and NSG flow logs retire on
// September 30, 2027. VNet flow logs also record AVNM security admin rule decisions, which
// demo 5.2 depends on.

param location string
param tags object
param networkWatcherName string
param vnets array
param storageId string
param workspaceId string
param workspaceCustomerId string

resource watcher 'Microsoft.Network/networkWatchers@2024-05-01' existing = {
  name: networkWatcherName
}

// One at a time: creating both flow logs concurrently returned InternalServerError on
// 2026-09-26, and a serial retry succeeded.
@batchSize(1)
resource flowLogs 'Microsoft.Network/networkWatchers/flowLogs@2024-05-01' = [for v in vnets: {
  parent: watcher
  name: 'fl-${v.name}'
  location: location
  tags: tags
  properties: {
    targetResourceId: v.id
    storageId: storageId
    enabled: true
    format: { type: 'JSON', version: 2 }
    retentionPolicy: { days: 7, enabled: true }
    flowAnalyticsConfiguration: {
      networkWatcherFlowAnalyticsConfiguration: {
        enabled: true
        workspaceResourceId: workspaceId
        workspaceId: workspaceCustomerId
        workspaceRegion: location
        // Ten minutes is the faster traffic analytics interval; the default is sixty.
        trafficAnalyticsInterval: 10
      }
    }
  }
}]
