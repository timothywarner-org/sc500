<#
.SYNOPSIS
    Read-only readiness check for the Lesson 7 lab at CTSO-L07-BASELINE.

.DESCRIPTION
    PASS means the check matches the baseline the demos start from. WARN means something costs
    money or needs attention before the demo but doesn't break the baseline (a running VM, a
    firewall that still exists, a DNAT source that's no longer your IP). FAIL means a demo
    would start from the wrong state. Reset repairs policy drift; failed extensions require
    working egress and agent diagnosis. Changes nothing.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Test-L07Lab.ps1
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L07.Common.ps1')
[void](Assert-L07Context)
$cfg = $script:L07Config
$lab = Get-L07DeploymentOutput
$rg = $cfg.resourceGroup
$n = $cfg.names
$checks = [Collections.Generic.List[object]]::new()
function Add-Check([string]$Name, $Expected, $Actual, [switch]$WarnOnly) {
    $ok = "$Expected" -eq "$Actual"
    $checks.Add([pscustomobject]@{ Result = if ($ok) { 'PASS' } elseif ($WarnOnly) { 'WARN' } else { 'FAIL' }; Check = $Name; Expected = "$Expected"; Actual = "$Actual" })
}

$group = Invoke-L07Az @('group', 'show', '--name', $rg)
Add-Check 'Resource group tag managedBy' $cfg.managedBy $group.tags.managedBy

# Check the intended spoke/default-route shape; actual next-hop evidence remains a demo check.
$hub = Invoke-L07Az @('network', 'vnet', 'show', '--resource-group', $rg, '--name', $n.hubVnet)
$fwSubnet = @($hub.subnets | Where-Object name -eq 'AzureFirewallSubnet')
Add-Check 'AzureFirewallSubnet prefix (minimum /26)' $cfg.addressPlan.hubFirewall $(if ($fwSubnet.Count) { $fwSubnet[0].addressPrefix } else { 'missing' })
foreach ($p in $n.hubToProd, $n.hubToNonprod) {
    $peer = @($hub.virtualNetworkPeerings | Where-Object name -eq $p)
    Add-Check "$p connected, forwarded traffic allowed" 'Connected True' $(if ($peer.Count) { "$($peer[0].peeringState) $($peer[0].allowForwardedTraffic)" } else { 'missing' })
}
foreach ($spoke in @(@{ v = $n.prodVnet; s = $n.appSubnet; rt = $n.prodRouteTable }, @{ v = $n.nonprodVnet; s = $n.appSubnet; rt = $n.nonprodRouteTable })) {
    $vnet = Invoke-L07Az @('network', 'vnet', 'show', '--resource-group', $rg, '--name', $spoke.v)
    $sub = @($vnet.subnets | Where-Object name -eq $spoke.s)[0]
    Add-Check "$($spoke.v)/$($spoke.s) is private (no default outbound access)" 'False' (Get-L07Value $sub 'defaultOutboundAccess')
    Add-Check "$($spoke.v)/$($spoke.s) route table" $spoke.rt ((Get-L07Value $sub 'routeTable.id') -split '/')[-1]
    Add-Check "$($spoke.v) peerings (hub only)" 1 @($vnet.virtualNetworkPeerings).Count
    $rt = Invoke-L07Az @('network', 'route-table', 'show', '--resource-group', $rg, '--name', $spoke.rt)
    $default = @($rt.routes | Where-Object addressPrefix -eq '0.0.0.0/0')
    Add-Check "$($spoke.rt) sends 0.0.0.0/0 to the firewall" "VirtualAppliance $($cfg.addressPlan.hosts.firewall)" $(if ($default.Count) { "$($default[0].nextHopType) $($default[0].nextHopIpAddress)" } else { 'missing' })
}
$prodNsg = Invoke-L07Az @('network', 'nsg', 'show', '--resource-group', $rg, '--name', $n.prodNsg)
Add-Check "$($n.prodNsg) custom rules" 'allow-app-from-firewall deny-all-other-inbound' ((@($prodNsg.securityRules | Sort-Object priority | ForEach-Object name)) -join ' ')
$nonprodNsg = Invoke-L07Az @('network', 'nsg', 'show', '--resource-group', $rg, '--name', $n.nonprodNsg)
Add-Check "$($n.nonprodNsg) custom rules (baseline: defaults only)" 0 @($nonprodNsg.securityRules).Count

