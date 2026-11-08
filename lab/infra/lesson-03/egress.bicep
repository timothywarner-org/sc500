@description('Lab region.')
param location string = 'eastus2'
var tags = { course: 'SC500', lesson: '03', managedBy: 'sc500-l03-iac', lifecycle: 'rehearsal-only' }
// Start recreates only the costly egress resources removed after each session.
resource ip 'Microsoft.Network/publicIPAddresses@2025-09-01' = {
  name: 'pip-sc500-l03-egress'
  location: location
  tags: tags
  sku: { name: 'Standard', tier: 'Regional' }
  properties: { publicIPAllocationMethod: 'Static', publicIPAddressVersion: 'IPv4' }
}
resource nat 'Microsoft.Network/natGateways@2025-09-01' = {
  name: 'nat-sc500-l03-egress'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: { idleTimeoutInMinutes: 4, publicIpAddresses: [{ id: ip.id }] }
}
output natId string = nat.id
