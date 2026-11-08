// SC-500 Lesson 7 firewall policy (retained), afwp-hub-shared-eastus2-001 in config.json. A policy with zero or one firewall association is
// free, so it stays deployed between sessions and the portal can show every setting while the
// firewall itself (bounded, about 1.75 USD an hour) doesn't exist.
//
// Rule processing, as Microsoft documents it: threat intelligence is checked before any rule.
// Then rule collection groups run in priority order, but inside that order DNAT always goes
// first, then network rules, then application rules. Rules are terminating, and anything no rule
// allows is denied. IDPS in Alert and deny mode runs inline after the rules.
//
// Baseline (CTSO-L07-BASELINE): threat intelligence and IDPS both in Alert mode, which is
// Microsoft's default for threat intelligence. Demo 7.1 raises both to Alert and deny.

@description('Azure region.')
param location string

@description('Common tags from config.json, plus policyState from Set-L07Policy.ps1.')
param tags object

@description('Every resource name, from config.json.')
param names object

@description('Address plan, from config.json.')
param addressPlan object

@description('Listener ports, from config.json.')
param ports object

@description('Probe targets and IDPS test values, from config.json.')
param tests object

@description('Resource ID of the firewall\'s user-assigned identity, which reads the CA secret.')
param firewallIdentityId string

@description('Versioned secret ID of the inspection CA (Key Vault creates the secret when the certificate is imported).')
#disable-next-line secure-secrets-in-params // A Key Vault secret URI, an identifier the firewall dereferences with its own identity; it carries no key material.
param inspectionCaSecretId string

@description('The operator\'s current public IPv4 address, the only DNAT source.')
param operatorPublicIp string

@description('The retained firewall public IP address, the DNAT destination.')
param firewallPublicIpAddress string

@description('Threat intelligence mode. Alert is the baseline; Deny is Alert and deny.')
@allowed(['Alert', 'Deny'])
param threatIntelMode string = 'Alert'

@description('IDPS mode. Alert is the baseline; Deny is Alert and deny.')
@allowed(['Alert', 'Deny'])
param idpsMode string = 'Alert'

@description('Mode for the HaxerMen test signature. Empty leaves it on the policy mode.')
@allowed(['', 'Alert', 'Deny'])
param idpsTestSignatureMode string = ''

resource policy 'Microsoft.Network/firewallPolicies@2024-05-01' = {
  name: names.firewallPolicy
  location: location
  tags: union(tags, { workload: 'hub', env: 'shared' })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${firewallIdentityId}': {} }
  }
  properties: {
    sku: { tier: 'Premium' }
    threatIntelMode: threatIntelMode
    intrusionDetection: {
      mode: idpsMode
      configuration: {
        signatureOverrides: empty(idpsTestSignatureMode) ? [] : [
          { id: tests.idpsTestSignatureId, mode: idpsTestSignatureMode }
        ]
      }
    }
    // TLS inspection: the firewall re-signs inspected sessions with this intermediate CA, which
    // it reads from Key Vault through the Secrets interface as the user-assigned identity.
    transportSecurity: {
      certificateAuthority: {
        name: names.inspectionCaCertificate
        keyVaultSecretId: inspectionCaSecretId
      }
    }
  }
}

// DNAT: publish production's status page on the firewall's public IP, to the operator only.
// A DNAT rule adds an implicit allow, which is why its source should never be a wildcard.
resource dnat 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-05-01' = {
  parent: policy
  name: 'rcg-dnat'
  properties: {
    priority: 100
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyNatRuleCollection'
        name: 'dnat-servicehub-status'
        priority: 100
        action: { type: 'Dnat' }
        rules: [
          {
            ruleType: 'NatRule'
            name: 'status-page-from-operator'
            ipProtocols: ['TCP']
            sourceAddresses: [operatorPublicIp]
            destinationAddresses: [firewallPublicIpAddress]
            destinationPorts: [string(ports.app)]
            translatedAddress: addressPlan.hosts.prodApp
            translatedPort: string(ports.app)
          }
        ]
      }
    ]
  }
}

