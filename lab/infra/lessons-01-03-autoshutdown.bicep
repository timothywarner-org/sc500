// Parked-state auto-shutdown for every Lessons 1-3 VM (subscription scope).
//
// Run this after a from-zero rebuild, once the lesson templates have created the VMs, so the
// overnight safety net comes back exactly as it was. It doesn't create or start any VM.
//
//   az deployment sub what-if --location eastus2 --template-file infra/lessons-01-03-autoshutdown.bicep
//   az deployment sub create  --location eastus2 --template-file infra/lessons-01-03-autoshutdown.bicep
//
// Lesson 3's scan window pauses only the runner's schedule, through auto-shutdown.bicep directly.
targetScope = 'subscription'

@description('Parked default for all three VMs.')
@allowed([
  'Enabled'
  'Disabled'
])
param status string = 'Enabled'

var vms = [
  {
    group: 'rg-sc500-identity-lab'
    name: 'vm-maint-01'
  }
  {
    group: 'rg-sc500-comparison-lab'
    name: 'vm-compare-01'
  }
  {
    group: 'rg-sc500-l03-platform'
    name: 'vm-sc500-l03-runner'
  }
]

module shutdown './auto-shutdown.bicep' = [for vm in vms: {
  name: 'sc500-autoshutdown-${vm.name}'
  scope: resourceGroup(vm.group)
  params: {
    vmName: vm.name
    status: status
  }
}]
