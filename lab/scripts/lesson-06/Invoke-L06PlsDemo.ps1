<#
.SYNOPSIS
    Demo 6.2: a partner requests private access to Contoso's parts API through a Private Link
    service, Contoso approves it, and the partner connects.

.DESCRIPTION
    Needs the bounded Pls lab (Deploy-L06Bounded.ps1 -Lab Pls). Each -Mode is one on-camera step
    and saves its result under lab/.azure/lesson-06/evidence.
      Settings           The Private Link service: alias, visibility, auto-approval, NAT IP, the
                         load balancer frontend it's attached to, and its connections.
      RequestConnection  The partner creates pep-fabrikam-to-partsapi-001 in its own VNet as a manual
                         request by alias, the way a customer in another tenant would.
      Connections        Both views of the request: the partner endpoint's status and the
                         provider's list of connections, with the request message.
      Approve            Contoso approves the pending connection.
      Probe              From the partner client, calls the parts API through the endpoint's
                         private IP. The answer shows the address the provider saw.
    Reset-L06Lab.ps1 deletes the partner endpoint, so the next run starts with no connection.

.PARAMETER Mode
    Settings, RequestConnection, Connections, Approve, or Probe.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Invoke-L06PlsDemo.ps1 -Mode Settings
#>
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Settings', 'RequestConnection', 'Connections', 'Approve', 'Probe')][string]$Mode)
. (Join-Path $PSScriptRoot 'L06.Common.ps1')
[void](Assert-L06Context)
$cfg = $script:L06Config
$lab = Get-L06Outputs -Lab Pls
$rg = $cfg.plsResourceGroup
$peName = $script:L06Names.partnerEndpoint

function Get-PartnerEndpointIp {
    $pe = Invoke-L06Az -AllowFailure @('network', 'private-endpoint', 'show', '--resource-group', $rg, '--name', $peName)
    if ($pe.ExitCode -ne 0) { return $null }
    $pe = $pe.Stdout | ConvertFrom-Json -Depth 50
    $nic = Invoke-L06Az @('network', 'nic', 'show', '--ids', @($pe.networkInterfaces)[0].id)
    return @($nic.ipConfigurations)[0].privateIPAddress
}

