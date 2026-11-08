// Provision outbound connectivity before Linux boots so Defender's first install can finish.
// This lab convenience adds no inbound path; remove it after deallocating retained guests.
param location string
param tags object
@description('The Contoso workload whose subnet uses this NAT gateway, for example servicehub.')
param workload string
@description('CAF naming components from config.json naming: env, region, instance.')
param naming object
var natName = 'ng-${workload}-${naming.env}-${naming.region}-${naming.instance}'
var maintenanceTags = union(tags, { purpose: 'lesson06-maintenance-egress' })
resource pip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-${natName}'
  location: location
  tags: maintenanceTags
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static', publicIPAddressVersion: 'IPv4' }
}
resource nat 'Microsoft.Network/natGateways@2024-05-01' = {
  name: natName
  location: location
  tags: maintenanceTags
  sku: { name: 'Standard' }
  properties: { idleTimeoutInMinutes: 4, publicIpAddresses: [{ id: pip.id }] }
}
output id string = nat.id
