// Temporary outbound path for the Lesson 13 collectors. The subnet has no default outbound access,
// and the Azure Monitor Agent must reach Azure Monitor, so a NAT gateway exists only while the VMs
// run. Start-L13Lab.ps1 creates it and Stop-L13Lab.ps1 deletes it; the tags are checked before deletion.
targetScope = 'resourceGroup'
param location string
param names object
param tags object
var egressTags = union(tags, { lifecycle: 'rehearsal-only' })

resource ip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: names.natIp
  location: location
  tags: egressTags
  sku: { name: 'Standard', tier: 'Regional' }
  properties: { publicIPAllocationMethod: 'Static', publicIPAddressVersion: 'IPv4' }
}

resource nat 'Microsoft.Network/natGateways@2024-05-01' = {
  name: names.nat
  location: location
  tags: egressTags
  sku: { name: 'Standard' }
  properties: { idleTimeoutInMinutes: 4, publicIpAddresses: [ { id: ip.id } ] }
}

output natId string = nat.id
