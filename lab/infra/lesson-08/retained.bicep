// Retained part of the SC-500 Lesson 8 lab: Contoso's servers (resource group scope).
//
//   vm-servicehub-prod-001   ServiceHub's app server. Trusted Launch (Secure Boot, vTPM, integrity
//                            monitoring), encryption at host, no public IP, reached through Bastion
//                            Developer. Machine configuration audits it against the Azure compute
//                            security baseline. Defender for Servers Plan 2 (on for the whole
//                            subscription) covers it.
//   vm-datacenter-prod-001  A server in Contoso's datacenter: an Azure VM prepared, per
//                            Microsoft's evaluation procedure, to behave like an on-premises machine
//                            so it can be onboarded to Azure Arc as arcs-datacenter-prod-001.
//                            Defender for Servers is off for this VM resource, so only its Arc
//                            identity is covered once you connect it.
//   bas-servers-prod-eastus2-001  Bastion Developer: free, portal-only, one connection at a time.
//
// Two Azure Policy assignments at this resource group: the Linux security baseline through machine
// configuration (Arc machines included), and "encryption at host enabled" (audit).
//
// The bounded legacy app server (public IP, Standard security type, JIT) is in legacy.bicep.

@description('Azure region for every resource.')
param location string

@description('Every resource name, from config.json.')
param names object

@description('Address plan, from config.json.')
param addressPlan object

@description('VM sizes by role, from config.json.')
param vmSizes object

@description('Lab admin user name.')
param adminUsername string

@description('Public half of the lab admin key.')
param sshPublicKey string

@description('Pinned Ubuntu image version.')
param imageVersion string

@description('Base64 cloud-init for the ServiceHub app server.')
param appCustomData string

@description('Base64 cloud-init for the datacenter server.')
param onpremCustomData string

@description('Built-in policy definition GUIDs.')
param policyDefinitions object

@description('Common tags from config.json. Each resource adds its own workload and env, CAF\'s functional tags.')
param tags object

@description('Auto-shutdown settings from config.json.')
param autoShutdown object

var serversTags = union(tags, { workload: 'servers', env: 'prod' })
var appTags = union(tags, { workload: 'servicehub', env: 'prod' })
var onpremTags = union(tags, { workload: 'datacenter', env: 'prod' })

