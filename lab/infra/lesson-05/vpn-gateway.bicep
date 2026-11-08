// One route-based VPN gateway (VpnGw1AZ) and its zone-redundant Standard public IP.
// Non-AZ VpnGw1-5 SKUs retire on September 30, 2026, and new gateways need a Standard SKU
// public IP, so the lab uses the AZ SKU from the start. Optional point-to-site settings use
// Microsoft Entra ID, which requires the OpenVPN tunnel type and the Azure VPN Client.

param name string
param location string
param tags object
param gatewaySubnetId string
@description('Empty for no point-to-site configuration.')
param p2sAddressPool string = ''
param tenantId string = ''
@description('Audience for the Microsoft-registered Azure VPN Client app.')
param p2sAudience string = ''
@description('Log Analytics workspace for gateway, tunnel, IKE, and P2S diagnostics. Empty for none.')
param workspaceId string = ''

resource pip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-${name}'
  location: location
  tags: tags
  sku: { name: 'Standard', tier: 'Regional' }
  zones: ['1', '2', '3']
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

var p2s = empty(p2sAddressPool) ? null : {
  vpnClientAddressPool: { addressPrefixes: [p2sAddressPool] }
  vpnClientProtocols: ['OpenVPN']
  vpnAuthenticationTypes: ['AAD']
  aadTenant: 'https://login.microsoftonline.com/${tenantId}/'
  aadAudience: p2sAudience
  aadIssuer: 'https://sts.windows.net/${tenantId}/'
}

resource gateway 'Microsoft.Network/virtualNetworkGateways@2024-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    vpnGatewayGeneration: 'Generation1'
    sku: { name: 'VpnGw1AZ', tier: 'VpnGw1AZ' }
    activeActive: false
    enableBgp: false
    ipConfigurations: [
      {
        name: 'default'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: { id: gatewaySubnetId }
          publicIPAddress: { id: pip.id }
        }
      }
    ]
    vpnClientConfiguration: p2s
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  name: 'to-law-sc500-l05'
  scope: gateway
  properties: {
    workspaceId: workspaceId
    logs: [{ categoryGroup: 'allLogs', enabled: true }]
  }
}

output gatewayId string = gateway.id
output publicIp string = pip.properties.ipAddress
