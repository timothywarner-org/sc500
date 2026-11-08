// SC-500 Lesson 6 bounded lab: a Windows Server host for the Microsoft Entra private network
// connector (demo 6.3).
//
// The connector only ever makes outbound connections (ports 80 and 443) to the Private Access
// service; it needs no inbound port. The public IP here exists for two outbound reasons (the
// hub subnets have no default outbound access, and a NAT gateway would cost more for a bounded
// lab) and for operator-only RDP. Setup uses delegated registration after your interactive
// sign-in. Registration credentials travel only through protected Run Command parameters.
// The NSG allows RDP only from the operator's current public IP. Retain the registered host
// deallocated between runs. The connector NIC sits in the hub, so it can reach the app VM
// (10.60.16.4:8080) over the hub-to-spoke peering.
// Cost while deployed: about 0.05 USD an hour.

param location string
param tags object
param subnetId string
param privateIp string
param vmSize string
param operatorPublicIp string
@secure()
@description('Generated in memory by Deploy-L06Bounded.ps1 and saved only as a DPAPI-protected file for you.')
param adminPassword string
@description('Resource names from config.json names, per Cloud Adoption Framework naming guidance, https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming (CAF, applied to Contoso).')
param names object

resource pip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: names.connectorPip
  location: location
  tags: tags
  sku: { name: 'Standard', tier: 'Regional' }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: names.connectorNsg
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-RDP-From-Operator'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '${operatorPublicIp}/32'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
          description: 'You install and register the connector interactively. Nothing else gets in.'
        }
      }
    ]
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: names.connectorNic
  location: location
  tags: tags
  properties: {
    networkSecurityGroup: { id: nsg.id }
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: privateIp
          subnet: { id: subnetId }
          publicIPAddress: { id: pip.id }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: names.connectorVm
  location: location
  tags: tags
  properties: {
    hardwareProfile: { vmSize: vmSize }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: { secureBootEnabled: true, vTpmEnabled: true }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        name: names.connectorOsDisk
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: { storageAccountType: 'StandardSSD_LRS' }
        deleteOption: 'Delete'
      }
    }
    osProfile: {
      // Windows host names stop at 15 characters, so the host gets its own CAF-style name.
      computerName: names.connectorComputer
      adminUsername: 'contosoadmin'
      adminPassword: adminPassword
      windowsConfiguration: {
        provisionVMAgent: true
        enableAutomaticUpdates: true
        patchSettings: { patchMode: 'AutomaticByOS' }
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: nic.id, properties: { deleteOption: 'Delete' } }]
    }
    diagnosticsProfile: { bootDiagnostics: { enabled: true } }
  }
}

output lab object = {
  resourceGroup: resourceGroup().name
  vm: vm.name
  computerName: names.connectorComputer
  privateIp: privateIp
  publicIp: pip.properties.ipAddress
}
