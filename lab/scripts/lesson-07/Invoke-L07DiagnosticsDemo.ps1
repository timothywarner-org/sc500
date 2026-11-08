<#
.SYNOPSIS
    Demo 7.3 (and the DDoS check for 7.4): what Network Watcher and the NIC can tell you about
    a flow, and what they can't.

.DESCRIPTION
    NextHop          Network Watcher next hop from production to non-production and to the
                     internet. Both say VirtualAppliance 10.70.0.4: the firewall.
    FlowVerify       Network Watcher IP flow verify for production to non-production on the app
                     port, in both directions. IP flow verify evaluates NSG rules (and Virtual
                     Network Manager admin rules) only, so it reports what the NSGs allow. The
                     firewall's own log is where the deny shows up.
    EffectiveRoutes  The production NIC's effective routes: system routes plus the UDR.
    EffectiveRules   Effective security rules on both NICs, inbound, by priority. (The CLI
                     returns service tags such as VirtualNetwork without their expanded
                     prefixes; the portal's view can expand them.)
    Ddos             The firewall public IP's DDoS settings and the hub VNet's DDoS plan link.
    All              Every mode above, in order.
    The VMs must be running (Start-L07Lab.ps1). Read-only.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Invoke-L07DiagnosticsDemo.ps1 -Mode FlowVerify
#>
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('NextHop', 'FlowVerify', 'EffectiveRoutes', 'EffectiveRules', 'Ddos', 'All')][string]$Mode)
. (Join-Path $PSScriptRoot 'L07.Common.ps1')
[void](Assert-L07Context)
$cfg = $script:L07Config
$rg = $cfg.resourceGroup
$h = $cfg.addressPlan.hosts
$port = "$($cfg.ports.app)"
$modes = if ($Mode -eq 'All') { 'NextHop', 'FlowVerify', 'EffectiveRoutes', 'EffectiveRules', 'Ddos' } else { @($Mode) }
$evidence = [ordered]@{}

foreach ($m in $modes) {
    "== $m"
    switch ($m) {
        'NextHop' {
            $rows = foreach ($dest in @($h.nonprodApp, '1.2.3.4')) {
                $r = Invoke-L07Az @('network', 'watcher', 'show-next-hop', '--resource-group', $rg, '--vm', $cfg.names.prodVm, '--source-ip', $h.prodApp, '--dest-ip', $dest)
                [pscustomobject]@{ From = $h.prodApp; To = $dest; NextHopType = $r.nextHopType; NextHopIp = $r.nextHopIpAddress; Route = ($r.routeTableId -split '/')[-1] }
            }
            $evidence.nextHop = $rows
            $rows | Format-Table -AutoSize | Out-String
        }
        'FlowVerify' {
            $cases = @(
                @{ Vm = $cfg.names.prodVm; Dir = 'Outbound'; Local = "$($h.prodApp):50000"; Remote = "$($h.nonprodApp):$port"; Label = 'prod -> nonprod, leaving prod' }
                @{ Vm = $cfg.names.nonprodVm; Dir = 'Inbound'; Local = "$($h.nonprodApp):$port"; Remote = "$($h.prodApp):50000"; Label = 'prod -> nonprod, arriving at nonprod' }
                @{ Vm = $cfg.names.prodVm; Dir = 'Inbound'; Local = "$($h.prodApp):$port"; Remote = "$($h.nonprodApp):50000"; Label = 'nonprod -> prod, arriving at prod' }
            )
            $rows = foreach ($c in $cases) {
                $r = Invoke-L07Az @('network', 'watcher', 'test-ip-flow', '--resource-group', $rg, '--vm', $c.Vm, '--direction', $c.Dir, '--protocol', 'TCP', '--local', $c.Local, '--remote', $c.Remote)
                [pscustomobject]@{ Flow = $c.Label; Access = $r.access; NsgRule = ($r.ruleName -split '/')[-1] }
            }
            $evidence.ipFlowVerify = $rows
            $rows | Format-Table -AutoSize | Out-String
            'IP flow verify evaluates NSG and security admin rules. The firewall decision for the attempted flow is in AZFWNetworkRule (Invoke-L07FirewallDemo.ps1 -Mode Logs).'
        }
        'EffectiveRoutes' {
            $r = Invoke-L07Az @('network', 'nic', 'show-effective-route-table', '--resource-group', $rg, '--name', "nic-$($cfg.names.prodVm)")
            $rows = @($r.value | ForEach-Object { [pscustomobject]@{ Source = $_.source; State = $_.state; Prefix = ($_.addressPrefix -join ', '); NextHopType = $_.nextHopType; NextHop = ($_.nextHopIpAddress -join ', ') } })
            $evidence.effectiveRoutesProd = $rows
            $rows | Format-Table -AutoSize | Out-String -Width 200
        }
        'EffectiveRules' {
            foreach ($vm in @($cfg.names.prodVm, $cfg.names.nonprodVm)) {
                $r = Invoke-L07Az @('network', 'nic', 'list-effective-nsg', '--resource-group', $rg, '--name', "nic-$vm")
                $rules = @($r.value | ForEach-Object { $_.effectiveSecurityRules }) | Where-Object direction -eq 'Inbound'
                # Only rules that use a service tag carry expandedSourceAddressPrefix, and StrictMode
                # throws on a missing property, so read both through Get-L07Value.
                $rows = @($rules | ForEach-Object {
                        $expanded = @(@(Get-L07Value $_ 'expandedSourceAddressPrefix') | Where-Object { $_ })
                        $declared = "$(Get-L07Value $_ 'sourceAddressPrefix')"
                        $shown = if ($expanded.Count) { ($expanded | Select-Object -First 6) -join ', ' } else { $declared }
                        if ($expanded.Count -gt 6) { $shown += " (+$($expanded.Count - 6) more)" }
                        [pscustomobject]@{ Priority = $_.priority; Rule = ($_.name -split '/')[-1]; Access = $_.access; Declared = $declared; Expands = $shown }
                    } | Sort-Object Priority)
                $evidence["effectiveInbound-$vm"] = $rows
                "-- $vm inbound"
                $rows | Format-Table -AutoSize -Wrap | Out-String -Width 200
            }
        }
        'Ddos' {
            $pip = Invoke-L07Az @('network', 'public-ip', 'show', '--resource-group', $rg, '--name', $cfg.names.firewallPublicIp)
            $hub = Invoke-L07Az @('network', 'vnet', 'show', '--resource-group', $rg, '--name', $cfg.names.hubVnet)
            $row = [pscustomobject]@{
                PublicIp              = $pip.ipAddress
                IpDdosProtectionMode  = "$(Get-L07Value $pip 'ddosSettings.protectionMode')"
                HubDdosProtection     = "$(Get-L07Value $hub 'enableDdosProtection')"
                HubDdosPlan           = "$(Get-L07Value $hub 'ddosProtectionPlan.id')"
            }
            $evidence.ddos = $row
            $row | Format-List | Out-String
            if ($row.IpDdosProtectionMode -eq 'VirtualNetworkInherited' -and -not $hub.enableDdosProtection) {
                'Inherited mode without a VNet plan: only infrastructure protection applies.'
            }
            else { 'Additional DDoS configuration is present; inspect the mode and VNet plan above.' }
        }
    }
}
[void](Write-L07Evidence "diagnostics-$($Mode.ToLowerInvariant())" $evidence)