# Key Vault and the inspection CA.
$kv = Invoke-L07Az @('keyvault', 'show', '--resource-group', $rg, '--name', $lab.keyVaultName)
$kvDiag = @(Invoke-L07Az @('monitor', 'diagnostic-settings', 'list', '--resource', $kv.id))
Add-Check 'Key Vault audit logs go to the lesson workspace' $n.keyVaultDiagnostics $(if ($kvDiag.Count) { @($kvDiag | ForEach-Object name) -join ',' } else { 'missing' })
Add-Check 'Key Vault uses Azure RBAC' 'True' $kv.properties.enableRbacAuthorization
Add-Check 'Key Vault firewall default action / bypass' 'Deny AzureServices' "$($kv.properties.networkAcls.defaultAction) $($kv.properties.networkAcls.bypass)"
$caPath = Join-Path $script:L07State 'inspection-ca-public.json'
$ca = if (Test-Path -LiteralPath $caPath) { Get-Content -LiteralPath $caPath -Raw | ConvertFrom-Json } else { $null }
$cert = $null
try { $cert = Get-L07InspectionCaCertificate -VaultUri $lab.keyVaultUri } catch { $cert = $null }
Add-Check 'Inspection CA certificate in Key Vault' 'present' $(if ($cert) { 'present' } else { 'missing or unreadable from this IP' })
if ($cert) {
    $exp = [DateTimeOffset]::FromUnixTimeSeconds([int64]$cert.attributes.exp).UtcDateTime
    Add-Check 'Inspection CA valid at least a year forward' 'True' ($exp -gt [DateTime]::UtcNow.AddDays(365))
    $thumb = [BitConverter]::ToString([Convert]::FromBase64String(($cert.x5t -replace '-', '+' -replace '_', '/').PadRight([math]::Ceiling($cert.x5t.Length / 4) * 4, '='))) -replace '-', ''
    Add-Check 'Key Vault CA matches the CA the VMs trust' "$($ca.interThumbprint)" $thumb
}

# Firewall policy at baseline.
$policy = Invoke-L07Az @('resource', 'show', '--resource-group', $rg, '--resource-type', 'Microsoft.Network/firewallPolicies', '--name', $n.firewallPolicy)
$pp = $policy.properties
Add-Check 'Policy tier' 'Premium' (Get-L07Value $pp 'sku.tier')
Add-Check 'Threat intelligence mode (baseline: Alert)' 'Alert' $pp.threatIntelMode
Add-Check 'IDPS mode (baseline: Alert)' 'Alert' (Get-L07Value $pp 'intrusionDetection.mode')
Add-Check 'IDPS signature overrides (baseline: none)' 0 @(Get-L07Value $pp 'intrusionDetection.configuration.signatureOverrides').Count
Add-Check 'TLS inspection CA secret' "$(if ($cert) { $cert.sid } else { 'n/a' })" (Get-L07Value $pp 'transportSecurity.certificateAuthority.keyVaultSecretId')
# Rule collection groups are child resources, which a resource-group listing doesn't return, so
# read each expected group by ID.
$applicationGroup = $null
$rcgText = @(foreach ($name in 'rcg-application', 'rcg-dnat', 'rcg-network') {
        $d = Invoke-L07Az -AllowFailure @('resource', 'show', '--ids', "$($policy.id)/ruleCollectionGroups/$name")
        if ($d.ExitCode -eq 0) {
            $g = $d.Stdout | ConvertFrom-Json
            if ($name -eq 'rcg-application') { $applicationGroup = $g }
            "$($g.name)=$($g.properties.priority)"
        } else { "$name=missing" }
    })
Add-Check 'Rule collection groups and priorities' 'rcg-application=300 rcg-dnat=100 rcg-network=200' ($rcgText -join ' ')
# A previously successful installation must not hide a policy that blocks ongoing protection.
$appRules = @((Get-L07Value $applicationGroup 'properties.ruleCollections') | ForEach-Object rules)
foreach ($ruleName in 'allow-defender-without-tls-inspection','allow-defender-installer-host') {
    $rule = @($appRules | Where-Object name -eq $ruleName)
    $valid = $rule.Count -eq 1 -and (Get-L07Value $rule[0] 'terminateTLS') -eq $false -and
        ((@($rule[0].sourceAddresses | Sort-Object) -join ',') -eq (@($cfg.addressPlan.hosts.prodApp,$cfg.addressPlan.hosts.nonprodApp | Sort-Object) -join ','))
    Add-Check "$ruleName is uninspected and scoped to both guests" 'True' $valid
}
$installer = @($appRules | Where-Object name -eq 'allow-defender-installer-host')
Add-Check 'Defender installer hostname is explicitly allowed' 'raw.githubusercontent.com' $(if ($installer.Count -eq 1) { @($installer[0].targetFqdns) -join ',' } else { 'missing' })
$dnat = Invoke-L07Az @('resource', 'show', '--ids', "$($policy.id)/ruleCollectionGroups/rcg-dnat")
$dnatSource = @($dnat.properties.ruleCollections[0].rules[0].sourceAddresses) -join ','
Add-Check 'DNAT source is your current public IP' (Get-L07OperatorIp) $dnatSource -WarnOnly
Add-Check 'DNAT destination is the firewall public IP' $lab.firewallPublicIpAddress (@($dnat.properties.ruleCollections[0].rules[0].destinationAddresses) -join ',')

