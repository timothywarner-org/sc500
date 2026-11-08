<#
.SYNOPSIS
    Previews, or deploys, the retained SC-500 Lesson 7 perimeter lab and its firewall policy.

.DESCRIPTION
    Default run: runs the read-only preflight (group owner, VM SKU and quota, Key Vault name,
    budget API, same-named resources elsewhere), resolves the operator, role IDs, image version,
    SSH public key, and the TLS inspection CA's public certificates, then runs ARM validation and
    what-if for the retained template and saves all three as private evidence. Nothing is created.
    Test-L07Templates.ps1 runs the offline checks (Bicep build, linter, CAF compliance) first.

    With -Deploy:
      1. Creates rg-perimeter-shared-eastus2 (names from infra/lesson-07/config.json): the hub
         VNet (AzureFirewallSubnet), the production and test spokes peered only to the hub, route
         tables that send 0.0.0.0/0 to the firewall's private IP, NSGs, the two app VMs with their
         23:00 auto-shutdown, the Log Analytics workspace, the Key Vault and its audit logs, the
         firewall's user-assigned identity, the firewall's public IP, and a monthly budget on the
         resource group.
      2. On the first run only, builds the inspection CA in memory and imports the intermediate
         into Key Vault. Only the two PUBLIC certificates are saved locally (they go into the VMs'
         trust store). The root's private key is discarded after signing; the intermediate's
         private key exists only inside Key Vault.
      3. Deploys the firewall policy (CTSO-L07-BASELINE: threat intelligence and IDPS in Alert
         mode) with its DNAT, network, and application rule collection groups.

    The firewall itself is bounded; Deploy-L07Bounded.ps1 creates it. The VMs are left running;
    run Start-L07Lab.ps1 -Stop when you're done.

    Idempotent. The DNAT rule and the Key Vault firewall allow the operator's CURRENT public IP,
    so re-run this after your address changes.

.PARAMETER Deploy
    Create or update the resources after the preview passes.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Deploy-L07Lab.ps1

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Deploy-L07Lab.ps1 -Deploy

.NOTES
    Cost: see infra/lesson-07/config.json. Retained baseline is roughly 0.30 USD a day with the
    VMs deallocated. This script creates no firewall and no DDoS plan.
#>
[CmdletBinding()]
param([switch]$Deploy)
. (Join-Path $PSScriptRoot 'L07.Common.ps1')

[void](Assert-L07Context)
$cfg = $script:L07Config

# Read-only preflight: a group another lesson owns, a blocked VM size, no quota, a taken vault
# name, or no budget API would each fail the deployment halfway. Stop here instead.
[void](Test-L07Preflight)

$me = Invoke-L07Az -NoSubscription @('ad', 'signed-in-user', 'show')
function Get-RoleId([string]$Name) {
    $r = @(Invoke-L07Az @('role', 'definition', 'list', '--name', $Name))
    if ($r.Count -ne 1) { throw "$Name did not resolve to exactly one role definition." }
    return $r[0].name
}

# The CA's public half is saved so a redeploy puts the same trust anchors in the same customData
# (Azure refuses to change customData on an existing VM). The private halves are never saved.
$caPath = Join-Path $script:L07State 'inspection-ca-public.json'
$newCa = $null
if (Test-Path -LiteralPath $caPath) { $ca = Get-Content -LiteralPath $caPath -Raw | ConvertFrom-Json }
elseif ($Deploy) {
    $newCa = New-L07InspectionCa
    $ca = [pscustomobject]@{
        createdUtc       = [DateTime]::UtcNow.ToString('o')
        note             = 'Public certificates only. The root private key was discarded after signing; the intermediate private key exists only in Key Vault.'
        rootPem          = $newCa.RootPem
        rootThumbprint   = $newCa.RootThumbprint
        interPem         = $newCa.InterPem
        interThumbprint  = $newCa.InterThumbprint
        interNotAfterUtc = $newCa.InterNotAfterUtc
    }
    [void][IO.Directory]::CreateDirectory($script:L07State)
    $ca | ConvertTo-Json | Set-Content -LiteralPath $caPath -Encoding utf8
}
else {
    # Preview only: placeholder certificates keep what-if honest about shape without minting a CA.
    $ca = [pscustomobject]@{ rootPem = '-----PREVIEW-----'; interPem = '-----PREVIEW-----' }
}
$b64 = { param($s) [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($s)) }

$operatorIp = Get-L07OperatorIp
$values = [ordered]@{
    location                          = $cfg.location
    resourceGroupName                 = $cfg.resourceGroup
    operatorObjectId                  = $me.id
    operatorPublicIp                  = $operatorIp
    sshPublicKey                      = Get-L07SshPublicKey
    imageVersion                      = Get-L07ImageVersion
    vmSize                            = $cfg.vmSize
    names                             = $cfg.names
    addressPlan                       = $cfg.addressPlan
    ports                             = $cfg.ports
    tests                             = $cfg.tests
    rootCaB64                         = & $b64 $ca.rootPem
    interCaB64                        = & $b64 $ca.interPem
    keyVaultSecretsUserRoleId         = Get-RoleId 'Key Vault Secrets User'
    keyVaultCertificatesOfficerRoleId = Get-RoleId 'Key Vault Certificates Officer'
    tags                              = $cfg.tags
    budget                            = $cfg.budget
    autoShutdown                      = $cfg.autoShutdown
}
$parameters = [ordered]@{}; foreach ($k in $values.Keys) { $parameters[$k] = @{ value = $values[$k] } }
[void][IO.Directory]::CreateDirectory($script:L07State)
$paramsPath = Join-Path $script:L07State 'deployment.parameters.json'
[ordered]@{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = $parameters } |
    ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $paramsPath -Encoding utf8

