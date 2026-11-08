// SC-500 Lesson 9, retained part: Contoso ServiceHub's application platform surfaces
// (resource group scope).
//
// Everything here costs little or nothing idle. The AKS cluster is stopped between takes, and the
// consumption-billed services (Container Apps, Flex Consumption Functions, a Consumption logic
// app, Consumption API Management) charge nothing while idle. The public edge (Application
// Gateway WAF, Front Door WAF), the App Service origin and the Container Instances worker are the
// bounded part in edge.bicep. Names come from config.json; each resource carries the common CAF
// tags plus its own workload and env.

@description('Azure region for every resource except the cluster.')
param location string

@description('Azure region for the AKS cluster.')
param aksLocation string

@description('Every resource name, from config.json.')
param names object

@description('Address plan, from config.json.')
param addressPlan object

@description('AKS node size, from config.json.')
param aksNodeSize string

@description('The operator workstation\'s public IPv4 address, for the allow lists. Never shown on slides.')
param operatorIp string

@description('Object ID of the operator (you), for the AKS data-plane role.')
param operatorObjectId string

@description('Microsoft Entra tenant ID.')
param tenantId string

@description('Application (client) ID of the lab API app registration that Deploy-L09Lab.ps1 creates or repairs.')
param apiAppId string

@description('The lab API\'s delegated scope.')
param apiScope string

@description('Built-in policy definition GUIDs.')
param policyDefinitions object

@description('API Management rate limit: calls per period.')
param rateLimitCalls int

@description('API Management rate limit period in seconds.')
param rateLimitPeriodSeconds int

@description('False on the first pass, before the images exist (the container app pulls an image, and AKS preflight reads the workspace); true afterward.')
param deployApps bool

@description('Common tags from config.json. Each resource adds its own workload and env, CAF\'s functional tags.')
param tags object

var platformTags = union(tags, { workload: 'appplatform', env: 'prod' })
var servicehubTags = union(tags, { workload: 'servicehub', env: 'prod' })
var statusTags = union(tags, { workload: 'status', env: 'prod' })
var partsTags = union(tags, { workload: 'partsapi', env: 'prod' })
var gatewayIdTags = union(tags, { workload: 'apigateway', env: 'prod' })
var intakeTags = union(tags, { workload: 'intake', env: 'prod' })
var operatorCidr = '${operatorIp}/32'
var apiAudience = 'api://${apiAppId}'

// Built-in role definition IDs.
var roleAcrPull = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var roleBlobOwner = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var roleQueueContributor = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
var roleAksRbacClusterAdmin = 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b'

// ---------- Shared: logs, identities, network ----------
resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: names.workspace
  location: location
  tags: platformTags
  properties: { sku: { name: 'PerGB2018' }, retentionInDays: 30 }
}

// User-assigned identities, so each role assignment exists before the resource that needs it.
resource pullId 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = { name: names.pullIdentity, location: location, tags: servicehubTags }
resource funcId 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = { name: names.functionIdentity, location: location, tags: partsTags }
resource apimId 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = { name: names.apimIdentity, location: location, tags: gatewayIdTags }

// The edge part's subnets live here so a bounded deployment only adds the costly pieces.
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: names.vnet
  location: location
  tags: platformTags
  properties: {
    addressSpace: { addressPrefixes: [ addressPlan.vnet ] }
    subnets: [
      { name: names.gatewaySubnet, properties: { addressPrefix: addressPlan.gateway } }
      {
        name: names.aciSubnet
        properties: {
          addressPrefix: addressPlan.aci
          delegations: [ { name: 'aci', properties: { serviceName: 'Microsoft.ContainerInstance/containerGroups' } } ]
        }
      }
    ]
  }
}

// ---------- 9.1 Containers ----------
// Basic tier: firewall rules and private endpoints need Premium, so this registry's controls are
// identity ones. No admin user (no shared password); pulls use managed identities with AcrPull.
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: names.registry
  location: location
  tags: servicehubTags
  sku: { name: 'Basic' }
  properties: { adminUserEnabled: false, anonymousPullEnabled: false, publicNetworkAccess: 'Enabled', zoneRedundancy: 'Disabled' }
}

resource pullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, pullId.id, roleAcrPull)
  scope: acr
  properties: { principalId: pullId.properties.principalId, principalType: 'ServicePrincipal', roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleAcrPull) }
}

