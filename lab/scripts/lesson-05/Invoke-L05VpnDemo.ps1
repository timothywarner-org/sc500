<#
.SYNOPSIS
    Demo 5.4: secure site-to-site and point-to-site VPN connections.

.DESCRIPTION
    Needs the bounded Vpn lab (Deploy-L05Bounded.ps1 -Lab Vpn -Deploy). The hub gateway's
    connection carries the Contoso baseline as a custom IPsec/IKE policy (IKEv2, AES256,
    SHA256, DH group 14; IPsec GCMAES256, PFS 14). The simulated field service branch still
    offers legacy crypto, which is the introduced fault: the tunnel can't form.

    Modes, in on-camera order:
      Settings   Gateway SKUs, both connections' IPsec/IKE policies, and the P2S settings.
      Status     Connection status and byte counters for both connections.
      IkeLogs    IKE diagnostic log lines from Log Analytics (negotiation failures show here).
      FixBranch  Replaces the branch connection's policy with the Contoso baseline.
      Probe      From the branch client: SSH banner of the platform scanner, across the tunnel.
      Break      Puts the legacy policy back on the branch connection (the reset target).

    Point-to-site connects with the Azure VPN Client and a real Microsoft Entra sign-in, so
    You do that yourself; no script signs in as anyone.

.EXAMPLE
    pwsh -NoProfile -File C:\github\sc500\lab\scripts\lesson-05\Invoke-L05VpnDemo.ps1 -Mode Status
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Settings', 'Status', 'IkeLogs', 'FixBranch', 'Probe', 'Break')][string]$Mode
)
. (Join-Path $PSScriptRoot 'L05.Common.ps1')
[void](Assert-L05Context)
$cfg = $script:L05Config
$vpnRg = $cfg.vpnResourceGroup
[void](Get-L05Outputs -Lab Vpn)
$connections = @('conn-hub-to-field-branch', 'conn-field-branch-to-hub')
$policy = @{
    baseline = @('--ike-encryption', 'AES256', '--ike-integrity', 'SHA256', '--dh-group', 'DHGroup14',
        '--ipsec-encryption', 'GCMAES256', '--ipsec-integrity', 'GCMAES256', '--pfs-group', 'PFS14',
        '--sa-lifetime', '27000', '--sa-max-size', '102400000')
    legacy   = @('--ike-encryption', 'AES128', '--ike-integrity', 'SHA1', '--dh-group', 'DHGroup2',
        '--ipsec-encryption', 'AES128', '--ipsec-integrity', 'SHA1', '--pfs-group', 'None',
        '--sa-lifetime', '27000', '--sa-max-size', '102400000')
}

function Set-L05BranchPolicy {
    # A connection holds a single custom policy, so replace rather than add alongside.
    param([ValidateSet('baseline', 'legacy')][string]$Name)
    [void](Invoke-L05Az -Raw @('network', 'vpn-connection', 'ipsec-policy', 'clear', '--resource-group', $vpnRg, '--connection-name', 'conn-field-branch-to-hub'))
    [void](Invoke-L05Az (@('network', 'vpn-connection', 'ipsec-policy', 'add', '--resource-group', $vpnRg, '--connection-name', 'conn-field-branch-to-hub') + $policy[$Name]))
    return Invoke-L05Az @('network', 'vpn-connection', 'ipsec-policy', 'list', '--resource-group', $vpnRg, '--connection-name', 'conn-field-branch-to-hub')
}

