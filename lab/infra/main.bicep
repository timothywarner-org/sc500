targetScope = 'subscription'

@description('Region verified for the selected subscription before deployment.')
param location string = 'eastus2'

@description('Public SSH key only. Its private key stays outside the course folder.')
param sshPublicKey string

@description('Pinned Ubuntu Gen2 image version resolved from the live marketplace.')
param imageVersion string = '24.04.202609040'

@description('Small general-purpose SKU verified against subscription quota and restrictions.')
// Standard_B2s added 2026-10-17: the lab subscription restricts every B-series v2 size in
// eastus2 (SkuNotAvailable). B2s keeps 2 vCPUs, 4 GB and encryption at host. The config picks one.
@allowed(['Standard_B2ls_v2', 'Standard_B2s'])
param vmSize string = 'Standard_B2ls_v2'

var tags = {
  course: 'SC500'
  workload: 'ContosoServiceHub'
  managedBy: 'sc500-demo-iac'
  lifecycle: 'retain-until-recording-complete'
  lesson: '01'
}

// Separate groups make the positive, negative, and lock demonstrations independently resettable.
resource workload 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-sc500-identity-lab'
  location: location
  tags: tags
}
resource comparison 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-sc500-comparison-lab'
  location: location
  tags: tags
}
resource lockFixture 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-sc500-lock-lab'
  location: location
  tags: union(tags, { lifecycle: 'disposable-lock-fixture' })
}

module maintenanceVm './modules/maintenance-vm.bicep' = {
  name: 'sc500-maintenance-vm'
  scope: workload
  params: {
    location: location
    vmName: 'vm-maint-01'
    networkName: 'vnet-sc500-identity'
    networkPrefix: '10.50.1.0/24'
    subnetPrefix: '10.50.1.0/26'
    vmSize: vmSize
    imageVersion: imageVersion
    sshPublicKey: sshPublicKey
    tags: tags
  }
}
module comparisonVm './modules/maintenance-vm.bicep' = {
  name: 'sc500-comparison-vm'
  scope: comparison
  params: {
    location: location
    vmName: 'vm-compare-01'
    networkName: 'vnet-sc500-comparison'
    networkPrefix: '10.50.2.0/24'
    subnetPrefix: '10.50.2.0/26'
    vmSize: vmSize
    imageVersion: imageVersion
    sshPublicKey: sshPublicKey
    tags: tags
  }
}

output maintenanceVmId string = maintenanceVm.outputs.vmId
output comparisonVmId string = comparisonVm.outputs.vmId
output maintenanceDiskId string = maintenanceVm.outputs.osDiskId
output comparisonDiskId string = comparisonVm.outputs.osDiskId
output lockResourceGroupId string = lockFixture.id