// One 4-vCPU node: a 2-vCPU node ran out of schedulable CPU once the Defender sensor, Gatekeeper,
// and Cilium were running, and AKS guidance puts system pools at 4 vCPUs or more. Production runs
// at least two nodes; one is a lab economy. D4s_v3, because the lab subscription can't use the
// v5 sizes in eastus2 or centralus (NotAvailableForSubscription, November 1, 2026). The cluster's
// tags reach its node resource group and the load balancer, public IP, NSG and kubelet identity
// AKS puts there; the node pool's tags reach the scale set and its instances.
resource aks 'Microsoft.ContainerService/managedClusters@2024-09-01' = if (deployApps) {
  name: names.aks
  location: aksLocation
  tags: servicehubTags
  sku: { name: 'Base', tier: 'Free' }
  identity: { type: 'SystemAssigned' }
  properties: {
    dnsPrefix: names.aks
    nodeResourceGroup: names.aksNodeResourceGroup
    enableRBAC: true
    // Microsoft Entra ID with Azure RBAC, and no local accounts: every kubectl call is a named
    // Entra identity with an Azure role, and there's no static cluster-admin credential.
    disableLocalAccounts: true
    aadProfile: { managed: true, enableAzureRBAC: true, tenantID: tenantId }
    apiServerAccessProfile: { authorizedIPRanges: [ operatorCidr ] }
    agentPoolProfiles: [
      {
        name: 'systemd4'
        mode: 'System'
        count: 1
        vmSize: aksNodeSize
        osType: 'Linux'
        osSKU: 'AzureLinux'
        osDiskSizeGB: 64
        type: 'VirtualMachineScaleSets'
        tags: servicehubTags
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkDataplane: 'cilium'
      networkPolicy: 'cilium'
      podCidr: '10.244.0.0/16'
      serviceCidr: '10.95.0.0/16'
      dnsServiceIP: '10.95.0.10'
    }
    oidcIssuerProfile: { enabled: true }
    securityProfile: {
      // The Defender for Containers sensor, set explicitly rather than left to autoprovisioning.
      defender: { logAnalyticsWorkspaceResourceId: law.id, securityMonitoring: { enabled: true } }
      workloadIdentity: { enabled: true }
      imageCleaner: { enabled: true, intervalHours: 168 }
    }
    // Azure Policy for Kubernetes: the Gatekeeper admission controller that enforces the deny below.
    addonProfiles: { azurepolicy: { enabled: true } }
    autoUpgradeProfile: { upgradeChannel: 'patch', nodeOSUpgradeChannel: 'NodeImage' }
  }
}

resource kubeletPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployApps) {
  name: guid(acr.id, aks.id, roleAcrPull)
  scope: acr
  properties: { principalId: aks.properties.identityProfile.kubeletidentity.objectId, principalType: 'ServicePrincipal', roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleAcrPull) }
}

// Data-plane access for the operator, through Azure RBAC rather than a kubeconfig secret.
resource operatorAks 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployApps) {
  name: guid(aks.id, operatorObjectId, roleAksRbacClusterAdmin)
  scope: aks
  properties: { principalId: operatorObjectId, principalType: 'User', roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleAksRbacClusterAdmin) }
}

// Gated deployment: Gatekeeper refuses privileged pods anywhere in this group's clusters.
resource noPrivileged 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: names.privilegedPolicy
  properties: {
    displayName: 'Contoso app platform: Kubernetes clusters must not run privileged containers (Deny)'
    policyDefinitionId: tenantResourceId('Microsoft.Authorization/policyDefinitions', policyDefinitions.noPrivilegedContainers)
    parameters: { effect: { value: 'Deny' } }
    enforcementMode: 'Default'
  }
}

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: names.containerEnv
  location: location
  tags: servicehubTags
  properties: {
    appLogsConfiguration: { destination: 'log-analytics', logAnalyticsConfiguration: { customerId: law.properties.customerId, sharedKey: law.listKeys().primarySharedKey } }
    workloadProfiles: [ { name: 'Consumption', workloadProfileType: 'Consumption' } ]
    zoneRedundant: false
  }
}

