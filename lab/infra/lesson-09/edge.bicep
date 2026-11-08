// SC-500 Lesson 9, bounded part (resource group scope): the public edge in front of the App
// Service origin, and a Container Instances worker. Created for the demo and deleted right after
// (Deploy-L09Edge.ps1, Remove-L09Edge.ps1). Application Gateway WAF_v2 bills by the hour while it
// exists; Front Door Standard's base fee and WAF policy bill by the month, prorated.
//
// lifecycle says bounded. Remove-L09Edge.ps1 refuses any resource without this lesson's managedby
// tag and a bounded lifecycle.

@description('Azure region for the gateway, its IP and WAF policy, and the worker, from config.json.')
param location string

@description('Region for the App Service origin, from config.json (southcentralus: where this subscription has App Service quota).')
param webLocation string

@description('Every resource name, from config.json.')
param names object

@description('The registry\'s login server, from the retained deployment\'s outputs.')
param registryServer string

@description('Resource ID of the image-pull identity, from the retained deployment\'s outputs.')
param pullIdentityId string

@description('Resource ID of the lesson\'s Log Analytics workspace, from the retained deployment\'s outputs.')
param workspaceId string

@description('Common tags from config.json. Each resource adds its own workload and env, and the bounded lifecycle.')
param tags object

var bounded = { lifecycle: 'bounded: remove after the rehearsal or take' }
var servicehubTags = union(tags, { workload: 'servicehub', env: 'prod' }, bounded)
var workerTags = union(tags, { workload: 'partsworker', env: 'prod' }, bounded)
// The origin runs where the subscription has App Service quota, so its region tag says so.
var webTags = union(servicehubTags, { region: webLocation })
var gatewaySubnetId = resourceId('Microsoft.Network/virtualNetworks/subnets', names.vnet, names.gatewaySubnet)
var aciSubnetId = resourceId('Microsoft.Network/virtualNetworks/subnets', names.vnet, names.aciSubnet)
var agwId = resourceId('Microsoft.Network/applicationGateways', names.gateway)

// ---------- App Service origin ----------
// B1 Linux in South Central US: on November 1, 2026 the lab subscription had no App Service plan
// quota (limit 0) in eastus2 for F1, B1, S1, P0v3 or P1v3, nor B1 in centralus, eastus,
// northcentralus, westus or westus2; southcentralus, westus3 and canadacentral passed ARM
// validation. HTTPS only, TLS 1.3 minimum, no FTP, no basic-auth publishing, no remote debugging,
// a managed identity for outbound calls, and default-deny inbound with two allow rules: this
// Application Gateway's public address, and the AzureFrontDoor.Backend service tag only when the
// X-Azure-FDID header carries this profile's ID. Anything else, including a direct request to the
// default host name, gets 403.
resource webPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: names.webPlan
  location: webLocation
  tags: webTags
  kind: 'linux'
  sku: { name: 'B1', tier: 'Basic' }
  properties: { reserved: true }
}

resource web 'Microsoft.Web/sites@2024-04-01' = {
  name: names.webApp
  location: webLocation
  tags: webTags
  kind: 'app,linux'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: webPlan.id
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      linuxFxVersion: 'NODE|22-lts'
      minTlsVersion: '1.3'
      scmMinTlsVersion: '1.2'
      ftpsState: 'Disabled'
      http20Enabled: true
      remoteDebuggingEnabled: false
      alwaysOn: false
      ipSecurityRestrictionsDefaultAction: 'Deny'
      ipSecurityRestrictions: [
        { name: 'allow-app-gateway', priority: 100, action: 'Allow', tag: 'Default', ipAddress: '${agwIp.properties.ipAddress}/32' }
        { name: 'allow-this-front-door', priority: 110, action: 'Allow', tag: 'ServiceTag', ipAddress: 'AzureFrontDoor.Backend', headers: { 'x-azure-fdid': [ afd.properties.frontDoorId ] } }
      ]
      scmIpSecurityRestrictionsDefaultAction: 'Deny'
      scmIpSecurityRestrictionsUseMain: false
    }
  }
}

