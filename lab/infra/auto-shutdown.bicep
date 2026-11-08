// Daily auto-shutdown for one course VM (resource-group scope).
//
// WHY THIS EXISTS: every Lessons 1-3 VM carries a 23:00 Central auto-shutdown that was added on
// 2026-10-06 outside any template. Declaring it here makes the parked state reproducible after a
// rebuild, and lets Lesson 3 pause it on purpose for a Defender scan window (status: 'Disabled').
//
// The values mirror the live schedules read back on 2026-10-10: daily 2300, Central Standard Time,
// notifications off. The resource name is fixed by the platform convention, shutdown-computevm-<vm>.
//
// Deploy to a VM's own resource group, for example:
//   az deployment group what-if -g rg-sc500-l03-platform --template-file infra/auto-shutdown.bicep \
//     --parameters vmName=vm-sc500-l03-runner status=Enabled
// Schema: https://learn.microsoft.com/azure/templates/microsoft.devtestlab/2018-09-15/schedules

@description('Name of an existing VM in this resource group.')
param vmName string

@description('Enabled is the parked default. Disabled keeps the VM running overnight, for example through a Defender scan window.')
@allowed([
  'Enabled'
  'Disabled'
])
param status string = 'Enabled'

@description('Local shutdown time in 24-hour HHmm.')
param time string = '2300'

@description('Windows time zone ID for the shutdown time.')
param timeZoneId string = 'Central Standard Time'

param location string = resourceGroup().location

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' existing = {
  name: vmName
}

resource shutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: 'shutdown-computevm-${vmName}'
  location: location
  properties: {
    status: status
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: time
    }
    timeZoneId: timeZoneId
    notificationSettings: {
      status: 'Disabled'
      timeInMinutes: 30
    }
    targetResourceId: vm.id
  }
}

output scheduleId string = shutdown.id
output scheduleStatus string = status