// HTTPS only, reachable only from the operator's address, and pulling its image with a managed
// identity instead of a registry password. Scales to zero between requests.
resource statusApp 'Microsoft.App/containerApps@2024-03-01' = if (deployApps) {
  name: names.containerApp
  location: location
  tags: statusTags
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${pullId.id}': {} } }
  properties: {
    environmentId: cae.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 80
        transport: 'auto'
        allowInsecure: false
        ipSecurityRestrictions: [ { name: 'allow-operator', description: 'Operator workstation only', ipAddressRange: operatorCidr, action: 'Allow' } ]
      }
      registries: [ { server: acr.properties.loginServer, identity: pullId.id } ]
    }
    template: {
      containers: [ { name: 'status', image: '${acr.properties.loginServer}/servicehub/status:1.0', resources: { cpu: json('0.25'), memory: '0.5Gi' } } ]
      scale: { minReplicas: 0, maxReplicas: 1 }
    }
  }
  dependsOn: [ pullRole ]
}

// ---------- 9.2 Serverless ----------
// The function's storage takes no account keys: the host and the deployment package both use the
// function's managed identity. Defender for Storage is Free on the lab subscription, so the
// September build's per-account Defender override isn't needed here.
resource st 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: names.storage
  location: location
  tags: partsTags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource blobs 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = { parent: st, name: 'default' }
resource packages 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = { parent: blobs, name: 'app-package' }

resource funcBlob 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(st.id, funcId.id, roleBlobOwner)
  scope: st
  properties: { principalId: funcId.properties.principalId, principalType: 'ServicePrincipal', roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleBlobOwner) }
}

resource funcQueue 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(st.id, funcId.id, roleQueueContributor)
  scope: st
  properties: { principalId: funcId.properties.principalId, principalType: 'ServicePrincipal', roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleQueueContributor) }
}

resource funcPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: names.functionPlan
  location: location
  tags: partsTags
  kind: 'functionapp'
  sku: { name: 'FC1', tier: 'FlexConsumption' }
  properties: { reserved: true }
}

resource func 'Microsoft.Web/sites@2024-04-01' = {
  name: names.functionApp
  location: location
  tags: partsTags
  kind: 'functionapp,linux'
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${funcId.id}': {} } }
  properties: {
    serverFarmId: funcPlan.id
    httpsOnly: true
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${st.properties.primaryEndpoints.blob}app-package'
          authentication: { type: 'UserAssignedIdentity', userAssignedIdentityResourceId: funcId.id }
        }
      }
      runtime: { name: 'powershell', version: '7.4' }
      scaleAndConcurrency: { maximumInstanceCount: 40, instanceMemoryMB: 512 }
    }
    siteConfig: {
      minTlsVersion: '1.2'
      http20Enabled: true
      appSettings: [
        { name: 'AzureWebJobsStorage__accountName', value: st.name }
        { name: 'AzureWebJobsStorage__credential', value: 'managedidentity' }
        { name: 'AzureWebJobsStorage__clientId', value: funcId.properties.clientId }
      ]
    }
  }
  dependsOn: [ funcBlob, funcQueue, packages ]
}

// No FTP or basic-auth publishing: deployments use Microsoft Entra identities.
resource funcFtp 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = { parent: func, name: 'ftp', properties: { allow: false } }
resource funcScm 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = { parent: func, name: 'scm', properties: { allow: false } }

// App Service Authentication (Easy Auth): a request without a valid token for the ServiceHub API
// gets 401 before any code runs, and a valid token from any client but API Management's identity
// gets 403.
resource funcAuth 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: func
  name: 'authsettingsV2'
  properties: {
    platform: { enabled: true }
    globalValidation: { requireAuthentication: true, unauthenticatedClientAction: 'Return401' }
    httpSettings: { requireHttps: true }
    login: { tokenStore: { enabled: false } }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: { clientId: apiAppId, openIdIssuer: 'https://sts.windows.net/${tenantId}/v2.0' }
        validation: {
          allowedAudiences: [ apiAudience, apiAppId ]
          defaultAuthorizationPolicy: { allowedApplications: [ apimId.properties.clientId ] }
        }
      }
    }
  }
}