$template = Join-Path $script:L07Lab 'infra/lesson-07/main.bicep'
$base = @('--location', $cfg.location, '--name', $cfg.deploymentName, '--template-file', $template, '--parameters', ('@' + $paramsPath))
$validation = Invoke-L07Az (@('deployment', 'sub', 'validate') + $base)
[void](Write-L07Evidence 'arm-validation' ($validation | Select-Object -ExcludeProperty properties))
$preview = Invoke-L07Az (@('deployment', 'sub', 'what-if') + $base + @('--result-format', 'ResourceIdOnly', '--no-pretty-print'))
[void](Write-L07Evidence 'what-if' $preview)
$deletes = @($preview.changes | Where-Object changeType -eq 'Delete')
if ($deletes.Count) { throw "What-if contains $($deletes.Count) deletion(s). Nothing was deployed." }
$preview.changes | ForEach-Object { '{0,-10} {1}' -f $_.changeType, ($_.resourceId -replace '^/subscriptions/[^/]+', '') } | Out-Host
if (-not $Deploy) { Write-Host 'Preview only. Re-run with -Deploy to create the Lesson 7 lab.'; return }

$started = Get-Date
$result = Invoke-L07Az (@('deployment', 'sub', 'create') + $base)
[void](Write-L07Evidence 'deployment' ([ordered]@{ state = $result.properties.provisioningState; duration = $result.properties.duration; outputs = $result.properties.outputs.lab.value }))
if ($result.properties.provisioningState -ne 'Succeeded') { throw 'ARM did not report success.' }
$lab = $result.properties.outputs.lab.value
Write-Host ("Retained lab deployed in {0:N0} minutes." -f ((Get-Date) - $started).TotalMinutes)

# An OS disk created from the VM's storage profile doesn't inherit the VM's tags, and a template
# can't tag it. Copy each VM's tags onto its disk, incrementally, so every resource in the group
# answers to the same workload, env and owner tags (Test-L07Lab.ps1 checks this).
foreach ($vmId in @($lab.prodVmId, $lab.nonprodVmId)) {
    $vm = Invoke-L07Az @('vm', 'show', '--ids', $vmId)
    $pairs = @($vm.tags.PSObject.Properties | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value })
    [void](Invoke-L07Az (@('resource', 'tag', '--is-incremental', '--ids', $vm.storageProfile.osDisk.managedDisk.id, '--tags') + $pairs))
    Write-Host "Tagged $($vm.storageProfile.osDisk.name) with $($vm.name)'s tags."
}

# Inspection CA in Key Vault. A missing certificate with no fresh CA in memory means the vault
# was rebuilt after the VMs were created; their trust store can't be changed in place.
try {
    $existing = Get-L07InspectionCaCertificate -VaultUri $lab.keyVaultUri
    if ($newCa) {
        # A freshly minted pair always goes in, as a new version of the same certificate. The
        # policy is then pointed at that version's secret.
        $imported = Import-L07InspectionCa -VaultUri $lab.keyVaultUri -PfxBase64 $newCa.InterPfxBase64
        $secretId = $imported.SecretId
        [void](Write-L07Evidence 'inspection-ca-imported' ([ordered]@{ certificateId = $imported.Id; secretId = $imported.SecretId; interThumbprint = $ca.interThumbprint; rootThumbprint = $ca.rootThumbprint; expires = $imported.Expires; replacedPrevious = [bool]$existing }))
        Write-Host 'Imported the inspection CA into Key Vault.'
    }
    elseif ($existing) {
        if ($ca.interThumbprint -and $existing.x5t) {
            $kvThumb = [BitConverter]::ToString([Convert]::FromBase64String(($existing.x5t -replace '-', '+' -replace '_', '/').PadRight([math]::Ceiling($existing.x5t.Length / 4) * 4, '='))) -replace '-', ''
            if ($kvThumb -ne $ca.interThumbprint) { throw "Key Vault holds a different inspection CA ($kvThumb) than the VMs trust ($($ca.interThumbprint))." }
        }
        $secretId = $existing.sid
        Write-Host 'Inspection CA already in Key Vault; reusing it.'
    }
    else { throw "Key Vault has no inspection CA, and the VMs already trust a CA whose private key no longer exists. Remove the lab (Remove-L07Lab.ps1) and deploy it again to mint a new pair." }
}
finally { if ($newCa) { $newCa.InterPfxBase64 = $null }; $newCa = $null }

# Firewall policy. The firewall identity's Key Vault role can take a few minutes to apply, and
# the policy validates access to the CA secret, so retry instead of failing on the first try.
& (Join-Path $PSScriptRoot 'Set-L07Policy.ps1') -SecretId $secretId
Write-Host "Deployed $($lab.resourceGroup). The VMs are running; Start-L07Lab.ps1 -Stop deallocates them."
