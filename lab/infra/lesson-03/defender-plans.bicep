// Defender for Cloud plans that Lesson 3's sections 3.2 and 3.3 depend on (subscription scope).
//
// WHY THIS EXISTS: on 2026-10-10 CloudPosture (Defender CSPM) and KeyVaults read Free, so the
// SSH-key secrets finding on vm-sc500-l03-runner was gone and regulatory compliance assessments
// weren't available. On 2026-09-26, when the evidence was captured, both were Standard and CSPM had
// agentless VM scanning on. This template is the single declaration of both states:
//   TakeReady  CloudPosture Standard with AgentlessVmScanning, KeyVaults Standard (PerKeyVault)
//   Parked     both Free
// VirtualMachines (Defender for Servers) is deliberately absent: Defender CSPM already includes
// agentless machine secrets scanning, and this template leaves that plan exactly as it finds it.
//
// Set-L03ScanWindow.ps1 deploys this; run it directly only to preview:
//   az deployment sub what-if --location eastus2 --template-file infra/lesson-03/defender-plans.bicep \
//     --parameters state=TakeReady
//
// Sources (checked 2026-10-10):
//   https://learn.microsoft.com/azure/templates/microsoft.security/2024-01-01/pricings
//   https://learn.microsoft.com/azure/defender-for-cloud/secrets-scanning-servers
//   https://learn.microsoft.com/azure/defender-for-cloud/concept-cloud-security-posture-management
targetScope = 'subscription'

@description('TakeReady for a recording window, Parked otherwise.')
@allowed([
  'TakeReady'
  'Parked'
])
param state string = 'Parked'

var takeReady = state == 'TakeReady'

resource keyVaults 'Microsoft.Security/pricings@2024-01-01' = {
  name: 'KeyVaults'
  properties: takeReady ? {
    pricingTier: 'Standard'
    subPlan: 'PerKeyVault'
  } : {
    pricingTier: 'Free'
  }
}

// Pricing updates are applied one plan at a time, so CSPM waits for Key Vault.
resource cloudPosture 'Microsoft.Security/pricings@2024-01-01' = {
  name: 'CloudPosture'
  properties: takeReady ? {
    pricingTier: 'Standard'
    extensions: [
      {
        name: 'AgentlessVmScanning'
        isEnabled: 'True'
      }
    ]
  } : {
    pricingTier: 'Free'
  }
  dependsOn: [
    keyVaults
  ]
}

output state string = state
