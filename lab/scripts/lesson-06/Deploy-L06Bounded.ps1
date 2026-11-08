<#
.SYNOPSIS
    Previews, or deploys, one of the bounded Lesson 6 labs.

.DESCRIPTION
    PLS and DNS bill by the hour and exist only while you work through the demo. The registered
    connector is now retained deallocated to preserve registration. The retained lab
    (Deploy-L06Lab.ps1) must exist first.
      Pls        rg-partsapi-prod-eastus2 (demo 6.2): the parts API behind an internal Standard Load
                 Balancer, the Private Link service pl-partsapi-prod-eastus2-001, and a partner VNet
                 that reuses the provider's address space. About 0.06 USD an hour,
                 plus about 0.10 USD an hour for two maintenance NAT gateways and IPs.
      Dns        rg-fieldoffice-prod-eastus2 (demo 6.4): a DNS Private Resolver with an inbound endpoint in
                 the retained hub, and a field-office VNet peered to the hub whose DNS stand-in
                 has no conditional forwarder yet. About 0.26 USD an hour,
                 plus about 0.05 USD an hour for maintenance NAT and its IP.
      Connector  rg-pnconnector-prod-eastus2 (demo 6.3): a Windows Server host in the hub for the
                 Microsoft Entra private network connector. About 0.05 USD an hour. Its admin
                 password is generated here and saved only as a DPAPI-protected credential under
                 %LOCALAPPDATA%\SC500\Lesson06 for your RDP sign-in (Copy-L06ConnectorPassword.ps1
                 puts it on the clipboard). It's never printed and never written in plain text.
                 RDP is allowed only from the operator's current public IP.

    Regional vCPU quota in the course subscription is shared with other lessons' VMs, which count even when
    deallocated. A live preflight checks available capacity. Linux fixtures use B1s (one vCPU).

.PARAMETER Lab
    Pls, Dns, or Connector.
.PARAMETER Deploy
    Create or update the resources after the preview passes.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Deploy-L06Bounded.ps1 -Lab Pls -Deploy
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Pls', 'Dns', 'Connector')][string]$Lab,
    [switch]$Deploy
)
. (Join-Path $PSScriptRoot 'L06.Common.ps1')
[void](Assert-L06Context)
$cfg = $script:L06Config
$private = Get-L06Outputs -Lab Private

$rgName = switch ($Lab) { 'Pls' { $cfg.plsResourceGroup } 'Dns' { $cfg.dnsResourceGroup } 'Connector' { $cfg.connectorResourceGroup } }
$groupExists=Invoke-L06Az @('group', 'exists', '--name', $rgName)
if ($groupExists) {
    $rg = Invoke-L06Az @('group', 'show', '--name', $rgName)
    if ($rg.tags.managedBy -ne $cfg.managedBy) { throw "$rgName exists but isn't tagged managedBy=$($cfg.managedBy). Stopping." }
}
if($Deploy){
    # Quota is shared with other authors; fail before creating billable partial fixtures.
    $n=$script:L06Names
    $expected=switch($Lab){'Pls'{@($n.partsVm,$n.fabrikamVm)};'Dns'{@($n.fieldOfficeDnsVm)};'Connector'{@($n.connectorVm)}}
    $present=if($groupExists){@(Invoke-L06Az @('vm','list','-g',$rgName)|ForEach-Object name)}else{@()}
    $perVm=if($Lab -eq 'Connector'){2}else{1}
    $needed=@($expected|Where-Object {$_ -notin $present}).Count*$perVm
    # The connector's family follows config.json windowsVmSize (Standard_B2s since October 30, 2026).
    $family=if($Lab -eq 'Connector'){$cfg.windowsVmFamily}else{'standardBSFamily'}
    $usage=Invoke-L06Az @('vm','list-usage','--location',$cfg.location)
    foreach($name in 'cores',$family){
        $quota=@($usage|Where-Object {$_.name.value -eq $name})[0]
        if([int]$quota.currentValue+$needed -gt [int]$quota.limit){throw "$($cfg.location) $name quota: $($quota.currentValue)/$($quota.limit), $needed additional cores required. Resolve quota before deploying; no resources were created."}
    }
}