# VMs, public IP, and the bounded firewall.
foreach ($vmName in $n.prodVm, $n.nonprodVm) {
    $vm = Invoke-L07Az @('vm', 'show', '--resource-group', $rg, '--name', $vmName, '--show-details')
    Add-Check "$vmName has no public IP" '' "$(Get-L07Value $vm 'publicIps')"
    Add-Check "$vmName power state" 'VM deallocated' $vm.powerState -WarnOnly
    $extensions = @(Invoke-L07Az @('vm', 'extension', 'list', '--resource-group', $rg, '--vm-name', $vmName))
    $mde = @($extensions | Where-Object name -eq 'MDE.Linux')
    # Lesson 7 doesn't teach Defender. If Defender for Servers provisions MDE.Linux in this
    # subscription, it must have succeeded (its egress rules are in the policy); if the plan is off,
    # there's no extension and nothing to check.
    if ($mde.Count -eq 1) { Add-Check "$vmName Defender extension (provisioned by the plan)" 'Succeeded' $mde[0].provisioningState }
    else { Add-Check "$vmName Defender extension (plan not provisioning it)" 'absent' 'absent' }
    $shutdown = Invoke-L07Az -AllowFailure @('resource', 'show', '--resource-group', $rg, '--resource-type', 'Microsoft.DevTestLab/schedules', '--name', "shutdown-computevm-$vmName")
    $shutdownState = if ($shutdown.ExitCode -eq 0) { "$(($shutdown.Stdout | ConvertFrom-Json).properties.status)" } else { 'missing' }
    Add-Check "$vmName auto-shutdown $($cfg.autoShutdown.time) $($cfg.autoShutdown.timeZoneId)" $(if ($cfg.autoShutdown.enabled) { 'Enabled' } else { 'missing' }) $shutdownState
    $unfinished = @($extensions | Where-Object provisioningState -ne 'Succeeded')
    Add-Check "$vmName unfinished extensions" 0 $unfinished.Count
}
$pip = Invoke-L07Az @('network', 'public-ip', 'show', '--resource-group', $rg, '--name', $n.firewallPublicIp)
Add-Check 'Firewall public IP is Standard and static' 'Standard Static' "$($pip.sku.name) $($pip.publicIPAllocationMethod)"
$fw = Get-L07Firewall
Add-Check 'Bounded firewall absent (not billing about 1.75 USD an hour)' 'absent' $(if ($fw) { 'present' } else { 'absent' }) -WarnOnly
Add-Check 'DDoS IP Protection restored to inherited baseline' 'VirtualNetworkInherited' (Get-L07Value $pip 'ddosSettings.protectionMode')
Add-Check 'No paid DDoS Network Protection plan on hub' 'False' ([bool](Get-L07Value $hub 'enableDdosProtection'))
$nw = @(Invoke-L07Az -NoSubscription @('network', 'watcher', 'list', '--subscription', $cfg.subscriptionId) | Where-Object location -eq $cfg.location)
Add-Check "Network Watcher enabled in $($cfg.location)" 'Succeeded' $(if ($nw.Count) { $nw[0].provisioningState } else { 'missing' })

# Cloud Adoption Framework hygiene: every resource carries the course owner tag and its own
# workload and env tags, and the group has its budget.
$untagged = @(Invoke-L07Az @('resource', 'list', '--resource-group', $rg)) | Where-Object {
    -not ("$(Get-L07Value $_ 'tags.managedby')" -eq $cfg.managedBy -and (Get-L07Value $_ 'tags.workload') -and (Get-L07Value $_ 'tags.env'))
}
Add-Check 'Every resource tagged managedby, workload and env' 'none missing' $(if ($untagged) { (@($untagged | ForEach-Object name) -join ', ') } else { 'none missing' })
if ($cfg.budget.enabled) {
    $budget = Invoke-L07Az -AllowFailure @('consumption', 'budget', 'show', '--budget-name', $n.budget, '--resource-group', $rg)
    Add-Check "Budget $($n.budget) ($($cfg.budget.monthlyAmountUsd) USD a month)" 'present' $(if ($budget.ExitCode -eq 0) { 'present' } else { 'missing' })
}

[void](Write-L07Evidence 'readiness' $checks)
$fails = @($checks | Where-Object Result -eq 'FAIL').Count
$warns = @($checks | Where-Object Result -eq 'WARN').Count
if ($fails) { "NOT READY: $fails check(s) failed. Reset fixes policy drift. Failed extensions require working egress and agent diagnosis; redeployment is not a blanket repair." }
else { "BASELINE CHECK PASSED: $($cfg.baseline) ($warns warning(s)). This doesn't prove the firewall's traffic results; run the demos for that." }
$checks | Format-Table -AutoSize | Out-String -Width 220
if ($fails) { exit 1 }
