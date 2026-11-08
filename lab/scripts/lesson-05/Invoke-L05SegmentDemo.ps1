<#
.SYNOPSIS
    Demo 5.1: segment the ServiceHub tiers with an NSG that names application security groups,
    then prove and audit the result.

.DESCRIPTION
    Starts from CTSO-L05-BASELINE, where nsg-servicehub has only its default rules. The
    default AllowVnetInBound rule (priority 65000) lets every tier reach every other tier, so
    the web tier can open the data tier's database port. That's the introduced fault.

    Modes, in demo order:
      Settings            NSG association, custom rules, and each NIC's ASG membership.
      Probe               Connection tests from the web and app tiers (Run Command).
      ApplyLeastPrivilege Adds the ASG-based allow rules and a deny for other VNet traffic.
      FlowVerify          Network Watcher IP flow verify: which rule decides each path.
      EffectiveRules      The data tier NIC's effective security rules.
      FlowLogs            Reads the newest VNet flow-log blob for denied flows to the data tier.
      TrafficAnalytics    Queries traffic analytics (NTANetAnalytics) for the same flows.

    Every mode writes private evidence under lab/.azure/lesson-05/evidence.

.PARAMETER Mode
    One of the modes above.

.EXAMPLE
    pwsh -NoProfile -File C:\github\sc500\lab\scripts\lesson-05\Invoke-L05SegmentDemo.ps1 -Mode Probe
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Settings', 'Probe', 'ApplyLeastPrivilege', 'FlowVerify', 'EffectiveRules', 'FlowLogs', 'TrafficAnalytics')]
    [string]$Mode
)
. (Join-Path $PSScriptRoot 'L05.Common.ps1')
[void](Assert-L05Context)
$cfg = $script:L05Config
$rg = $cfg.resourceGroup
$h = $cfg.addressPlan.hosts
$p = $cfg.ports
$nsg = 'nsg-servicehub'

