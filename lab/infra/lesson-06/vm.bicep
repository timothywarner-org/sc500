// One private Ubuntu test VM and its NIC, shared by every Lesson 6 template so the fixtures are
// identical: no public IP, SSH key only (the private key is discarded at deploy time), Trusted
// Launch, and a static private address so DNS answers and evidence stay readable. Same shape as
// the Lesson 5 module, plus a managed identity and an optional load balancer backend pool.

@description('VM name, for example vm-servicehub-prod-001. Linux, so it doubles as the host name.')
param name string
param location string
param tags object
param subnetId string
@description('Static private IP.')
param privateIp string
@description('Base64 cloud-init, or empty for no customization.')
param customData string = ''
param vmSize string
param sshPublicKey string
param imageVersion string = 'latest'
@description('SystemAssigned, UserAssigned, or None. The demos read blobs with the VM identity, never a key.')
@allowed(['SystemAssigned', 'UserAssigned', 'None'])
param identityType string = 'None'
@description('User-assigned identity resource IDs when identityType is UserAssigned.')
param userAssignedIdentityIds array = []
@description('Standard load balancer backend pools the NIC joins (the Private Link service provider VM).')
param lbBackendPoolIds array = []

var userIdentities = toObject(userAssignedIdentityIds, id => id, id => {})

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
          loadBalancerBackendAddressPools: [for id in lbBackendPoolIds: { id: id }]
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: name
  location: location
  tags: tags
  identity: identityType == 'None' ? null : (identityType == 'SystemAssigned'
    ? { type: 'SystemAssigned' }
    : { type: 'UserAssigned', userAssignedIdentities: userIdentities })
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
output principalId string = identityType == 'SystemAssigned' ? vm.identity.principalId : ''
