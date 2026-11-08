// One private Ubuntu test VM, its NIC, and its daily auto-shutdown, the same shape as the Lesson 5
// and 6 fixtures: no public IP, SSH key only (the private key is discarded at deploy time),
// Trusted Launch, and a static private address so firewall logs and Network Watcher results stay
// readable. No managed identity: nothing on these VMs signs in to Azure.
//
// Child names follow Cloud Adoption Framework naming guidance, https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming: {type}-{parent name}, so nic-vm-servicehub-prod-001
// and osdisk-vm-servicehub-prod-001. The shutdown schedule's name is fixed by the platform:
// shutdown-computevm-{vm name}.

@description('VM name from config.json, for example vm-servicehub-prod-001.')
@minLength(1)
@maxLength(64)
param name string

@description('Azure region.')
param location string

@description('Tags: the common set plus this VM\'s workload and env.')
param tags object

@description('Resource ID of the subnet for the NIC.')
param subnetId string

@description('Static private IP.')
param privateIp string

@description('Base64 cloud-init. Azure refuses to change customData on an existing VM.')
param customData string

@description('VM size.')
param vmSize string

@description('SSH public key. The private half is never saved.')
param sshPublicKey string

@description('Pinned Ubuntu image version.')
param imageVersion string

@description('Auto-shutdown settings: enabled, time (HHmm) and timeZoneId.')
param autoShutdown object

@description('Local admin user for the SSH key. Nobody signs in with it.')
param adminUsername string = 'contosoadmin'

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
      adminUsername: adminUsername
      customData: customData
      linuxConfiguration: {
        disablePasswordAuthentication: true
        provisionVMAgent: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
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

// Cost guardrail: a VM left running after the demo stops at 23:00 Central. Notifications are off,
// because a shutdown of a lab fixture needs no warning.
resource shutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = if (autoShutdown.enabled) {
  name: 'shutdown-computevm-${name}'
  location: location
  tags: tags
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: { time: autoShutdown.time }
    timeZoneId: autoShutdown.timeZoneId
    notificationSettings: { status: 'Disabled', timeInMinutes: 30 }
    targetResourceId: vm.id
  }
}

@description('The VM\'s resource ID.')
output vmId string = vm.id

@description('The NIC\'s resource ID.')
output nicId string = nic.id

@description('The static private IP.')
output privateIp string = privateIp