resource webFtp 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = { parent: web, name: 'ftp', properties: { allow: false } }
resource webScm 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = { parent: web, name: 'scm', properties: { allow: false } }

// ---------- Application Gateway WAF_v2 (regional) ----------
resource agwIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: names.gatewayIp
  location: location
  tags: servicehubTags
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

// Microsoft's managed rule set in Prevention mode: a request whose anomaly score reaches the
// threshold gets 403 at the gateway and never reaches the origin.
resource agwWaf 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2024-05-01' = {
  name: names.gatewayWaf
  location: location
  tags: servicehubTags
  properties: {
    policySettings: { state: 'Enabled', mode: 'Prevention', requestBodyCheck: true, maxRequestBodySizeInKb: 128, fileUploadLimitInMb: 100 }
    managedRules: { managedRuleSets: [ { ruleSetType: 'Microsoft_DefaultRuleSet', ruleSetVersion: '2.1' } ] }
  }
}

resource agw 'Microsoft.Network/applicationGateways@2024-05-01' = {
  name: names.gateway
  location: location
  tags: servicehubTags
  properties: {
    sku: { name: 'WAF_v2', tier: 'WAF_v2', capacity: 1 }
    firewallPolicy: { id: agwWaf.id }
    gatewayIPConfigurations: [ { name: 'gateway', properties: { subnet: { id: gatewaySubnetId } } } ]
    frontendIPConfigurations: [ { name: 'public', properties: { publicIPAddress: { id: agwIp.id } } } ]
    frontendPorts: [ { name: 'http', properties: { port: 80 } } ]
    backendAddressPools: [ { name: 'servicehub-web', properties: { backendAddresses: [ { fqdn: webHost } ] } } ]
    probes: [
      {
        name: 'web-probe'
        properties: { protocol: 'Https', path: '/', interval: 30, timeout: 30, unhealthyThreshold: 3, pickHostNameFromBackendHttpSettings: true, match: { statusCodes: [ '200-399' ] } }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'https-to-app-service'
        properties: { port: 443, protocol: 'Https', cookieBasedAffinity: 'Disabled', pickHostNameFromBackendAddress: true, requestTimeout: 30, probe: { id: '${agwId}/probes/web-probe' } }
      }
    ]
    httpListeners: [
      {
        name: 'http'
        properties: { frontendIPConfiguration: { id: '${agwId}/frontendIPConfigurations/public' }, frontendPort: { id: '${agwId}/frontendPorts/http' }, protocol: 'Http' }
      }
    ]
    requestRoutingRules: [
      {
        name: 'to-servicehub-web'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: { id: '${agwId}/httpListeners/http' }
          backendAddressPool: { id: '${agwId}/backendAddressPools/servicehub-web' }
          backendHttpSettings: { id: '${agwId}/backendHttpSettingsCollection/https-to-app-service' }
        }
      }
    ]
  }
}

// Categories listed explicitly: in Lesson 7, a categoryGroup setting delivered no rows.
resource agwDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${names.gateway}'
  scope: agw
  properties: {
    workspaceId: workspaceId
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      { category: 'ApplicationGatewayFirewallLog', enabled: true }
      { category: 'ApplicationGatewayAccessLog', enabled: true }
    ]
  }
}

// ---------- Front Door Standard (global) ----------
resource afd 'Microsoft.Cdn/profiles@2024-02-01' = {
  name: names.frontDoor
  location: 'global'
  tags: servicehubTags
  sku: { name: 'Standard_AzureFrontDoor' }
  properties: { originResponseTimeoutSeconds: 60 }
}

resource afdEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-02-01' = {
  parent: afd
  name: names.frontDoorEndpoint
  location: 'global'
  tags: servicehubTags
  properties: { enabledState: 'Enabled' }
}