// Servers subnet NSG. SSH only from inside the VNet, which is where Bastion connects from; the
// default rules deny everything inbound from the internet.
resource serversNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: names.serversNsg
  location: location
  tags: serversTags
  properties: {
    securityRules: [
      {
        name: 'allow-ssh-from-vnet'
        properties: {
          description: 'Bastion reaches the servers on their private IPs. Nothing from the internet.'
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: names.vnet
  location: location
  tags: serversTags
  properties: {
    addressSpace: { addressPrefixes: [addressPlan.vnet] }
    subnets: [
      {
        name: names.serversSubnet
        properties: {
          addressPrefix: addressPlan.servers
          networkSecurityGroup: { id: serversNsg.id }
          // Lab economy, stated plainly: the agents on these servers (Defender for Endpoint, the
          // Arc agent, machine configuration, guest attestation) need outbound HTTPS, and a NAT
          // gateway would cost more than the rest of the lab. Production uses an explicit method
          // such as a NAT gateway or a firewall, as Lesson 7 does.
          defaultOutboundAccess: true
        }
      }
      {
        name: names.legacySubnet
        properties: {
          addressPrefix: addressPlan.legacy
          // The bounded legacy server has its own public IP, which is its explicit outbound path.
          defaultOutboundAccess: false
        }
      }
    ]
  }
}

// Bastion Developer: no AzureBastionSubnet and no public IP. East US 2 supports it.
resource bastion 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: names.bastion
  location: location
  tags: serversTags
  sku: { name: 'Developer' }
  properties: {
    virtualNetwork: { id: vnet.id }
  }
}

module app 'vm.bicep' = {
  name: 'vm-${names.appVm}'
  params: {
    name: names.appVm
    location: location
    tags: appTags
    subnetId: vnet.properties.subnets[0].id
    privateIp: addressPlan.hosts.app
    vmSize: vmSizes.app
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    imageVersion: imageVersion
    customData: appCustomData
    securityType: 'TrustedLaunch'
    encryptionAtHost: true
    systemIdentity: true
    autoShutdown: autoShutdown
  }
}

resource appVm 'Microsoft.Compute/virtualMachines@2024-11-01' existing = {
  name: names.appVm
}

// Integrity monitoring: the Guest Attestation extension, configured as Microsoft's template does.
resource attestation 'Microsoft.Compute/virtualMachines/extensions@2024-11-01' = {
  parent: appVm
  name: 'GuestAttestation'
  location: location
  tags: appTags
  dependsOn: [app]
  properties: {
    publisher: 'Microsoft.Azure.Security.LinuxAttestation'
    type: 'GuestAttestation'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    settings: {
      AttestationConfig: {
        MaaSettings: { maaEndpoint: '', maaTenantName: 'GuestAttestation' }
        AscSettings: { ascReportingEndpoint: '', ascReportingFrequency: '' }
        useCustomToken: 'false'
        disableAlerts: 'false'
      }
    }
  }
}

// Machine configuration on an Azure VM needs this extension and a system-assigned identity. At
// scale you'd assign the "Deploy prerequisites to enable Guest Configuration policies on virtual
// machines" initiative instead; one VM doesn't need it.
resource machineConfiguration 'Microsoft.Compute/virtualMachines/extensions@2024-11-01' = {
  parent: appVm
  name: 'AzurePolicyforLinux'
  location: location
  tags: appTags
  dependsOn: [attestation]
  properties: {
    publisher: 'Microsoft.GuestConfiguration'
    type: 'ConfigurationForLinux'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
  }
}

module onprem 'vm.bicep' = {
  name: 'vm-${names.onpremVm}'
  params: {
    name: names.onpremVm
    computerName: names.onpremComputer
    location: location
    tags: onpremTags
    subnetId: vnet.properties.subnets[0].id
    privateIp: addressPlan.hosts.onprem
    vmSize: vmSizes.onprem
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    imageVersion: imageVersion
    customData: onpremCustomData
    securityType: 'TrustedLaunch'
    // On, so the encryption-at-host audit leaves the legacy server as the only exception.
    encryptionAtHost: true
    systemIdentity: false
    autoShutdown: autoShutdown
  }
}

resource onpremVm 'Microsoft.Compute/virtualMachines@2024-11-01' existing = {
  name: names.onpremVm
}

// Plan 2 is on for the subscription, and it can be turned off per resource. Turning it off for the
// Azure VM that plays the on-premises server keeps Defender from installing an extension on it and
// from billing the same server twice once its Arc identity exists.
resource onpremDefender 'Microsoft.Security/pricings@2024-01-01' = {
  name: 'VirtualMachines'
  scope: onpremVm
  dependsOn: [onprem]
  properties: {
    pricingTier: 'Free'
  }
}

// Linux security baseline through machine configuration, for Azure VMs and Arc machines here.
resource baselineAssignment 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: names.baselineAssignment
  properties: {
    displayName: 'Contoso servers: Linux machines should meet the Azure compute security baseline'
    description: 'Audit through Azure Machine Configuration. Arc machines included.'
    policyDefinitionId: tenantResourceId('Microsoft.Authorization/policyDefinitions', policyDefinitions.linuxBaseline)
    parameters: {
      IncludeArcMachines: { value: 'true' }
      effect: { value: 'AuditIfNotExists' }
    }
    nonComplianceMessages: [{ message: 'This Linux server does not meet the Azure compute security baseline.' }]
  }
}

// Encryption at host, audited for every VM here, so the legacy server shows up as the exception.
resource encryptionAtHostAssignment 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: names.encryptionAtHostAssignment
  properties: {
    displayName: 'Contoso servers: Virtual machines should have encryption at host enabled'
    description: 'Audit only.'
    policyDefinitionId: tenantResourceId('Microsoft.Authorization/policyDefinitions', policyDefinitions.encryptionAtHost)
    parameters: {
      effect: { value: 'Audit' }
    }
    nonComplianceMessages: [{ message: 'Enable encryption at host on this VM.' }]
  }
}

@description('Resource IDs, names and addresses the lesson scripts read back.')
output lab object = {
  resourceGroup: resourceGroup().name
  location: location
  vnetId: vnet.id
  serversSubnetId: vnet.properties.subnets[0].id
  legacySubnetId: vnet.properties.subnets[1].id
  bastionId: bastion.id
  appVmId: app.outputs.vmId
  appVmName: names.appVm
  appPrivateIp: addressPlan.hosts.app
  appPrincipalId: app.outputs.principalId
  onpremVmId: onprem.outputs.vmId
  onpremVmName: names.onpremVm
  onpremPrivateIp: addressPlan.hosts.onprem
  baselineAssignmentId: baselineAssignment.id
  encryptionAtHostAssignmentId: encryptionAtHostAssignment.id
}
