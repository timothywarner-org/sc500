param location string
param tags object
param targetGroupId string
param probeSourceBase64 string
param includeFederation bool
@allowed(['Both', 'UserAssigned', 'SystemAssigned'])
param probeIdentity string

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'id-sc500-l02-servicehub'
  location: location
  tags: tags
}

// Exact repository/environment matching avoids trusting every branch or repository.
resource federation 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2024-11-30' = if (includeFederation) {
  parent: identity
  name: 'github-sc500-lesson02'
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: 'repo:<your-github-owner>/sc500:environment:sc500-lesson02'
    audiences: ['api://AzureADTokenExchange']
  }
}

resource container 'Microsoft.ContainerInstance/containerGroups@2025-09-01' = {
  name: 'aci-sc500-l02-identity'
  location: location
  tags: tags
  // Retain the system principal in both phases; temporarily detach, never delete, the UAMI.
  identity: probeIdentity == 'SystemAssigned' ? {
    type: 'SystemAssigned'
  } : {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${identity.id}': {}
    }
  }
  properties: {
    osType: 'Linux'
    sku: 'Standard'
    restartPolicy: 'Never'
    // No ipAddress or ports means no public ingress. The ARM probe still needs outbound HTTPS.
    containers: [{
      name: 'identity-probe'
      properties: {
        image: 'mcr.microsoft.com/azure-cli@sha256:7f9ca8e6bf1c72e5fafefb6925546272776d635fb428538455c5c79bb77e2aa7'
        command: [
          'python3'
          '-u'
          '-c'
          'import os,base64;exec(compile(base64.b64decode(os.environ["PROBE_SOURCE_BASE64"]),"identity-probe.py","exec"))'
        ]
        environmentVariables: [
          { name: 'PROBE_SOURCE_BASE64', value: probeSourceBase64 }
          { name: 'TARGET_GROUP_ID', value: targetGroupId }
          { name: 'USER_IDENTITY_CLIENT_ID', value: identity.properties.clientId }
          { name: 'EXPECTED_TENANT_ID', value: subscription().tenantId }
          { name: 'PROBE_IDENTITY', value: probeIdentity }
          { name: 'HOME', value: '/tmp' }
          { name: 'AZURE_CONFIG_DIR', value: '/tmp/azure' }
        ]
        resources: {
          requests: { cpu: 1, memoryInGB: json('1.5') }
          limits: { cpu: 1, memoryInGB: json('1.5') }
        }
        securityContext: {
          // East US 2 Standard ACI rejected the other advertised fields; the launcher drops UID/GID before networking.
          privileged: false
        }
      }
    }]
  }
}

output containerGroupId string = container.id
output systemPrincipalId string = container.identity.principalId
output userPrincipalId string = identity.properties.principalId
output userClientId string = identity.properties.clientId
output userIdentityId string = identity.id