resource afdOrigins 'Microsoft.Cdn/profiles/originGroups@2024-02-01' = {
  parent: afd
  name: 'servicehub-web'
  properties: {
    loadBalancingSettings: { sampleSize: 4, successfulSamplesRequired: 3, additionalLatencyInMilliseconds: 50 }
    healthProbeSettings: { probePath: '/', probeRequestType: 'HEAD', probeProtocol: 'Https', probeIntervalInSeconds: 100 }
    sessionAffinityState: 'Disabled'
  }
}

resource afdOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2024-02-01' = {
  parent: afdOrigins
  name: 'app-service'
  properties: { hostName: webHost, originHostHeader: webHost, httpPort: 80, httpsPort: 443, priority: 1, weight: 1000, enabledState: 'Enabled', enforceCertificateNameCheck: true }
}

resource afdRoute 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-02-01' = {
  parent: afdEndpoint
  name: 'default'
  properties: {
    originGroup: { id: afdOrigins.id }
    supportedProtocols: [ 'Http', 'Https' ]
    patternsToMatch: [ '/*' ]
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
  }
  dependsOn: [ afdOrigin ]
}

// Front Door Standard runs custom rules only; Microsoft's managed rule sets and bot protection
// need Premium. This rule blocks the paths scanners probe for. Front Door WAF policy names must be
// letters and digits only, so this one has no hyphens.
resource afdWaf 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2024-02-01' = {
  name: names.frontDoorWaf
  location: 'global'
  tags: servicehubTags
  sku: { name: 'Standard_AzureFrontDoor' }
  properties: {
    policySettings: { enabledState: 'Enabled', mode: 'Prevention', requestBodyCheck: 'Enabled', customBlockResponseStatusCode: 403 }
    customRules: {
      rules: [
        {
          name: 'BlockScannerProbes'
          enabledState: 'Enabled'
          priority: 100
          ruleType: 'MatchRule'
          action: 'Block'
          matchConditions: [ { matchVariable: 'RequestUri', operator: 'Contains', negateCondition: false, matchValue: [ '/.env', '/.git', '/wp-admin' ], transforms: [ 'Lowercase' ] } ]
        }
      ]
    }
  }
}

resource afdSecurity 'Microsoft.Cdn/profiles/securityPolicies@2024-02-01' = {
  parent: afd
  name: 'waf'
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: { id: afdWaf.id }
      associations: [ { domains: [ { id: afdEndpoint.id } ], patternsToMatch: [ '/*' ] } ]
    }
  }
}

resource afdDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${names.frontDoor}'
  scope: afd
  properties: {
    workspaceId: workspaceId
    logs: [
      { category: 'FrontDoorAccessLog', enabled: true }
      { category: 'FrontDoorWebApplicationFirewallLog', enabled: true }
    ]
  }
}

// ---------- Container Instances worker ----------
// In the VNet with a private IP only, pulling its image with a user-assigned managed identity
// (system-assigned identities can't pull images in Container Instances).
resource worker 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: names.containerGroup
  location: location
  tags: workerTags
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${pullIdentityId}': {} } }
  properties: {
    osType: 'Linux'
    sku: 'Standard'
    restartPolicy: 'Always'
    subnetIds: [ { id: aciSubnetId } ]
    ipAddress: { type: 'Private', ports: [ { port: 80, protocol: 'TCP' } ] }
    imageRegistryCredentials: [ { server: registryServer, identity: pullIdentityId } ]
    containers: [
      {
        name: 'status'
        properties: { image: '${registryServer}/servicehub/status:1.0', ports: [ { port: 80, protocol: 'TCP' } ], resources: { requests: { cpu: 1, memoryInGB: 1 } } }
      }
    ]
  }
}

var webHost = web.properties.defaultHostName

@description('Names, addresses and host names the web and container demos read back. No keys or secrets.')
output edge object = {
  webApp: web.name
  webHost: webHost
  gatewayIp: agwIp.properties.ipAddress
  frontDoorHost: afdEndpoint.properties.hostName
  frontDoorId: afd.properties.frontDoorId
  workerIp: worker.properties.ipAddress.ip
}