// Network rules: say the segmentation out loud. The default deny would drop this traffic anyway,
// but an explicit deny puts the rule's name in every log line.
resource network 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-05-01' = {
  parent: policy
  name: 'rcg-network'
  dependsOn: [dnat]
  properties: {
    priority: 200
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'net-deny-cross-environment'
        priority: 100
        action: { type: 'Deny' }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'deny-prod-to-nonprod'
            ipProtocols: ['Any']
            sourceAddresses: [addressPlan.prod]
            destinationAddresses: [addressPlan.nonprod]
            destinationPorts: ['*']
          }
          {
            ruleType: 'NetworkRule'
            name: 'deny-nonprod-to-prod'
            ipProtocols: ['Any']
            sourceAddresses: [addressPlan.nonprod]
            destinationAddresses: [addressPlan.prod]
            destinationPorts: ['*']
          }
        ]
      }
    ]
  }
}

// Application rules: the workload URL is inspected. Both guests also need explicitly named
// operating-system and Defender destinations. Defender does not support TLS interception.
// The threat intelligence test FQDN has an allow rule so the
// log proves threat intelligence acts before any allow rule.
resource application 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-05-01' = {
  parent: policy
  name: 'rcg-application'
  dependsOn: [network]
  properties: {
    priority: 300
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'app-allow-prod-egress'
        priority: 100
        action: { type: 'Allow' }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'allow-firewall-docs-inspected'
            sourceAddresses: [addressPlan.prod]
            protocols: [{ protocolType: 'Https', port: 443 }]
            targetUrls: [tests.allowedUrl]
            terminateTLS: true
          }
          {
            ruleType: 'ApplicationRule'
            name: 'allow-threat-intel-test-fqdn'
            sourceAddresses: [addressPlan.prod]
            protocols: [{ protocolType: 'Http', port: 80 }]
            targetFqdns: [tests.threatIntelTestFqdn]
          }
        ]
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'app-allow-os-updates'
        priority: 200
        action: { type: 'Allow' }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'allow-ubuntu-mirrors'
            sourceAddresses: [addressPlan.prod, addressPlan.nonprod]
            protocols: [{ protocolType: 'Http', port: 80 }, { protocolType: 'Https', port: 443 }]
            targetFqdns: ['azure.archive.ubuntu.com', 'security.ubuntu.com', 'archive.ubuntu.com']
          }
        ]
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'app-allow-platform-egress'
        priority: 300
        action: { type: 'Allow' }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'allow-defender-without-tls-inspection'
            sourceAddresses: [addressPlan.hosts.prodApp, addressPlan.hosts.nonprodApp]
            protocols: [{ protocolType: 'Https', port: 443 }]
            // Microsoft's Linux prerequisites and streamlined URL list govern these endpoints.
            // Keep this separate from the inspected workload rule so security agents can connect.
            targetFqdns: [
              'packages.microsoft.com'
              'msdefender.download.prss.microsoft.com'
              '*.endpoint.security.microsoft.com'
              'config.edge.skype.com'
              'go.microsoft.com'
              'definitionupdates.microsoft.com'
              'www.microsoft.com'
              '*.download.microsoft.com'
              '*.wdcp.microsoft.com'
              'wdcp.microsoft.com'
              '*.wd.microsoft.com'
              '*.wdcpalt.microsoft.com'
              'wdcpalt.microsoft.com'
              'nf.smartscreen.microsoft.com'
              'unitedstates.smartscreen.microsoft.com'
            ]
            terminateTLS: false
          }
          {
            ruleType: 'ApplicationRule'
            name: 'allow-defender-installer-host'
            sourceAddresses: [addressPlan.hosts.prodApp, addressPlan.hosts.nonprodApp]
            protocols: [{ protocolType: 'Https', port: 443 }]
            // MDE.Linux retrieves Microsoft's mdatp-xplat installer from this shared host.
            // Without TLS interception, an FQDN rule cannot restrict the repository path.
            // Keep the exception limited to these two managed lab guests, not the subnet.
            targetFqdns: ['raw.githubusercontent.com']
            terminateTLS: false
          }
          {
            ruleType: 'ApplicationRule'
            name: 'allow-ubuntu-contract-service'
            sourceAddresses: [addressPlan.hosts.prodApp, addressPlan.hosts.nonprodApp]
            protocols: [{ protocolType: 'Https', port: 443 }]
            targetFqdns: ['contracts.canonical.com']
          }
        ]
      }
    ]
  }
}

@description('The policy\'s resource ID.')
output policyId string = policy.id
@description('Threat intelligence mode as deployed.')
output threatIntelMode string = policy.properties.threatIntelMode
@description('IDPS mode as deployed.')
output idpsMode string = policy.properties.intrusionDetection.mode