// Consumption logic app: SAS turned off, so the only way in is a Microsoft Entra token for the
// ServiceHub API, from the operator's address. Trigger data is hidden in run history, and run
// history content is readable only from the same address.
resource intake 'Microsoft.Logic/workflows@2019-05-01' = {
  name: names.logicApp
  location: location
  tags: intakeTags
  identity: { type: 'SystemAssigned' }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: { method: 'POST', schema: { type: 'object', properties: { partId: { type: 'string' } } } }
          runtimeConfiguration: { secureData: { properties: [ 'inputs', 'outputs' ] } }
        }
      }
      actions: {
        Respond: {
          type: 'Response'
          kind: 'Http'
          runAfter: {}
          inputs: { statusCode: 200, headers: { 'Content-Type': 'application/json' }, body: { workflow: 'servicehub-intake', accepted: '@{triggerBody()?[\'partId\']}' } }
        }
      }
    }
    accessControl: {
      triggers: {
        allowedCallerIpAddresses: [ { addressRange: operatorCidr } ]
        openAuthenticationPolicies: {
          policies: {
            servicehub: {
              type: 'AAD'
              claims: [
                { name: 'iss', value: 'https://sts.windows.net/${tenantId}/' }
                { name: 'aud', value: apiAudience }
              ]
            }
          }
        }
        sasAuthenticationPolicy: { state: 'Disabled' }
      }
      contents: { allowedCallerIpAddresses: [ { addressRange: operatorCidr } ] }
    }
  }
}

// ---------- 9.4 API Management ----------
resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: names.apim
  location: location
  tags: servicehubTags
  sku: { name: 'Consumption', capacity: 0 }
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${apimId.id}': {} } }
  properties: { publisherEmail: '<your-admin-upn>', publisherName: 'Contoso ServiceHub' }
}

resource partsApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: 'servicehub-parts'
  properties: {
    displayName: 'ServiceHub parts'
    path: 'servicehub'
    protocols: [ 'https' ]
    serviceUrl: 'https://${func.properties.defaultHostName}/api'
    subscriptionRequired: true
    subscriptionKeyParameterNames: { header: 'Ocp-Apim-Subscription-Key', query: 'subscription-key' }
  }
}

resource getPart 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: partsApi
  name: 'get-part'
  properties: {
    displayName: 'Get a part'
    method: 'GET'
    urlTemplate: '/parts/{partId}'
    templateParameters: [ { name: 'partId', type: 'string', required: true } ]
  }
}

// Inbound order matters: prove the caller (Microsoft Entra token for the ServiceHub API), limit
// how often that subscription can call, drop the caller's token, then call the back end as API
// Management's own managed identity. The back end trusts only that identity.
var partsPolicy = '''
<policies>
  <inbound>
    <base />
    <validate-azure-ad-token tenant-id="{0}" header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="A ServiceHub access token is required.">
      <audiences>
        <audience>{1}</audience>
      </audiences>
      <required-claims>
        <claim name="scp" match="any">
          <value>{2}</value>
        </claim>
      </required-claims>
    </validate-azure-ad-token>
    <rate-limit calls="{3}" renewal-period="{4}" remaining-calls-header-name="x-ratelimit-remaining" />
    <set-header name="Authorization" exists-action="delete" />
    <authentication-managed-identity resource="{1}" client-id="{5}" />
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
    <set-header name="X-Powered-By" exists-action="delete" />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''

resource partsPolicyRes 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: partsApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: format(partsPolicy, tenantId, apiAudience, apiScope, rateLimitCalls, rateLimitPeriodSeconds, apimId.properties.clientId)
  }
}

resource labSubscription 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = {
  parent: apim
  name: 'servicehub-lab'
  properties: { displayName: 'ServiceHub lab caller', scope: '/apis/${partsApi.name}', state: 'active', allowTracing: false }
}

@description('Names, IDs and endpoints the lesson scripts read back. No keys, tokens or SAS values.')
output lab object = {
  resourceGroup: resourceGroup().name
  workspaceId: law.id
  registry: acr.name
  registryServer: acr.properties.loginServer
  pullIdentityId: pullId.id
  pullIdentityClientId: pullId.properties.clientId
  aks: names.aks
  aksLocation: aksLocation
  aksNodeResourceGroup: names.aksNodeResourceGroup
  containerApp: deployApps ? statusApp.name : ''
  containerAppFqdn: deployApps ? statusApp!.properties.configuration.ingress.fqdn : ''
  storage: st.name
  functionApp: func.name
  functionHost: func.properties.defaultHostName
  logicApp: intake.name
  apim: apim.name
  apimGateway: apim.properties.gatewayUrl
  apimIdentityClientId: apimId.properties.clientId
  apiAudience: apiAudience
  vnetId: vnet.id
}