switch ($Mode) {
    'Settings' {
        $hub = Invoke-L05Az @('network', 'vnet-gateway', 'show', '--resource-group', $cfg.resourceGroup, '--name', 'vgw-contoso-platform-hub')
        $branch = Invoke-L05Az @('network', 'vnet-gateway', 'show', '--resource-group', $vpnRg, '--name', 'vgw-contoso-field-branch')
        $pol = foreach ($c in $connections) {
            $p = @(Invoke-L05Az @('network', 'vpn-connection', 'ipsec-policy', 'list', '--resource-group', $vpnRg, '--connection-name', $c))[0]
            [pscustomobject]@{ Connection = $c; IKE = "$($p.ikeEncryption)/$($p.ikeIntegrity)/$($p.dhGroup)"; IPsec = "$($p.ipsecEncryption)/$($p.ipsecIntegrity)/$($p.pfsGroup)" }
        }
        $p2s = $hub.vpnClientConfiguration
        $view = [ordered]@{
            HubGateway    = "$($hub.name) $($hub.sku.name) $($hub.vpnType)"
            BranchGateway = "$($branch.name) $($branch.sku.name) $($branch.vpnType)"
            Policies      = @($pol)
            P2S           = [ordered]@{ Pool = ($p2s.vpnClientAddressPool.addressPrefixes -join ','); Tunnel = ($p2s.vpnClientProtocols -join ','); Auth = ($p2s.vpnAuthenticationTypes -join ','); Audience = $p2s.aadAudience; Tenant = $p2s.aadTenant }
        }
        [void](Write-L05Evidence 'vpn-settings' $view)
        "Hub:    $($view.HubGateway)"; "Branch: $($view.BranchGateway)"
        $pol | Format-Table -AutoSize | Out-String -Width 200
        'Point-to-site: pool {0}, tunnel {1}, authentication {2}, audience {3}' -f $view.P2S.Pool, $view.P2S.Tunnel, $view.P2S.Auth, $view.P2S.Audience
    }
    'Status' {
        $rows = foreach ($c in $connections) {
            $s = Invoke-L05Az @('network', 'vpn-connection', 'show', '--resource-group', $vpnRg, '--name', $c)
            [pscustomobject]@{ Connection = $c; Status = $s.connectionStatus; Protocol = $s.connectionProtocol; IngressBytes = $s.ingressBytesTransferred; EgressBytes = $s.egressBytesTransferred }
        }
        [void](Write-L05Evidence 'vpn-status' @($rows))
        $rows | Format-Table -AutoSize | Out-String -Width 200
    }
    'IkeLogs' {
        $network = Get-L05Outputs -Lab Network
        $q = "AzureDiagnostics | where TimeGenerated > ago(2h) | where Category == 'IKEDiagnosticLog' " +
             "| project TimeGenerated, Resource, Message | order by TimeGenerated desc | take 25"
        $r = @(Invoke-L05Az -NoSubscription @('monitor', 'log-analytics', 'query', '--workspace', $network.workspaceCustomerId, '--analytics-query', $q))
        [void](Write-L05Evidence 'vpn-ike-logs' ([ordered]@{ query = $q; rows = $r }))
        if (-not @($r).Count) { 'No IKE diagnostic rows yet. Gateway diagnostics can take 10 to 15 minutes to arrive.' }
        else { $r | ForEach-Object { '{0:HH:mm:ss} {1} {2}' -f ([datetime]$_.TimeGenerated), $_.Resource, ($_.Message -replace '\s+', ' ') } }
    }
    'FixBranch' {
        $after = Set-L05BranchPolicy -Name baseline
        [void](Write-L05Evidence 'vpn-fix-branch' $after)
        'Branch connection now offers the Contoso baseline. The gateways renegotiate; check Status in a minute or two.'
    }
    'Probe' {
        $rows = @(Test-L05Paths -ResourceGroup $vpnRg -FromVm 'vm-branch-client' -Targets @(
                [pscustomobject]@{ Name = 'platform-scanner-ssh'; Ip = $cfg.addressPlan.hosts.mgmt; Port = 22 }
            ))
        [void](Write-L05Evidence 'vpn-probe' $rows)
        $rows | Select-Object From, To, Port, Result, Answer | Format-Table -AutoSize | Out-String -Width 200
    }
    'Break' {
        $after = Set-L05BranchPolicy -Name legacy
        [void](Write-L05Evidence 'vpn-break-branch' $after)
        'Branch connection offers legacy crypto again (the demo 5.4 starting fault).'
    }
}
