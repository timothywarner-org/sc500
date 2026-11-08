<#
.SYNOPSIS
    Read-only readiness check for the Lesson 6 lab at CTSO-L06-BASELINE.

.DESCRIPTION
    PASS means the check matches the baseline the demos start from. WARN means something costs
    money or needs attention before the demo but doesn't break the baseline (a running VM, a
    bounded lab that still exists). FAIL means a demo would start from the wrong state; run
    Reset-L06Lab.ps1 and check again. Changes nothing.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Test-L06Lab.ps1
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L06.Common.ps1')
[void](Assert-L06Context)
$cfg = $script:L06Config
$lab = Get-L06Outputs -Lab Private
$rg = $cfg.resourceGroup
$checks = [Collections.Generic.List[object]]::new()
function Add-Check([string]$Name, $Expected, $Actual, [switch]$WarnOnly) {
    $ok = "$Expected" -eq "$Actual"
    $checks.Add([pscustomobject]@{ Result = if ($ok) { 'PASS' } elseif ($WarnOnly) { 'WARN' } else { 'FAIL' }; Check = $Name; Expected = "$Expected"; Actual = "$Actual" })
}

$group = Invoke-L06Az @('group', 'show', '--name', $rg)
Add-Check 'Resource group tag managedBy' $cfg.managedBy $group.tags.managedBy

$sa = Invoke-L06Az @('storage', 'account', 'show', '--resource-group', $rg, '--name', $lab.recordsAccountName)
Add-Check 'Records account public network access (baseline fault: Enabled)' 'Enabled' $sa.publicNetworkAccess
Add-Check 'Records account Shared Key access' 'False' $sa.allowSharedKeyAccess
Add-Check 'Records account anonymous blob access' 'False' $sa.allowBlobPublicAccess
Add-Check 'Records account minimum TLS' 'TLS1_2' $sa.minimumTlsVersion
Add-Check 'Records account private endpoint connections (baseline: none)' 0 @(Get-L06Value $sa 'privateEndpointConnections').Count
$exists = Invoke-L06Az -NoSubscription -AllowFailure @('storage', 'blob', 'exists', '--account-name', $lab.recordsAccountName, '--container-name', $cfg.recordsContainer, '--name', $cfg.seedBlob, '--auth-mode', 'login')
Add-Check "Seed record $($cfg.seedBlob) readable from the workstation" 'True' $(if ($exists.ExitCode -eq 0) { ($exists.Stdout | ConvertFrom-Json).exists } else { 'error' })

$links = @(Invoke-L06Az @('network', 'private-dns', 'link', 'vnet', 'list', '--resource-group', $rg, '--zone-name', $cfg.privateDnsZone))
foreach ($name in $script:L06Names.hubZoneLink, $script:L06Names.servicehubZoneLink) {
    $l = @($links | Where-Object name -eq $name)
    Add-Check "$name state" 'Completed' $(if ($l.Count) { $l[0].virtualNetworkLinkState } else { 'missing' })
    Add-Check "$name fallback to internet" 'Default' $(if ($l.Count) { Get-L06Value $l[0] 'resolutionPolicy' } else { 'missing' })
}
$a = @(Invoke-L06Az @('network', 'private-dns', 'record-set', 'a', 'list', '--resource-group', $rg, '--zone-name', $cfg.privateDnsZone))
Add-Check 'Private zone A records (baseline: none)' 0 $a.Count

$hub = Invoke-L06Az @('network', 'vnet', 'show', '--resource-group', $rg, '--name', $script:L06Names.hubVnet)
foreach ($s in $hub.subnets) { Add-Check "$($s.name) is private (no default outbound access)" 'False' (Get-L06Value $s 'defaultOutboundAccess') }
$inbound = @($hub.subnets | Where-Object name -eq 'snet-dns-inbound')[0]
Add-Check 'snet-dns-inbound delegated to the DNS resolver' 'Microsoft.Network/dnsResolvers' (@(Get-L06Value $inbound 'delegations')[0].serviceName)
foreach ($p in 'peer-hub-to-servicehub') {
    $peer = @($hub.virtualNetworkPeerings | Where-Object name -eq $p)
    Add-Check "$p state" 'Connected' $(if ($peer.Count) { $peer[0].peeringState } else { 'missing' })
}

$vm = Invoke-L06Az @('vm', 'show', '--resource-group', $rg, '--name', $lab.appVm, '--show-details')
Add-Check "$($lab.appVm) has a system-assigned identity" 'SystemAssigned' (Get-L06Value $vm 'identity.type')
Add-Check "$($lab.appVm) has no public IP" '' "$(Get-L06Value $vm 'publicIps')"
Add-Check "$($lab.appVm) power state" 'VM deallocated' $vm.powerState -WarnOnly
# Why this check exists: Defender for Servers pushes the MDE.Linux extension after a VM starts,
# and it can't finish without internet egress. While any extension is Updating, Run Command
# queues behind it, so a demo step that looks hung is really waiting (13 minutes in the
# September 26 rehearsal). Wait for this to read Succeeded before the demo.
$busy = @(Invoke-L06Az @('vm', 'extension', 'list', '--resource-group', $rg, '--vm-name', $lab.appVm) |
        Where-Object { $_.provisioningState -ne 'Succeeded' } | ForEach-Object { "$($_.name) $($_.provisioningState)" })
Add-Check "$($lab.appVm) extension provisioning (Failed is not ready)" 'all succeeded' $(if ($busy.Count) { $busy -join '; ' } else { 'all succeeded' })

foreach ($b in @($cfg.plsResourceGroup, $cfg.dnsResourceGroup)) {
    Add-Check "Bounded lab $b absent (not billing)" 'False' ([bool](Invoke-L06Az @('group', 'exists', '--name', $b))) -WarnOnly
}
foreach($target in @(@{Group=$cfg.connectorResourceGroup;Vm=$script:L06Names.connectorVm},@{Group=$cfg.clientResourceGroup;Vm=$script:L06Names.clientVm})){
    if(Invoke-L06Az @('group','exists','-n',$target.Group)){
        $retained=Invoke-L06Az @('vm','show','-g',$target.Group,'-n',$target.Vm,'--show-details')
        Add-Check "$($target.Vm) retained, deallocated (disk/IP still bill)" 'VM deallocated' $retained.powerState -WarnOnly
    }
}
$nats=@(Invoke-L06Az @('network','nat','gateway','list','-g',$rg))
Add-Check 'Temporary maintenance NAT removed after take' 0 @($nats|Where-Object { (Get-L06Value $_ 'tags.purpose') -eq 'lesson06-maintenance-egress' }).Count -WarnOnly

[void](Write-L06Evidence 'readiness' $checks)
$fails = @($checks | Where-Object Result -eq 'FAIL').Count
$warns = @($checks | Where-Object Result -eq 'WARN').Count
if ($fails) { "NOT READY: $fails check(s) failed. Read the failing rows; reset fixes baseline drift, maintenance egress addresses extension installation." }
else { "BASELINE CHECK PASSED: $($cfg.baseline) ($warns warning(s)). This does not prove a human Private Access sign-in or recording readiness." }
$checks | Format-Table -AutoSize | Out-String -Width 220
if ($fails) { exit 1 }
