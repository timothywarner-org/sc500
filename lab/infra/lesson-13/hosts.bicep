// Lesson 13 collectors: a Linux log forwarder (Syslog and CEF) and a Windows event collector
// (Windows Security events and WEF). Both are private: no public IP, no inbound rule, managed with
// Run Command. Each gets the Azure Monitor Agent and its data collection rule associations.
targetScope = 'resourceGroup'

param location string
param names object
param vm object
param tags object
param dcrs object
param linuxPublicKey string
@secure()
param windowsAdminPassword string

// The first deployment needs outbound access for agent installation; later sessions use Start-L13Lab.ps1.
module egress 'egress.bicep' = {
  name: 'sc500-lesson13-egress'
  params: { location: location, names: names, tags: tags }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: names.nsg
  location: location
  tags: tags
  properties: { securityRules: [] }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: names.vnet
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [ '10.130.0.0/24' ] }
    subnets: [ {
      name: names.subnet
      properties: {
        addressPrefix: '10.130.0.0/27'
        defaultOutboundAccess: false
        networkSecurityGroup: { id: nsg.id }
        natGateway: { id: egress.outputs.natId }
      }
    } ]
  }
}

var subnetId = vnet.properties.subnets[0].id

resource fwdNic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-${names.forwarderVm}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [ { name: 'primary', properties: { privateIPAllocationMethod: 'Static', privateIPAddress: '10.130.0.4', subnet: { id: subnetId } } } ]
  }
}

resource wecNic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-${names.collectorVm}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [ { name: 'primary', properties: { privateIPAllocationMethod: 'Static', privateIPAddress: '10.130.0.5', subnet: { id: subnetId } } } ]
  }
}

// ---- Linux log forwarder ------------------------------------------------------------------------
resource fwd 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: names.forwarderVm
  location: location
  tags: union(tags, { role: 'syslog-cef-forwarder' })
  identity: { type: 'SystemAssigned' }
  properties: {
    hardwareProfile: { vmSize: vm.linuxSize }
    securityProfile: { securityType: 'TrustedLaunch', uefiSettings: { secureBootEnabled: true, vTpmEnabled: true } }
    storageProfile: {
      imageReference: vm.linuxImage
      // D2als_v6 attaches disks over NVMe only (config.json vm.sizeNote).
      diskControllerType: vm.diskControllerType
      osDisk: { name: 'osdisk-${names.forwarderVm}', createOption: 'FromImage', caching: 'ReadWrite', managedDisk: { storageAccountType: 'StandardSSD_LRS' }, deleteOption: 'Delete' }
    }
    osProfile: {
      computerName: names.forwarderComputer
      adminUsername: vm.adminUsername
      // Key-only sign-in. Deploy-L13Lab.ps1 generates the key pair in memory and keeps only the public half.
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: { publicKeys: [ { path: '/home/${vm.adminUsername}/.ssh/authorized_keys', keyData: linuxPublicKey } ] }
      }
    }
    networkProfile: { networkInterfaces: [ { id: fwdNic.id, properties: { deleteOption: 'Delete' } } ] }
    diagnosticsProfile: { bootDiagnostics: { enabled: true } }
  }
}

resource fwdAma 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  parent: fwd
  name: 'AzureMonitorLinuxAgent'
  location: location
  tags: tags
  properties: { publisher: 'Microsoft.Azure.Monitor', type: 'AzureMonitorLinuxAgent', typeHandlerVersion: '1.0', autoUpgradeMinorVersion: true, enableAutomaticUpgrade: true }
}

// An association is named for the rule it attaches, so the VM's list of associations reads as the
// list of routes it feeds.
resource fwdSyslog 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: names.dcrSyslog
  scope: fwd
  dependsOn: [ fwdAma ]
  properties: { dataCollectionRuleId: dcrs.syslog }
}

resource fwdCef 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: names.dcrCef
  scope: fwd
  dependsOn: [ fwdAma ]
  properties: { dataCollectionRuleId: dcrs.cef }
}

// ---- Windows event collector --------------------------------------------------------------------
resource wec 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: names.collectorVm
  location: location
  tags: union(tags, { role: 'windows-event-collector' })
  identity: { type: 'SystemAssigned' }
  properties: {
    hardwareProfile: { vmSize: vm.windowsSize }
    securityProfile: { securityType: 'TrustedLaunch', uefiSettings: { secureBootEnabled: true, vTpmEnabled: true } }
    storageProfile: {
      imageReference: vm.windowsImage
      diskControllerType: vm.diskControllerType
      osDisk: { name: 'osdisk-${names.collectorVm}', createOption: 'FromImage', caching: 'ReadWrite', managedDisk: { storageAccountType: 'StandardSSD_LRS' }, deleteOption: 'Delete' }
    }
    osProfile: {
      computerName: names.collectorComputer
      adminUsername: vm.adminUsername
      // Generated in memory by Deploy-L13Lab.ps1 and never stored. Nobody signs in; Run Command manages the VM.
      adminPassword: windowsAdminPassword
      windowsConfiguration: { provisionVMAgent: true, enableAutomaticUpdates: true }
    }
    networkProfile: { networkInterfaces: [ { id: wecNic.id, properties: { deleteOption: 'Delete' } } ] }
    diagnosticsProfile: { bootDiagnostics: { enabled: true } }
  }
}

resource wecAma 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  parent: wec
  name: 'AzureMonitorWindowsAgent'
  location: location
  tags: tags
  properties: { publisher: 'Microsoft.Azure.Monitor', type: 'AzureMonitorWindowsAgent', typeHandlerVersion: '1.0', autoUpgradeMinorVersion: true, enableAutomaticUpgrade: true }
}

resource wecSecurity 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: names.dcrWindowsSecurity
  scope: wec
  dependsOn: [ wecAma ]
  properties: { dataCollectionRuleId: dcrs.windowsSecurity }
}

resource wecForwarded 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: names.dcrForwarded
  scope: wec
  dependsOn: [ wecAma ]
  properties: { dataCollectionRuleId: dcrs.forwarded }
}

// ---- Auto-shutdown: a backstop for a forgotten Stop-L13Lab.ps1 ---------------------------------
// The DevTest Labs schedule deallocates the VM daily. It doesn't remove the NAT gateway; Stop-L13Lab.ps1 does.
resource fwdShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: 'shutdown-computevm-${names.forwarderVm}'
  location: location
  tags: tags
  properties: {
    status: vm.autoShutdown.enabled ? 'Enabled' : 'Disabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: { time: vm.autoShutdown.time }
    timeZoneId: vm.autoShutdown.timeZoneId
    notificationSettings: { status: 'Disabled', timeInMinutes: 30 }
    targetResourceId: fwd.id
  }
}

resource wecShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: 'shutdown-computevm-${names.collectorVm}'
  location: location
  tags: tags
  properties: {
    status: vm.autoShutdown.enabled ? 'Enabled' : 'Disabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: { time: vm.autoShutdown.time }
    timeZoneId: vm.autoShutdown.timeZoneId
    notificationSettings: { status: 'Disabled', timeInMinutes: 30 }
    targetResourceId: wec.id
  }
}

output lab object = {
  forwarderVm: fwd.name
  forwarderId: fwd.id
  collectorVm: wec.name
  collectorId: wec.id
  vnet: vnet.name
  natId: egress.outputs.natId
}
