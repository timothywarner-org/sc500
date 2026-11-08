<#
.SYNOPSIS
    Demo 5.3: show that the secured Virtual WAN hub inspects spoke-to-spoke traffic.

.DESCRIPTION
    Needs the bounded Wan lab (Deploy-L05Bounded.ps1 -Lab Wan -Deploy). Routing intent sends
    private traffic through Azure Firewall in the hub, and the Firewall Policy allows exactly
    one east-west path: the ServiceHub app spoke to the shared parts API on TCP 8080.

    Modes, in on-camera order:
      Settings      Virtual WAN type, hub, firewall SKU and policy, routing intent.
      Routes        Effective routes on the ServiceHub app VM's NIC: the next hop is the firewall.
      Probe         From the app spoke: the shared API (allowed) and its database port (denied).
      FirewallLogs  Network rule log rows for those two flows, from Log Analytics.

.EXAMPLE
    pwsh -NoProfile -File C:\github\sc500\lab\scripts\lesson-05\Invoke-L05WanDemo.ps1 -Mode Probe
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Settings', 'Routes', 'Probe', 'FirewallLogs')][string]$Mode
)
. (Join-Path $PSScriptRoot 'L05.Common.ps1')
[void](Assert-L05Context)
$cfg = $script:L05Config
$rg = $cfg.wanResourceGroup
$w = $cfg.addressPlan.wanHosts
[void](Get-L05Outputs -Lab Wan)

switch ($Mode) {
    'Settings' {
        $wan = Invoke-L05Az @('network', 'vwan', 'show', '--resource-group', $rg, '--name', 'vwan-sc500-l05')
        $hub = Invoke-L05Az @('network', 'vhub', 'show', '--resource-group', $rg, '--name', 'vhub-sc500-l05-eastus2')
        $fw = Invoke-L05Az @('network', 'firewall', 'show', '--resource-group', $rg, '--name', 'afw-sc500-l05-hub')
        $ri = Invoke-L05Az @('rest', '--method', 'get', '--url', "https://management.azure.com$($hub.id)/routingIntent?api-version=2024-05-01")
        $view = [ordered]@{
            # The CLI flattens properties.type into typePropertiesType, because the top-level
            # 'type' is the resource type (Microsoft.Network/virtualWans), not Basic or Standard.
            WanType        = $wan.typePropertiesType
            Hub            = "$($hub.name) $($hub.addressPrefix)"
            Firewall       = "$($fw.name) $($fw.sku.name)/$($fw.sku.tier), private IP $($fw.hubIPAddresses.privateIPAddress)"
            FirewallPolicy = ($fw.firewallPolicy.id -split '/')[-1]
            RoutingPolicies = @($ri.value.properties.routingPolicies | ForEach-Object { "$($_.name): $($_.destinations -join ',') -> $(($_.nextHop -split '/')[-1])" })
        }
        [void](Write-L05Evidence 'wan-settings' $view)
        $view.GetEnumerator() | ForEach-Object { '{0,-16} {1}' -f $_.Key, ($_.Value -join '; ') }
    }
    'Routes' {
        $routes = Invoke-L05Az @('network', 'nic', 'show-effective-route-table', '--resource-group', $rg, '--name', 'nic-vm-wan-servicehub-app')
        $rows = @($routes.value | ForEach-Object { [pscustomobject]@{ Source = $_.source; State = $_.state; Prefix = ($_.addressPrefix -join ','); NextHop = $_.nextHopType; NextHopIp = ($_.nextHopIpAddress -join ',') } })
        # Keep every route in the evidence file, but show only routes that carry traffic:
        # Azure adds a long list of reserved prefixes with next hop None, which buries the
        # three routing-intent routes on screen.
        [void](Write-L05Evidence 'wan-routes' $rows)
        $rows = @($rows | Where-Object NextHop -ne 'None')
        $rows | Format-Table -AutoSize | Out-String -Width 200
    }
    'Probe' {
        $rows = @(Test-L05Paths -ResourceGroup $rg -FromVm 'vm-wan-servicehub-app' -Targets @(
                [pscustomobject]@{ Name = 'shared-api'; Ip = $w.shared; Port = $cfg.ports.shared }
                [pscustomobject]@{ Name = 'shared-db'; Ip = $w.shared; Port = $cfg.ports.data }
            ))
        [void](Write-L05Evidence 'wan-probe' $rows)
        $rows | Select-Object From, To, Port, Result, Answer | Format-Table -AutoSize | Out-String -Width 200
    }
    'FirewallLogs' {
        $network = Get-L05Outputs -Lab Network
        $q = "AZFWNetworkRule | where TimeGenerated > ago(2h) | where DestinationIp == '$($w.shared)' " +
             "| project TimeGenerated, SourceIp, DestinationIp, DestinationPort, Action, Policy, RuleCollection, Rule, ActionReason | order by TimeGenerated desc | take 20"
        $r = @(Invoke-L05Az -NoSubscription @('monitor', 'log-analytics', 'query', '--workspace', $network.workspaceCustomerId, '--analytics-query', $q))
        [void](Write-L05Evidence 'wan-firewall-logs' ([ordered]@{ query = $q; rows = $r }))
        if (-not @($r).Count) { 'No network rule log rows yet. Firewall logs usually arrive in five to ten minutes; probe early, then query again.' }
        else {
            # The CLI returns TimeGenerated as text in UTC plus a TableName column; show UTC time
            # and one "Decided by" column so the allowed row names its rule and the denied row
            # names the firewall's default action, which is the comparison the demo makes.
            $r | ForEach-Object {
                [pscustomobject]@{
                    TimeUtc     = ([DateTime]$_.TimeGenerated).ToUniversalTime().ToString('HH:mm:ss')
                    Source      = $_.SourceIp
                    Destination = "$($_.DestinationIp):$($_.DestinationPort)"
                    Action      = $_.Action
                    DecidedBy   = if ($_.Rule) { "$($_.Policy) / $($_.RuleCollection) / $($_.Rule)" } else { $_.ActionReason }
                }
            } | Sort-Object TimeUtc, Destination, Action -Unique | Sort-Object TimeUtc -Descending |
                Format-Table -AutoSize | Out-String -Width 220
        }
    }
}
