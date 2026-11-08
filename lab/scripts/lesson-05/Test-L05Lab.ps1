<#
.SYNOPSIS
    Read-only readiness check: is the retained Lesson 5 lab at CTSO-L05-BASELINE?

.DESCRIPTION
    Checks what the demos depend on and prints one PASS, WARN, or FAIL row per check, then
    saves a readiness evidence file. It changes nothing. Exit code 1 when anything FAILs.
    WARN means "works, but look": for example, a bounded lab that is still billing.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-05\Test-L05Lab.ps1
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L05.Common.ps1')
[void](Assert-L05Context)
$cfg = $script:L05Config
$rg = $cfg.resourceGroup
$checks = [Collections.Generic.List[object]]::new()
function Add-Check {
    param([string]$Check, $Expected, $Actual, [ValidateSet('FAIL', 'WARN')][string]$Otherwise = 'FAIL')
    $ok = "$Actual" -eq "$Expected"
    $checks.Add([pscustomobject]@{ Result = if ($ok) { 'PASS' } else { $Otherwise }; Check = $Check; Expected = "$Expected"; Actual = "$Actual" })
}

$lab = Get-L05Outputs
$rgInfo = Invoke-L05Az @('group', 'show', '--name', $rg)
Add-Check 'Resource group tag managedBy' $cfg.managedBy $rgInfo.tags.managedBy

# Segmentation baseline (demo 5.1 starting fault)
$nsg = Invoke-L05Az @('network', 'nsg', 'show', '--resource-group', $rg, '--name', 'nsg-servicehub')
Add-Check 'nsg-servicehub custom rules (baseline fault: defaults only)' 0 @($nsg.securityRules).Count
Add-Check 'nsg-servicehub associated with snet-servicehub' 'snet-servicehub' ((@($nsg.subnets)[0].id -split '/')[-1])
foreach ($tier in 'web', 'app', 'data') {
    $nic = Invoke-L05Az @('network', 'nic', 'show', '--resource-group', $rg, '--name', "nic-vm-servicehub-$tier")
    Add-Check "nic-vm-servicehub-$tier ASG" "asg-servicehub-$tier" ((@($nic.ipConfigurations[0].applicationSecurityGroups)[0].id -split '/')[-1])
    Add-Check "nic-vm-servicehub-$tier has no public IP" 'False' ([bool](Get-L05Value $nic.ipConfigurations[0] 'publicIPAddress'))
}
foreach ($v in @(@('vnet-sc500-l05-servicehub', 'snet-servicehub'), @('vnet-sc500-l05-hub', 'snet-management'))) {
    $s = Invoke-L05Az @('network', 'vnet', 'subnet', 'show', '--resource-group', $rg, '--vnet-name', $v[0], '--name', $v[1])
    Add-Check "$($v[1]) is private (no default outbound access)" 'False' $s.defaultOutboundAccess
}
foreach ($peer in @(@('vnet-sc500-l05-hub', 'peer-hub-to-servicehub'), @('vnet-sc500-l05-servicehub', 'peer-servicehub-to-hub'))) {
    $p = Invoke-L05Az @('network', 'vnet', 'peering', 'show', '--resource-group', $rg, '--vnet-name', $peer[0], '--name', $peer[1])
    Add-Check "$($peer[1]) state" 'Connected' $p.peeringState
}

# AVNM baseline (defined, not deployed)
$api = 'api-version=2024-05-01'
$mgr = "https://management.azure.com$($lab.networkManagerId)"
$m = Invoke-L05Az @('rest', '--method', 'get', '--url', "$mgr`?$api")
Add-Check 'AVNM scope access' 'SecurityAdmin' (@($m.properties.networkManagerScopeAccesses) -join ',')
$members = Invoke-L05Az @('rest', '--method', 'get', '--url', "$mgr/networkGroups/ng-servicehub-workloads/staticMembers?$api")
Add-Check 'Network group members' 'vnet-sc500-l05-servicehub' ((@($members.value | ForEach-Object { ($_.properties.resourceId -split '/')[-1] })) -join ',')
$rules = Invoke-L05Az @('rest', '--method', 'get', '--url', "$mgr/securityAdminConfigurations/sac-contoso-platform-baseline/ruleCollections/rc-platform-remote-access/rules?$api")
Add-Check 'Security admin rules defined' 'AlwaysAllow@100,Deny@200' ((@($rules.value | Sort-Object { $_.properties.priority } | ForEach-Object { "$($_.properties.access)@$($_.properties.priority)" })) -join ',')
$status = Invoke-L05Az @('rest', '--method', 'post', '--url', "$mgr/listDeploymentStatus?$api", '--body', (@{ regions = @($cfg.location); deploymentTypes = @('SecurityAdmin') } | ConvertTo-Json -Compress))
$deployed = @($status.value | Where-Object { $_.deploymentStatus -eq 'Deployed' -and @($_.configurationIds).Count -gt 0 }).Count
Add-Check 'Security admin configuration deployed (baseline: no)' 0 $deployed

# Audit plumbing
foreach ($v in 'vnet-sc500-l05-hub', 'vnet-sc500-l05-servicehub') {
    $fl = Invoke-L05Az -AllowFailure @('network', 'watcher', 'flow-log', 'show', '--location', $cfg.location, '--name', "fl-$v")
    $flow = if ($fl.ExitCode -eq 0) { $fl.Stdout | ConvertFrom-Json } else { $null }
    Add-Check "fl-$v enabled" 'True' ([bool](Get-L05Value $flow 'enabled'))
    Add-Check "fl-$v traffic analytics interval" 10 (Get-L05Value $flow 'flowAnalyticsConfiguration.networkWatcherFlowAnalyticsConfiguration.trafficAnalyticsInterval')
}

# Compute state and bounded labs (informational: running VMs and bounded labs bill by the hour)
$vms = @(Invoke-L05Az @('vm', 'list', '--resource-group', $rg, '--show-details', '--query', '[].{name:name, power:powerState}'))
Add-Check 'Test VMs present' 4 $vms.Count
foreach ($vm in $vms) { Add-Check "$($vm.name) power state" 'VM deallocated' $vm.power 'WARN' }
foreach ($b in $cfg.wanResourceGroup, $cfg.vpnResourceGroup) { Add-Check "Bounded lab $b absent" 'False' ([bool](Invoke-L05Az @('group', 'exists', '--name', $b))) 'WARN' }
# The hub gateway lives outside the temporary VPN group, so group absence alone misses its bill.
$hubVpn = @(Get-L05HubVpnResources)
foreach ($name in 'vgw-contoso-platform-hub', 'pip-vgw-contoso-platform-hub') {
    Add-Check "Bounded hub resource $name absent" 'False' ([bool]@($hubVpn | Where-Object name -eq $name).Count) 'WARN'
}

$checks | Format-Table -AutoSize | Out-String -Width 220
$fail = @($checks | Where-Object Result -eq 'FAIL').Count
$warn = @($checks | Where-Object Result -eq 'WARN').Count
[void](Write-L05Evidence 'readiness' ([ordered]@{ fail = $fail; warn = $warn; checks = @($checks) }))
if ($fail) { Write-Host "NOT READY: $fail check(s) failed."; exit 1 }
Write-Host "READY: the lab is at $($cfg.baseline) ($warn warning(s))."