$values = [ordered]@{ location = $cfg.location; resourceGroupName = $rgName; managedBy = $cfg.managedBy; names = $cfg.names }
# The connector template takes no naming components; the other two name their maintenance NAT gateways with them.
if ($Lab -ne 'Connector') { $values.naming = $cfg.naming }
$secure = @()
switch ($Lab) {
    'Pls' {
        $values.sshPublicKey = Get-L06SshPublicKey
        $values.imageVersion = Get-L06ImageVersion
        $values.vmSize = $cfg.vmSize
        $values.addressPlan = $cfg.addressPlan
        $values.ports = $cfg.ports
        $template = 'main-pls.bicep'; $deploymentName = $cfg.plsDeploymentName
    }
    'Dns' {
        $values.retainedResourceGroup = $cfg.resourceGroup
        $values.sshPublicKey = Get-L06SshPublicKey
        $values.imageVersion = Get-L06ImageVersion
        $values.vmSize = $cfg.vmSize
        $values.addressPlan = $cfg.addressPlan
        $values.hubVnetId = $private.hubVnetId
        $values.hubVnetName = $private.hubVnetName
        $values.dnsInboundSubnetId = $private.dnsInboundSubnetId
        $values.clientIdentityId = $private.onpremIdentityId
        $template = 'main-dns.bicep'; $deploymentName = $cfg.dnsDeploymentName
    }
    'Connector' {
        if (-not $IsWindows) { throw 'The connector password is protected with Windows DPAPI; run this on your workstation.' }
        $values.subnetId = $private.connectorsSubnetId
        $values.privateIp = $cfg.addressPlan.hosts.connector
        $values.vmSize = $cfg.windowsVmSize
        $values.operatorPublicIp = (Invoke-RestMethod -Uri 'https://api.ipify.org?format=json' -TimeoutSec 15).ip
        $template = 'main-connector.bicep'; $deploymentName = $cfg.connectorDeploymentName
        # Reuse the saved credential on a redeploy (Azure won't change the password in place),
        # otherwise generate one: 24 characters with every class Windows requires.
        $credDir = Join-Path $env:LOCALAPPDATA 'SC500/Lesson06'
        $credPath = Join-Path $credDir 'connector-admin.credential.xml'
        if (Test-Path -LiteralPath $credPath) { $credential = Import-Clixml -LiteralPath $credPath }
        else {
            $sets = @('ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789', '!@#%^*-_=+')
            $chars = foreach ($s in $sets) { 1..6 | ForEach-Object { $s[[Security.Cryptography.RandomNumberGenerator]::GetInt32($s.Length)] } }
            $shuffled = -join ($chars | Sort-Object { [Security.Cryptography.RandomNumberGenerator]::GetInt32([int]::MaxValue) })
            $credential = [pscredential]::new('contosoadmin', (ConvertTo-SecureString $shuffled -AsPlainText -Force))
            $shuffled = $null; $chars = $null
            [void][IO.Directory]::CreateDirectory($credDir)
            $credential | Export-Clixml -LiteralPath $credPath
        }
        $secure = @('--parameters', ('adminPassword=' + $credential.GetNetworkCredential().Password))
    }
}
$parameters = [ordered]@{}; foreach ($k in $values.Keys) { $parameters[$k] = @{ value = $values[$k] } }
$paramsPath = Join-Path $script:L06State "deployment-$($Lab.ToLowerInvariant()).parameters.json"
[ordered]@{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = $parameters } |
    ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $paramsPath -Encoding utf8

$base = @('--location', $cfg.location, '--name', $deploymentName, '--template-file', (Join-Path $script:L06Lab "infra/lesson-06/$template"), '--parameters', ('@' + $paramsPath)) + $secure
try {
    $validation = Invoke-L06Az (@('deployment', 'sub', 'validate') + $base)
    [void](Write-L06Evidence "$($Lab.ToLowerInvariant())-arm-validation" ($validation | Select-Object -ExcludeProperty properties))
    $preview = Invoke-L06Az (@('deployment', 'sub', 'what-if') + $base + @('--result-format', 'ResourceIdOnly', '--no-pretty-print'))
    [void](Write-L06Evidence "$($Lab.ToLowerInvariant())-what-if" $preview)
    foreach($diagnostic in @(Get-L06Value $preview 'diagnostics')){
        if($null -ne $diagnostic){Write-Warning "$($diagnostic.code): $($diagnostic.message)"}
    }
    $deletes = @($preview.changes | Where-Object changeType -eq 'Delete')
    if ($deletes.Count) { throw "What-if contains $($deletes.Count) deletion(s). Nothing was deployed." }
    $preview.changes | ForEach-Object { '{0,-10} {1}' -f $_.changeType, ($_.resourceId -replace '^/subscriptions/[^/]+', '') } | Out-Host
    if (-not $Deploy) { Write-Host "Preview only. Re-run with -Deploy to create the $Lab lab."; return }
    $started = Get-Date
    $result = Invoke-L06Az (@('deployment', 'sub', 'create') + $base)
    [void](Write-L06Evidence "$($Lab.ToLowerInvariant())-deployment" ([ordered]@{ state = $result.properties.provisioningState; duration = $result.properties.duration; outputs = $result.properties.outputs.lab.value }))
    if ($result.properties.provisioningState -ne 'Succeeded') { throw 'ARM did not report success.' }
    $lifecycle=if($Lab -eq 'Connector'){'Retain the registered host and deallocate with Start-L06PrivateAccessLab.ps1 -Stop.'}else{"Remove it with Remove-L06Bounded.ps1 -Lab $Lab when the session ends."}
    Write-Host ("$Lab lab deployed in {0:N0} minutes. $lifecycle" -f ((Get-Date) - $started).TotalMinutes)
}
finally { $secure = $null; $base = $null; $credential = $null }