switch ($Mode) {
    'Settings' {
        $n = Invoke-L05Az @('network', 'nsg', 'show', '--resource-group', $rg, '--name', $nsg)
        $nics = foreach ($tier in 'web', 'app', 'data') {
            $nic = Invoke-L05Az @('network', 'nic', 'show', '--resource-group', $rg, '--name', "nic-vm-servicehub-$tier")
            [pscustomobject]@{ Tier = $tier; Ip = $nic.ipConfigurations[0].privateIPAddress; Asg = (@($nic.ipConfigurations[0].applicationSecurityGroups | ForEach-Object { ($_.id -split '/')[-1] }) -join ', ') }
        }
        $custom = @($n.securityRules | Sort-Object priority | ForEach-Object { [pscustomobject]@{ Priority = $_.priority; Name = $_.name; Access = $_.access; Port = $_.destinationPortRange } })
        $result = [ordered]@{ Nsg = $nsg; Subnet = (@($n.subnets | ForEach-Object { ($_.id -split '/')[-1] }) -join ', '); CustomRules = $custom.Count; Nics = @($nics) }
        [void](Write-L05Evidence 'segment-settings' $result)
        "NSG $nsg on subnet $($result.Subnet); custom rules: $($custom.Count)"
        if ($custom.Count) { $custom | Format-Table -AutoSize | Out-String }
        else { 'Only default rules. AllowVnetInBound (65000) allows every tier to reach every other tier.' }
        $nics | Format-Table -AutoSize | Out-String
    }
    'Probe' {
        $rows = @(Test-L05Paths -ResourceGroup $rg -FromVm 'vm-servicehub-web' -Targets @(
                [pscustomobject]@{ Name = 'app-api'; Ip = $h.app; Port = $p.app }
                [pscustomobject]@{ Name = 'data-db'; Ip = $h.data; Port = $p.data }
            ))
        $rows += @(Test-L05Paths -ResourceGroup $rg -FromVm 'vm-servicehub-app' -Targets @(
                [pscustomobject]@{ Name = 'data-db'; Ip = $h.data; Port = $p.data }
            ))
        [void](Write-L05Evidence 'segment-probe' $rows)
        $rows | Select-Object From, To, Port, Result, Answer | Format-Table -AutoSize | Out-String -Width 200
    }
    'ApplyLeastPrivilege' {
        # Allow rules name tiers, not addresses. The deny at 4000 sits above the default
        # AllowVnetInBound (65000), so anything not explicitly allowed between tiers stops here.
        # The VirtualNetwork tag is broader than this VNet. Inventory dependencies first;
        # this fixture has no load balancer and doesn't establish health-probe behavior.
        $asg = @{ web = 'asg-servicehub-web'; app = 'asg-servicehub-app'; data = 'asg-servicehub-data' }
        # Objects, not nested arrays: PowerShell flattens @(@(...), @(...)) into one list.
        $rules = @(
            [pscustomobject]@{ Name = 'Allow-Web-To-App-API'; Priority = '100'; From = $asg.web; To = $asg.app; Port = [string]$p.app }
            [pscustomobject]@{ Name = 'Allow-App-To-Data-DB'; Priority = '110'; From = $asg.app; To = $asg.data; Port = [string]$p.data }
        )
        foreach ($r in $rules) {
            [void](Invoke-L05Az @('network', 'nsg', 'rule', 'create', '--resource-group', $rg, '--nsg-name', $nsg, '--name', $r.Name,
                    '--priority', $r.Priority, '--access', 'Allow', '--direction', 'Inbound', '--protocol', 'Tcp',
                    '--source-asgs', $r.From, '--destination-asgs', $r.To, '--source-port-ranges', '*', '--destination-port-ranges', $r.Port))
        }
        [void](Invoke-L05Az @('network', 'nsg', 'rule', 'create', '--resource-group', $rg, '--nsg-name', $nsg, '--name', 'Deny-Other-VNet-Inbound',
                '--priority', '4000', '--access', 'Deny', '--direction', 'Inbound', '--protocol', '*',
                '--source-address-prefixes', 'VirtualNetwork', '--destination-address-prefixes', '*', '--source-port-ranges', '*', '--destination-port-ranges', '*'))
        $after = Invoke-L05Az @('network', 'nsg', 'rule', 'list', '--resource-group', $rg, '--nsg-name', $nsg)
        # ARM omits empty properties, so read each side through Get-L05Value (StrictMode-safe).
        $side = { param($rule, $which)
            $asgs = @(Get-L05Value $rule "${which}ApplicationSecurityGroups") | Where-Object { $_ } | ForEach-Object { ($_.id -split '/')[-1] }
            $prefix = Get-L05Value $rule "${which}AddressPrefix"
            (@($asgs) + @($prefix) | Where-Object { $_ }) -join ',' }
        $view = @($after | Sort-Object priority | ForEach-Object {
                [pscustomobject]@{ Priority = $_.priority; Name = $_.name; Access = $_.access; Source = (& $side $_ 'source'); Destination = (& $side $_ 'destination'); Port = $_.destinationPortRange }
            })
        [void](Write-L05Evidence 'segment-apply' $view)
        $view | Format-Table -AutoSize | Out-String -Width 200
    }
    'FlowVerify' {
        # IP flow verify evaluates the rules Azure would apply to one packet at the data NIC.
        $cases = @(
            @{ Name = 'web to data database'; Remote = "$($h.web):50000"; Local = "$($h.data):$($p.data)" }
            @{ Name = 'app to data database'; Remote = "$($h.app):50000"; Local = "$($h.data):$($p.data)" }
        )
        $rows = foreach ($c in $cases) {
            $r = Invoke-L05Az @('network', 'watcher', 'test-ip-flow', '--resource-group', $rg, '--vm', 'vm-servicehub-data',
                '--direction', 'Inbound', '--protocol', 'TCP', '--local', $c.Local, '--remote', $c.Remote)
            [pscustomobject]@{ Path = $c.Name; Access = $r.access; Rule = ($r.ruleName -split '/')[-1] }
        }
        [void](Write-L05Evidence 'segment-flowverify' @($rows))
        $rows | Format-Table -AutoSize | Out-String -Width 200
    }
    'EffectiveRules' {
        $e = Invoke-L05Az @('network', 'nic', 'list-effective-nsg', '--resource-group', $rg, '--name', 'nic-vm-servicehub-data')
        $rows = foreach ($assoc in $e.value) {
            foreach ($r in $assoc.effectiveSecurityRules | Where-Object direction -eq 'Inbound' | Sort-Object priority) {
                # ASG sources come back as full resource IDs; keep the readable last segment.
                $src = @(Get-L05Value $r 'sourceAddressPrefix') + @(Get-L05Value $r 'expandedSourceAddressPrefix' | Select-Object -First 2) |
                    Where-Object { $_ } | ForEach-Object { if ($_ -match '/applicationSecurityGroups/') { ($_ -split '/')[-1] } else { $_ } }
                [pscustomobject]@{ Priority = $r.priority; Name = ($r.name -split '/')[-1]; Access = $r.access; Source = (@($src | Where-Object { $_ }) -join ','); Port = (Get-L05Value $r 'destinationPortRange') }
            }
        }
        [void](Write-L05Evidence 'segment-effective' @($rows))
        $rows | Format-Table -AutoSize | Out-String -Width 200
    }
    'FlowLogs' {
        Get-L05FlowTuples -VnetName 'vnet-sc500-l05-servicehub' -DestinationPort $p.data -EvidenceName 'segment-flowlogs'
    }
    'TrafficAnalytics' {
        $lab = Get-L05Outputs
        $q = "NTANetAnalytics | where TimeGenerated > ago(4h) | where DestIp == '$($h.data)' and DestPort == $($p.data) " +
             "| summarize Flows = count(), Last = max(TimeGenerated) by SrcIp, FlowStatus, AclRule | order by Last desc"
        $r = @(Invoke-L05Az @('monitor', 'log-analytics', 'query', '--workspace', $lab.workspaceCustomerId, '--analytics-query', $q) -NoSubscription)
        [void](Write-L05Evidence 'segment-traffic-analytics' ([ordered]@{ query = $q; rows = $r }))
        if (-not @($r).Count) { 'No traffic analytics rows yet. Processing runs every 10 minutes; the raw flow log (FlowLogs mode) arrives sooner.' }
        else { $r | Format-Table -AutoSize | Out-String -Width 200 }
    }
}
