// An unpeered Windows client proves the GSA path without a hidden route into ServiceHub.
targetScope = 'resourceGroup'
param location string = 'eastus2'
@description('Windows 11 client size, from config.json windowsVmSize.')
param vmSize string = 'Standard_B2s'
param imageVersion string
param operatorPublicIp string
param operatorObjectId string
@secure()
param adminPassword string
@description('Resource names from config.json names, per Cloud Adoption Framework naming guidance, https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming (CAF, applied to Contoso).')
param names object
var tags = { managedBy: 'sc500-l06-iac', lesson: '6', lifecycle: 'retain-deallocated', purpose: 'private-access-client' }

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: names.clientNsg
  location: location
  tags: tags
  properties: {
    securityRules: [{
      name: 'RDP-Operator-Only'
      properties: {
        priority: 100
        direction: 'Inbound'
        access: 'Allow'
        protocol: 'Tcp'
        sourceAddressPrefix: '${operatorPublicIp}/32'
        sourcePortRange: '*'
        destinationAddressPrefix: '*'
        destinationPortRange: '3389'
      }
    }]
  }
}
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: names.clientVnet
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: ['10.60.48.0/24'] }
    subnets: [{
      name: 'snet-client'
      properties: { addressPrefix: '10.60.48.0/27', defaultOutboundAccess: false }
    }]
  }
}
// A Standard public IP supplies explicit egress. Only the operator's /32 can reach RDP.
resource pip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: names.clientPip
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static', publicIPAddressVersion: 'IPv4' }
}
resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: names.clientNic
  location: location
  tags: tags
  properties: {
    networkSecurityGroup: { id: nsg.id }
    ipConfigurations: [{
      name: 'primary'
      properties: {
        privateIPAllocationMethod: 'Static'
        privateIPAddress: '10.60.48.4'
        subnet: { id: vnet.properties.subnets[0].id }
        publicIPAddress: { id: pip.id }
      }
    }]
  }
}
resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: names.clientVm
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    hardwareProfile: { vmSize: vmSize }
    securityProfile: { securityType: 'TrustedLaunch', uefiSettings: { secureBootEnabled: true, vTpmEnabled: true } }
    storageProfile: {
      imageReference: { publisher: 'MicrosoftWindowsDesktop', offer: 'windows-11', sku: 'win11-24h2-pro', version: imageVersion }
      osDisk: { name: names.clientOsDisk, createOption: 'FromImage', caching: 'ReadWrite', managedDisk: { storageAccountType: 'StandardSSD_LRS' }, deleteOption: 'Delete' }
    }
    osProfile: {
      computerName: names.clientComputer
      adminUsername: 'contosoadmin'
      adminPassword: adminPassword
      windowsConfiguration: { provisionVMAgent: true, enableAutomaticUpdates: true }
    }
    networkProfile: { networkInterfaces: [{ id: nic.id, properties: { deleteOption: 'Delete' } }] }
    diagnosticsProfile: { bootDiagnostics: { enabled: true } }
  }
}
// Device join is necessary for the GA client scenario. It does not assert Intune compliance.
resource join 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  parent: vm
  name: 'AADLoginForWindows'
  location: location
  tags: tags
  properties: { publisher: 'Microsoft.Azure.ActiveDirectory', type: 'AADLoginForWindows', typeHandlerVersion: '1.0', autoUpgradeMinorVersion: true }
}
resource login 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vm.id,operatorObjectId,'fb879df8-f326-4884-b1cf-06f3ad86be52')
  scope: vm
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions','fb879df8-f326-4884-b1cf-06f3ad86be52')
    principalId: operatorObjectId
    principalType: 'User'
  }
}
output lab object = { resourceGroup: resourceGroup().name, vm: vm.name, computerName: names.clientComputer, publicIp: pip.properties.ipAddress, privateIp: '10.60.48.4', peering: 'none', location: location }
