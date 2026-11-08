<#
.SYNOPSIS
    Previews, or deploys, one of the bounded Lesson 5 labs: the secured Virtual WAN hub
    (demo 5.3) or the site-to-site and point-to-site VPN (demo 5.4).

.DESCRIPTION
    Both labs bill by the hour, so they exist only while you work through the demo. Deploy about an
    hour before recording; Remove-L05Bounded.ps1 takes them down afterward.
      Wan  rg-sc500-l05-wan: Standard Virtual WAN, hub, Azure Firewall Basic with a Firewall
           Policy, two spokes with one test VM each, and routing intent for private traffic.
           About 0.66 USD an hour. The hub and firewall take 30 to 45 minutes to provision.
      Vpn  rg-sc500-l05-vpn: the simulated field service branch (VNet, VpnGw1AZ gateway,
           client VM), local network gateways, and both IPsec connections; plus the hub-side
           VpnGw1AZ gateway with Microsoft Entra point-to-site settings in the retained hub
           VNet. About 0.43 USD an hour. Gateways take 30 to 45 minutes to provision.
    The retained network lab (Deploy-L05Lab.ps1) must exist first: both labs reuse its SSH
    public key, image version, and Log Analytics workspace, and the VPN lab uses its hub VNet.

    The VPN pre-shared key is generated here, in memory, for each deployment. It's passed to
    ARM as a secure parameter, never printed, and never written to disk.

.PARAMETER Lab
    Wan or Vpn.
.PARAMETER Deploy
    Create or update the resources after the preview passes.
.PARAMETER BranchPolicy
    Vpn only. legacy (default) deploys the introduced fault; baseline deploys a working tunnel.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-05\Deploy-L05Bounded.ps1 -Lab Wan -Deploy
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Wan', 'Vpn')][string]$Lab,
    [switch]$Deploy,
    [ValidateSet('legacy', 'baseline')][string]$BranchPolicy = 'legacy'
)
. (Join-Path $PSScriptRoot 'L05.Common.ps1')
[void](Assert-L05Context)
$cfg = $script:L05Config
$network = Get-L05Outputs -Lab Network

$rgName = if ($Lab -eq 'Wan') { $cfg.wanResourceGroup } else { $cfg.vpnResourceGroup }
if (Invoke-L05Az @('group', 'exists', '--name', $rgName)) {
    $rg = Invoke-L05Az @('group', 'show', '--name', $rgName)
    if ($rg.tags.managedBy -ne $cfg.managedBy) { throw "$rgName exists but isn't tagged managedBy=$($cfg.managedBy). Stopping." }
}
$publicKey = (Get-Content -LiteralPath (Join-Path $script:L05State 'ssh-public-key.txt') -Raw).Trim()
$imageVersion = (Get-Content -LiteralPath (Join-Path $script:L05State 'image-version.txt') -Raw).Trim()

$values = [ordered]@{
    location     = $cfg.location
    addressPlan  = $cfg.addressPlan
    sshPublicKey = $publicKey
    imageVersion = $imageVersion
    vmSize       = $cfg.boundedVmSize
    workspaceId  = $network.workspaceId
    managedBy    = $cfg.managedBy
}
if ($Lab -eq 'Wan') {
    $values.resourceGroupName = $cfg.wanResourceGroup
    $values.ports = $cfg.ports
    $template = 'main-wan.bicep'; $deploymentName = $cfg.wanDeploymentName
}
else {
    $values.networkResourceGroup = $cfg.resourceGroup
    $values.vpnResourceGroup = $cfg.vpnResourceGroup
    $values.tenantId = $cfg.tenantId
    $values.p2sAudience = $cfg.p2sAudience
    $values.branchPolicy = $BranchPolicy
    $template = 'main-vpn.bicep'; $deploymentName = $cfg.vpnDeploymentName
}
$parameters = [ordered]@{}; foreach ($k in $values.Keys) { $parameters[$k] = @{ value = $values[$k] } }
$paramsPath = Join-Path $script:L05State "deployment-$($Lab.ToLowerInvariant()).parameters.json"
[ordered]@{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = $parameters } |
    ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $paramsPath -Encoding utf8

$base = @('--location', $cfg.location, '--name', $deploymentName, '--template-file', (Join-Path $script:L05Lab "infra/lesson-05/$template"), '--parameters', ('@' + $paramsPath))
if ($Lab -eq 'Vpn') {
    # 40 characters from the unambiguous alphanumerics. Azure accepts up to 128 printable ASCII.
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'.ToCharArray()
    $psk = -join (1..40 | ForEach-Object { $alphabet[[Security.Cryptography.RandomNumberGenerator]::GetInt32($alphabet.Length)] })
    $base += @('--parameters', "sharedKey=$psk")
}
try {
    $validation = Invoke-L05Az (@('deployment', 'sub', 'validate') + $base)
    [void](Write-L05Evidence "$($Lab.ToLowerInvariant())-arm-validation" ($validation | Select-Object -ExcludeProperty properties))
    $preview = Invoke-L05Az (@('deployment', 'sub', 'what-if') + $base + @('--result-format', 'ResourceIdOnly', '--no-pretty-print'))
    [void](Write-L05Evidence "$($Lab.ToLowerInvariant())-what-if" $preview)
    $deletes = @($preview.changes | Where-Object changeType -eq 'Delete')
    if ($deletes.Count) { throw "What-if contains $($deletes.Count) deletion(s). Nothing was deployed." }
    $preview.changes | ForEach-Object { '{0,-10} {1}' -f $_.changeType, ($_.resourceId -replace '^/subscriptions/[^/]+', '') } | Out-Host
    if (-not $Deploy) { Write-Host "Preview only. Re-run with -Deploy to create the $Lab lab."; return }
    $started = Get-Date
    $result = Invoke-L05Az (@('deployment', 'sub', 'create') + $base)
    [void](Write-L05Evidence "$($Lab.ToLowerInvariant())-deployment" ([ordered]@{ state = $result.properties.provisioningState; duration = $result.properties.duration; outputs = $result.properties.outputs.lab.value }))
    if ($result.properties.provisioningState -ne 'Succeeded') { throw 'ARM did not report success.' }
    Write-Host ("$Lab lab deployed in {0:N0} minutes. Remove it with Remove-L05Bounded.ps1 -Lab $Lab when the session ends." -f ((Get-Date) - $started).TotalMinutes)
}
finally { $psk = $null; $base = $null }
