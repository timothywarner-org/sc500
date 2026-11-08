// One private Ubuntu test VM and its NIC. Used by every Lesson 5 template so the fixtures
// are identical: no public IP, SSH key only (the private key is discarded at deploy time),
// Trusted Launch, and a static private address so rules and evidence stay readable.

@description('VM name, for example vm-servicehub-web.')
param name string
param location string
param tags object
param subnetId string
@description('Static private IP. Stable addresses keep flow-log evidence and test commands readable.')
param privateIp string
@description('Application security groups the NIC joins. Empty for VMs that NSG rules address by prefix.')
param asgIds array = []
@description('Base64 cloud-init, or empty for no customization.')
param customData string = ''
param vmSize string
param sshPublicKey string
param imageVersion string = 'latest'

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-${name}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: privateIp
          subnet: { id: subnetId }
          applicationSecurityGroups: [for id in asgIds: { id: id }]
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    hardwareProfile: { vmSize: vmSize }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: imageVersion
      }
      osDisk: {
        name: 'osdisk-${name}'
        createOption: 'FromImage'
        diskSizeGB: 30
        caching: 'ReadWrite'
        managedDisk: { storageAccountType: 'StandardSSD_LRS' }
        deleteOption: 'Delete'
      }
    }
    osProfile: {
      computerName: name
      adminUsername: 'contosoadmin'
      customData: empty(customData) ? null : customData
      linuxConfiguration: {
        disablePasswordAuthentication: true
        provisionVMAgent: true
        ssh: {
          publicKeys: [
            {
              path: '/home/contosoadmin/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: nic.id, properties: { deleteOption: 'Delete' } }]
    }
    diagnosticsProfile: { bootDiagnostics: { enabled: true } }
  }
}

output vmId string = vm.id
output nicId string = nic.id
output privateIp string = privateIp
