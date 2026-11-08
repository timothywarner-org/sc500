<#
.SYNOPSIS
    Previews, or deploys, the retained SC-500 Lesson 6 private connectivity lab in the subscription
    infra/lesson-06/config.json pins.

.DESCRIPTION
    Default run: resolves the operator, role IDs, image version, and SSH public key, then runs
    ARM validation and what-if and saves both as private evidence. Nothing is created.
    With -Deploy: creates rg-servicehub-prod-eastus2 (hub and ServiceHub VNets, the records storage
    account with Entra-only access, the privatelink.blob.core.windows.net zone linked to both
    VNets, the ServiceHub app VM with its managed identity, and the field-office client
    identity), then seeds the synthetic record with the operator's Entra sign-in.

    The result is CTSO-L06-BASELINE: public network access Enabled on the records account and no
    private endpoint. That exposure is the demo 6.1 fault. The VM is left running; run
    Start-L06Lab.ps1 -Stop when you're done.

    Idempotent. Redeploying resets public network access to Enabled but doesn't delete a private
    endpoint that demo 6.1 created; Reset-L06Lab.ps1 does both.

.PARAMETER Deploy
    Create or update the resources after the preview passes.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Deploy-L06Lab.ps1

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Deploy-L06Lab.ps1 -Deploy

.NOTES
    Cost: see infra/lesson-06/config.json. Retained baseline is roughly 0.10 USD a day with the VM
    deallocated. This script creates no load balancer, DNS resolver, or Windows VM.
#>
[CmdletBinding()]
param([switch]$Deploy)
. (Join-Path $PSScriptRoot 'L06.Common.ps1')

$account = Assert-L06Context
$cfg = $script:L06Config

# A group with this name that another lesson owns would mean a collision, not a redeploy.
if (Invoke-L06Az @('group', 'exists', '--name', $cfg.resourceGroup)) {
    $rg = Invoke-L06Az @('group', 'show', '--name', $cfg.resourceGroup)
    if ($rg.tags.managedBy -ne $cfg.managedBy) { throw "$($cfg.resourceGroup) exists but isn't tagged managedBy=$($cfg.managedBy). Stopping." }
}

$me = Invoke-L06Az -NoSubscription @('ad', 'signed-in-user', 'show')
function Get-RoleId([string]$Name) {
    $r = @(Invoke-L06Az @('role', 'definition', 'list', '--name', $Name))
    if ($r.Count -ne 1) { throw "$Name did not resolve to exactly one role definition." }
    return $r[0].name
}

$values = [ordered]@{
    location                  = $cfg.location
    resourceGroupName         = $cfg.resourceGroup
    operatorObjectId          = $me.id
    sshPublicKey              = Get-L06SshPublicKey
    imageVersion              = Get-L06ImageVersion
    vmSize                    = $cfg.vmSize
    addressPlan               = $cfg.addressPlan
    ports                     = $cfg.ports
    recordsContainer          = $cfg.recordsContainer
    privateDnsZoneName        = $cfg.privateDnsZone
    blobDataReaderRoleId      = Get-RoleId 'Storage Blob Data Reader'
    blobDataContributorRoleId = Get-RoleId 'Storage Blob Data Contributor'
    managedBy                 = $cfg.managedBy
    baseline                  = $cfg.baseline
    # Every resource name, from config.json (Cloud Adoption Framework naming guidance, https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming).
    names                     = $cfg.names
    naming                    = $cfg.naming
}
$parameters = [ordered]@{}; foreach ($k in $values.Keys) { $parameters[$k] = @{ value = $values[$k] } }
$paramsPath = Join-Path $script:L06State 'deployment.parameters.json'
[ordered]@{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = $parameters } |
    ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $paramsPath -Encoding utf8

$template = Join-Path $script:L06Lab 'infra/lesson-06/main.bicep'
$base = @('--location', $cfg.location, '--name', $cfg.deploymentName, '--template-file', $template, '--parameters', ('@' + $paramsPath))
$validation = Invoke-L06Az (@('deployment', 'sub', 'validate') + $base)
[void](Write-L06Evidence 'arm-validation' $validation)
$preview = Invoke-L06Az (@('deployment', 'sub', 'what-if') + $base + @('--result-format', 'ResourceIdOnly', '--no-pretty-print'))
[void](Write-L06Evidence 'what-if' $preview)
$deletes = @($preview.changes | Where-Object changeType -eq 'Delete')
if ($deletes.Count) { throw "What-if contains $($deletes.Count) deletion(s). Nothing was deployed." }
$preview.changes | ForEach-Object { '{0,-10} {1}' -f $_.changeType, ($_.resourceId -replace '^/subscriptions/[^/]+', '') } | Out-Host
if (-not $Deploy) { Write-Host 'Preview only. Re-run with -Deploy to create the Lesson 6 lab.'; return }

$result = Invoke-L06Az (@('deployment', 'sub', 'create') + $base)
[void](Write-L06Evidence 'deployment' $result)
if ($result.properties.provisioningState -ne 'Succeeded') { throw 'ARM did not report success.' }
$lab = $result.properties.outputs.lab.value

# Seed the synthetic record with the operator's Entra sign-in. A new data role can take a few
# minutes to reach the storage service, so retry instead of failing on the first 403.
$seed = Join-Path $script:L06Lab ('infra/lesson-06/seed/' + $cfg.seedBlob)
for ($i = 1; $i -le 12; $i++) {
    $up = Invoke-L06Az -NoSubscription -Raw -AllowFailure @('storage', 'blob', 'upload', '--account-name', $lab.recordsAccountName,
        '--container-name', $cfg.recordsContainer, '--name', $cfg.seedBlob, '--file', $seed, '--auth-mode', 'login', '--overwrite')
    if ($up.ExitCode -eq 0) { Write-Host "Seeded $($cfg.seedBlob)."; break }
    if ($i -eq 12) { throw "Seeding failed after role propagation retries: $($up.Stderr.Trim())" }
    Write-Host "Waiting for the data role to apply ($i of 12)."
    Start-Sleep -Seconds 20
}
Write-Host "Deployed $($lab.resourceGroup). The VM is running; Start-L06Lab.ps1 -Stop deallocates it."
