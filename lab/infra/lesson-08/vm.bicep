// One Ubuntu 24.04 server, its NIC and its daily auto-shutdown, for the Lesson 8 lab. The caller
// decides the parts the lesson compares: the security type (Trusted Launch or Standard), encryption
// at host, a system-assigned identity for machine configuration, and whether the NIC gets a public
// IP and its own NSG (only the bounded legacy app server does). SSH key only; the private key
// never touches the repo. Static private addresses keep evidence and demo commands stable.
//
// Child names follow Cloud Adoption Framework naming guidance, https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming: {type}-{parent name}, so the app server's NIC
// is nic-vm-servicehub-prod-001 and its OS disk osdisk-vm-servicehub-prod-001.

@description('VM name from config.json, for example vm-servicehub-prod-001.')
param name string

@description('Host name inside the OS. The field office server uses a host name that doesn\'t say vm, as an on-premises server wouldn\'t.')
param computerName string = name

@description('Azure region, from the caller.')
param location string

@description('Tags: the common set plus this server\'s workload and env.')
param tags object

@description('Resource ID of the subnet for the NIC.')
param subnetId string

@description('Static private IP.')
param privateIp string

@description('VM size, checked against restrictions and quota by the deploy script.')
param vmSize string

@description('Lab admin user name.')
param adminUsername string

@description('Public half of the lab admin key.')
param sshPublicKey string

@description('Pinned Ubuntu image version.')
param imageVersion string

@description('Base64 cloud-init, or empty. Azure refuses to change customData on an existing VM.')
param customData string = ''

@description('TrustedLaunch turns on Secure Boot and the vTPM. Empty leaves the Standard security type (the default for this API version).')
@allowed(['TrustedLaunch', ''])
param securityType string = 'TrustedLaunch'

@description('Encrypt temp disks and disk caches on the host. Needs the Microsoft.Compute/EncryptionAtHost feature, which the preflight checks.')
param encryptionAtHost bool = false

@description('A system-assigned identity, which machine configuration needs on Azure VMs.')
param systemIdentity bool = false

@description('Resource ID of a public IP for the NIC, or empty for none.')
param publicIpId string = ''

@description('Resource ID of an NSG for the NIC, or empty to rely on the subnet NSG.')
param nicNsgId string = ''

@description('Auto-shutdown settings from config.json. enabled false deploys the schedule Disabled (the pre-demo soak).')
param autoShutdown object

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-${name}'
  location: location
  tags: tags
  properties: {
    networkSecurityGroup: empty(nicNsgId) ? null : { id: nicNsgId }
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: privateIp
          subnet: { id: subnetId }
          publicIPAddress: empty(publicIpId) ? null : { id: publicIpId }
        }
      }
    ]
  }
}

// Build the security profile once, so a Standard VM sends no uefiSettings at all.
var trusted = securityType == 'TrustedLaunch'
var securityProfile = union(
  { encryptionAtHost: encryptionAtHost },
  trusted ? { securityType: 'TrustedLaunch', uefiSettings: { secureBootEnabled: true, vTpmEnabled: true } } : {}
)

resource vm 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: name
  location: location
  tags: tags
  identity: systemIdentity ? { type: 'SystemAssigned' } : null
  properties: {
    hardwareProfile: { vmSize: vmSize }
    securityProfile: securityProfile
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
      computerName: computerName
      adminUsername: adminUsername
      customData: empty(customData) ? null : customData
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
    // Managed boot diagnostics: the lab reads each VM's own evidence from the serial log.
    diagnosticsProfile: { bootDiagnostics: { enabled: true } }
  }
}

// Cost guardrail (CAF G1): a VM left running after the demo stops at 23:00 Central. The schedule
// always exists, so the guardrail can't be forgotten; a soak deploys it Disabled. Notifications are
// off, because a lab fixture's shutdown needs no warning.
resource shutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: 'shutdown-computevm-${name}'
  location: location
  tags: tags
  properties: {
    status: autoShutdown.enabled ? 'Enabled' : 'Disabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: { time: autoShutdown.time }
    timeZoneId: autoShutdown.timeZoneId
    notificationSettings: { status: 'Disabled', timeInMinutes: 30 }
    targetResourceId: vm.id
  }
}

@description('The VM\'s resource ID.')
output vmId string = vm.id

@description('The VM\'s name.')
output vmName string = vm.name

@description('The NIC\'s resource ID.')
output nicId string = nic.id

@description('The static private IP.')
output privateIp string = privateIp

// Safe dereference: a VM without an identity has no identity block to read.
@description('The system-assigned identity\'s principal ID, or empty.')
output principalId string = vm.?identity.?principalId ?? ''
