<#
.SYNOPSIS
    Previews, or deploys, the retained SC-500 Lesson 5 network lab in your subscription.

.DESCRIPTION
    Default run: resolves the operator, role ID, image version, and SSH public key, then runs
    ARM validation and what-if and saves both as private evidence. Nothing is created.
    With -Deploy: creates rg-sc500-l05-network (platform hub, ServiceHub spoke, NSGs, ASGs,
    four private test VMs, the AVNM definitions, a Log Analytics workspace, and the flow-log
    storage account) plus the two VNet flow logs in NetworkWatcherRG. The result is
    CTSO-L05-BASELINE: default NSG rules only, and the AVNM configuration defined but not
    deployed. The VMs are left running; run Stop-L05Lab.ps1 when you're done.

    Idempotent. The SSH public key and image version are saved under lab/.azure/lesson-05 on
    the first run and reused, because Azure refuses to change either on an existing VM.
    Redeploying resets the NSG to its default rules, which is also what Reset-L05Lab.ps1 does.

.PARAMETER Deploy
    Create or update the resources after the preview passes.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-05\Deploy-L05Lab.ps1

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-05\Deploy-L05Lab.ps1 -Deploy

.NOTES
    Cost: see infra/lesson-05/config.json. Retained baseline is roughly 0.25 USD a day with the
    VMs deallocated. This script creates no Virtual WAN, firewall, or VPN gateway.
#>
[CmdletBinding()]
param([switch]$Deploy)
. (Join-Path $PSScriptRoot 'L05.Common.ps1')

$account = Assert-L05Context
$cfg = $script:L05Config

# A group from another lesson with this name would mean a collision, not a redeploy.
if (Invoke-L05Az @('group', 'exists', '--name', $cfg.resourceGroup)) {
    $rg = Invoke-L05Az @('group', 'show', '--name', $cfg.resourceGroup)
    if ($rg.tags.managedBy -ne $cfg.managedBy) { throw "$($cfg.resourceGroup) exists but isn't tagged managedBy=$($cfg.managedBy). Stopping." }
}

$me = Invoke-L05Az -NoSubscription @('ad', 'signed-in-user', 'show')
$reader = @(Invoke-L05Az @('role', 'definition', 'list', '--name', 'Storage Blob Data Reader'))
if ($reader.Count -ne 1) { throw 'Storage Blob Data Reader did not resolve to exactly one role definition.' }

# Reuse the first run's public key and image version. The private key never existed on disk.
[void][IO.Directory]::CreateDirectory($script:L05State)
$keyPath = Join-Path $script:L05State 'ssh-public-key.txt'
if (-not (Test-Path -LiteralPath $keyPath)) { New-L05SshPublicKey | Set-Content -LiteralPath $keyPath -Encoding ascii }
$publicKey = (Get-Content -LiteralPath $keyPath -Raw).Trim()
$imagePath = Join-Path $script:L05State 'image-version.txt'
if (-not (Test-Path -LiteralPath $imagePath)) {
    $image = Invoke-L05Az @('vm', 'image', 'show', '--urn', 'Canonical:ubuntu-24_04-lts:server:latest', '--location', $cfg.location)
    $image.name | Set-Content -LiteralPath $imagePath -Encoding ascii
}
$imageVersion = (Get-Content -LiteralPath $imagePath -Raw).Trim()

$values = [ordered]@{
    location                    = $cfg.location
    resourceGroupName           = $cfg.resourceGroup
    networkWatcherResourceGroup = $cfg.networkWatcherResourceGroup
    networkWatcherName          = $cfg.networkWatcherName
    operatorObjectId            = $me.id
    sshPublicKey                = $publicKey
    imageVersion                = $imageVersion
    vmSize                      = $cfg.vmSize
    addressPlan                 = $cfg.addressPlan
    ports                       = $cfg.ports
    blobDataReaderRoleId        = $reader[0].name
    managedBy                   = $cfg.managedBy
    baseline                    = $cfg.baseline
}
$parameters = [ordered]@{}; foreach ($k in $values.Keys) { $parameters[$k] = @{ value = $values[$k] } }
$paramsPath = Join-Path $script:L05State 'deployment.parameters.json'
[ordered]@{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = $parameters } |
    ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $paramsPath -Encoding utf8

$template = Join-Path $script:L05Lab 'infra/lesson-05/main.bicep'
$base = @('--location', $cfg.location, '--name', $cfg.deploymentName, '--template-file', $template, '--parameters', ('@' + $paramsPath))
$validation = Invoke-L05Az (@('deployment', 'sub', 'validate') + $base)
[void](Write-L05Evidence 'arm-validation' $validation)
$preview = Invoke-L05Az (@('deployment', 'sub', 'what-if') + $base + @('--result-format', 'ResourceIdOnly', '--no-pretty-print'))
[void](Write-L05Evidence 'what-if' $preview)
$deletes = @($preview.changes | Where-Object changeType -eq 'Delete')
if ($deletes.Count) { throw "What-if contains $($deletes.Count) deletion(s). Nothing was deployed." }
$preview.changes | ForEach-Object { '{0,-10} {1}' -f $_.changeType, ($_.resourceId -replace '^/subscriptions/[^/]+', '') } | Out-Host
if (-not $Deploy) { Write-Host 'Preview only. Re-run with -Deploy to create the Lesson 5 lab.'; return }

$result = Invoke-L05Az (@('deployment', 'sub', 'create') + $base)
[void](Write-L05Evidence 'deployment' $result)
if ($result.properties.provisioningState -ne 'Succeeded') { throw 'ARM did not report success.' }
$lab = $result.properties.outputs.lab.value
Write-Host "Deployed $($lab.resourceGroup). The VMs are running; Stop-L05Lab.ps1 deallocates them."
