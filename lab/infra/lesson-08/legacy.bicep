// Bounded part of the SC-500 Lesson 8 lab (resource group scope): vm-legacyapp-prod-001, the
// legacy app server Contoso hasn't modernized. It has everything the rest of the lesson removes: a
// public IP, the Standard security type (no Secure Boot, no vTPM), no encryption at host, and a
// standing NSG rule that lets the operator's IP reach SSH at any time. The access demo turns that
// standing access into just-in-time access through Defender for Cloud; the host demo shows it as
// the encryption-at-host policy's exception.
//
// lifecycle says bounded. Remove-L08Bounded.ps1 deletes it, and its JIT policy, after the demo.

@description('Azure region, from config.json.')
param location string

@description('Every resource name, from config.json.')
param names object

@description('Address plan, from config.json.')
param addressPlan object

@description('VM size for the legacy server, from config.json.')
param vmSize string

@description('Lab admin user name.')
param adminUsername string

@description('Public half of the lab admin key.')
param sshPublicKey string

@description('Pinned Ubuntu image version.')
param imageVersion string

@description('The operator workstation\'s current public IP, for the standing SSH rule.')
param operatorPublicIp string

@description('Resource ID of snet-legacy, from the retained deployment\'s outputs.')
param legacySubnetId string

@description('Common tags from config.json.')
param tags object

@description('Auto-shutdown settings from config.json.')
param autoShutdown object

var legacyTags = union(tags, { workload: 'legacyapp', env: 'prod', lifecycle: 'bounded: remove after the rehearsal or take' })

resource pip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: names.legacyPublicIp
  location: location
  tags: legacyTags
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// The "before" picture: SSH open to one admin address, all day, every day. JIT's deny rule and
// its time-bound allow rules land in this NSG when Defender for Cloud takes over the port.
resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: names.legacyNsg
  location: location
  tags: legacyTags
  properties: {
    securityRules: [
      {
        name: 'allow-ssh-admin-standing'
        properties: {
          description: 'Standing admin access: the thing JIT replaces.'
          priority: 1000
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '${operatorPublicIp}/32'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
}

module legacy 'vm.bicep' = {
  name: 'vm-${names.legacyVm}'
  params: {
    name: names.legacyVm
    location: location
    tags: legacyTags
    subnetId: legacySubnetId
    privateIp: addressPlan.hosts.legacy
    vmSize: vmSize
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    imageVersion: imageVersion
    securityType: ''
    encryptionAtHost: false
    systemIdentity: false
    publicIpId: pip.id
    nicNsgId: nsg.id
    autoShutdown: autoShutdown
  }
}

@description('The legacy server\'s resource ID.')
output legacyVmId string = legacy.outputs.vmId

@description('The legacy server\'s name.')
output legacyVmName string = names.legacyVm

@description('The legacy server\'s public IP address.')
output legacyPublicIp string = pip.properties.ipAddress

@description('The legacy server\'s NIC NSG resource ID.')
output legacyNsgId string = nsg.id