switch ($Mode) {
    'Settings' {
        $pls = Invoke-L06Az @('network', 'private-link-service', 'show', '--resource-group', $rg, '--name', $lab.plsName)
        $view = [ordered]@{
            Service      = $pls.name
            Alias        = $pls.alias
            Visibility   = @(Get-L06Value $pls 'visibility.subscriptions') -join ', '
            AutoApproval = if (@(Get-L06Value $pls 'autoApproval.subscriptions').Count) { @($pls.autoApproval.subscriptions) -join ', ' } else { 'none (every request needs approval)' }
            NatIp        = "$(@($pls.ipConfigurations)[0].privateIPAddress) in $((@($pls.ipConfigurations)[0].subnet.id -split '/')[-1])"
            Frontend     = (@($pls.loadBalancerFrontendIpConfigurations)[0].id -split '/')[-3, -1] -join ' / '
            ProxyProtocol = [bool](Get-L06Value $pls 'enableProxyProtocol')
            Connections  = @(@(Get-L06Value $pls 'privateEndpointConnections') | ForEach-Object { "$($_.name): $($_.privateLinkServiceConnectionState.status)" })
        }
        if (-not $view.Connections.Count) { $view.Connections = 'none' }
        [void](Write-L06Evidence 'pls-settings' $view)
        $view.GetEnumerator() | ForEach-Object { '{0,-13} {1}' -f $_.Key, ($_.Value -join '; ') }
    }
    'RequestConnection' {
        $existing = Invoke-L06Az -AllowFailure @('network', 'private-endpoint', 'show', '--resource-group', $rg, '--name', $peName)
        if ($existing.ExitCode -ne 0) {
            Write-Host "Creating $peName as a manual request by alias. This takes about a minute."
            [void](Invoke-L06Az @('network', 'private-endpoint', 'create', '--resource-group', $rg, '--name', $peName,
                    # Explicit location: this workstation's az config defaults to eastus, and a
                    # private endpoint must be in its VNet's region (eastus2).
                    '--location', $cfg.location, '--subnet', $lab.partnerSubnetId, '--nic-name', $script:L06Names.partnerEndpointNic,
                    '--private-connection-resource-id', $lab.plsAlias, '--connection-name', 'conn-partner-to-parts',
                    '--manual-request', 'true', '--request-message', 'Fabrikam field services: parts lookups for work order sync'))
        }
        $pe = Invoke-L06Az @('network', 'private-endpoint', 'show', '--resource-group', $rg, '--name', $peName)
        $conn = @($pe.manualPrivateLinkServiceConnections)[0]
        $view = [ordered]@{ Endpoint = $pe.name; RequestedBy = 'alias'; Target = $conn.privateLinkServiceId; Status = $conn.privateLinkServiceConnectionState.status; PrivateIp = Get-PartnerEndpointIp }
        [void](Write-L06Evidence 'pls-request' $view)
        $view.GetEnumerator() | ForEach-Object { '{0,-12} {1}' -f $_.Key, $_.Value }
    }
    'Connections' {
        $pe = Invoke-L06Az @('network', 'private-endpoint', 'show', '--resource-group', $rg, '--name', $peName)
        $pls = Invoke-L06Az @('network', 'private-link-service', 'show', '--resource-group', $rg, '--name', $lab.plsName)
        $rows = @(
            [pscustomobject]@{ Side = 'Partner endpoint'; Name = $pe.name; Status = @($pe.manualPrivateLinkServiceConnections)[0].privateLinkServiceConnectionState.status; Message = @($pe.manualPrivateLinkServiceConnections)[0].requestMessage }
        ) + @(@(Get-L06Value $pls 'privateEndpointConnections') | ForEach-Object {
                [pscustomobject]@{ Side = 'Contoso service'; Name = ($_.name -split '\.')[0]; Status = $_.privateLinkServiceConnectionState.status; Message = $_.privateLinkServiceConnectionState.description }
            })
        [void](Write-L06Evidence 'pls-connections' $rows)
        $rows | Format-Table -AutoSize | Out-String -Width 200
    }
    'Approve' {
        $pls = Invoke-L06Az @('network', 'private-link-service', 'show', '--resource-group', $rg, '--name', $lab.plsName)
        $pending = @(@(Get-L06Value $pls 'privateEndpointConnections') | Where-Object { $_.privateLinkServiceConnectionState.status -eq 'Pending' })
        if (-not $pending.Count) { throw 'No pending connection to approve. Run -Mode RequestConnection first.' }
        foreach ($c in $pending) {
            [void](Invoke-L06Az @('network', 'private-link-service', 'connection', 'update', '--resource-group', $rg, '--service-name', $lab.plsName,
                    '--name', $c.name, '--connection-status', 'Approved', '--description', 'Approved by the Contoso platform team for parts lookups'))
        }
        $pls = Invoke-L06Az @('network', 'private-link-service', 'show', '--resource-group', $rg, '--name', $lab.plsName)
        $rows = @(@(Get-L06Value $pls 'privateEndpointConnections') | ForEach-Object { [pscustomobject]@{ Connection = ($_.name -split '\.')[0]; Status = $_.privateLinkServiceConnectionState.status; Description = $_.privateLinkServiceConnectionState.description } })
        [void](Write-L06Evidence 'pls-approve' $rows)
        $rows | Format-Table -AutoSize | Out-String -Width 200
    }
    'Probe' {
        $ip = Get-PartnerEndpointIp
        if (-not $ip) { throw 'The partner endpoint does not exist. Run -Mode RequestConnection first.' }
        $script = "if timeout 4 bash -c 'exec 3<>/dev/tcp/$ip/$($cfg.ports.parts)' 2>/dev/null; then r=OPEN; else r=BLOCKED; fi; " +
                  "body=`$(curl -s -m 4 http://${ip}:$($cfg.ports.parts)/ 2>/dev/null | head -n 1); echo `"PROBE|`$r|`$body`""
        $out = Invoke-L06Guest -ResourceGroup $rg -VmName $lab.partnerClient -Script $script
        $row = if ($out -match 'PROBE\|([^|]*)\|(.*)') { [pscustomobject]@{ From = "$($lab.partnerClient) ($($cfg.addressPlan.hosts.partnerClient))"; To = "${ip}:$($cfg.ports.parts)"; Result = $Matches[1]; Answer = $Matches[2].Trim() } }
               else { [pscustomobject]@{ From = $lab.partnerClient; To = $ip; Result = 'NoResult'; Answer = $out } }
        [void](Write-L06Evidence 'pls-probe' $row)
        $row | Format-List | Out-String -Width 200
    }
}
