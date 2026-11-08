<#
.SYNOPSIS
    Previews, or deploys and seeds, the SC-500 Lesson 4 storage and SQL lab in the course
    subscription.

.DESCRIPTION
    Default run: resolves the operator, workstation IP, and role IDs, then runs ARM
    validation and what-if and saves both as private evidence. Nothing is created.
    With -Deploy: creates rg-sc500-l04-data and its resources, seeds synthetic Contoso data
    into storage and SQL, and leaves the lab at the CTSO-L04-BASELINE starting state.

    Parked or open: the script reads the SqlServers and StorageAccounts plan tiers first
    (GET only). While a plan is Free it skips the one step that needs it and says so: the
    express vulnerability assessment scanner, and applying the Storage plan to the two
    accounts. Set-L04DefenderWindow.ps1 -State Open does both later. Nothing here turns a
    paid plan on.

    Idempotent. A second run updates the same resources, because names come from a
    deterministic suffix and the seed steps overwrite or skip existing items.

.PARAMETER Deploy
    Create or update the resources after the preview passes.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-04\Deploy-L04Lab.ps1

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-04\Deploy-L04Lab.ps1 -Deploy

.NOTES
    Cost: about 0.20 USD a day parked (the Basic database plus cents of storage and Log
    Analytics; see infra/lesson-04/config.json). With the Defender window open, the
    subscription's plans also bill for these accounts and the server. This script changes
    no subscription-wide plan.
#>
[CmdletBinding()]
param([switch]$Deploy)
. (Join-Path $PSScriptRoot 'L04.Common.ps1')

$account = Assert-L04Context
$cfg = $script:L04Config

# A group from another lesson with this name would mean a collision, not a redeploy.
$exists = Invoke-L04Az @('group', 'exists', '--name', $cfg.resourceGroup)
if ($exists) {
    $rg = Invoke-L04Az @('group', 'show', '--name', $cfg.resourceGroup)
    if ($rg.tags.managedBy -ne $cfg.managedBy) { throw "$($cfg.resourceGroup) exists but isn't tagged managedBy=$($cfg.managedBy). Stopping." }
}

# Resolve every environment value at run time. Role IDs are looked up by name so a GUID
# typo can't silently grant a different role.
$me = Invoke-L04Az -NoSubscription @('ad', 'signed-in-user', 'show')   # Graph call: no subscription argument
$ip = Get-L04OperatorIp
$reader = @(Invoke-L04Az @('role', 'definition', 'list', '--name', 'Storage Blob Data Reader'))
$owner = @(Invoke-L04Az @('role', 'definition', 'list', '--name', 'Storage Blob Data Owner'))
if ($reader.Count -ne 1 -or $owner.Count -ne 1) { throw 'Storage Blob Data role definitions did not resolve to exactly one each.' }

# Read, never change, the two plans this deployment depends on.
$sqlPlan = Get-L04PlanTier SqlServers
$storagePlan = Get-L04PlanTier StorageAccounts
$vaEnabled = $sqlPlan -eq 'Standard'
Write-Host "Defender plans: SqlServers $sqlPlan, StorageAccounts $storagePlan."
if (-not $vaEnabled) { Write-Host 'SKIP vulnerability assessment scanner: the SqlServers plan is Free (parked). The Defender window turns it on.' }

[void][IO.Directory]::CreateDirectory($script:L04State)
$paramsPath = Join-Path $script:L04State 'deployment.parameters.json'
$values = [ordered]@{
    location              = $cfg.location
    resourceGroupName     = $cfg.resourceGroup
    operatorObjectId      = $me.id
    operatorUpn           = $me.userPrincipalName
    operatorIp            = $ip
    sqlLocation           = $cfg.sqlLocation
    blobDataReaderRoleId  = $reader[0].name
    blobDataOwnerRoleId   = $owner[0].name
    vulnerabilityAssessmentEnabled = $vaEnabled
}
$parameters = [ordered]@{}; foreach ($k in $values.Keys) { $parameters[$k] = @{ value = $values[$k] } }
[ordered]@{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = $parameters } |
    ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $paramsPath -Encoding utf8

$template = Join-Path $script:L04Lab 'infra/lesson-04/main.bicep'
$base = @('--location', $cfg.location, '--name', $cfg.deploymentName, '--template-file', $template, '--parameters', ('@' + $paramsPath))
$validation = Invoke-L04Az (@('deployment', 'sub', 'validate') + $base)
[void](Write-L04Evidence 'arm-validation' $validation)
$preview = Invoke-L04Az (@('deployment', 'sub', 'what-if') + $base + @('--result-format', 'ResourceIdOnly', '--no-pretty-print'))
[void](Write-L04Evidence 'what-if' $preview)
$deletes = @($preview.changes | Where-Object changeType -eq 'Delete')
if ($deletes.Count) { throw "What-if contains $($deletes.Count) deletion(s). Nothing was deployed." }
$preview.changes | ForEach-Object { '{0,-10} {1}' -f $_.changeType, ($_.resourceId -replace '^/subscriptions/[^/]+', '') } | Out-Host
if (-not $Deploy) { Write-Host 'Preview only. Re-run with -Deploy to create the Lesson 4 lab.'; return }

$result = Invoke-L04Az (@('deployment', 'sub', 'create') + $base)
[void](Write-L04Evidence 'deployment' $result)
if ($result.properties.provisioningState -ne 'Succeeded') { throw 'ARM did not report success.' }
$lab = $result.properties.outputs.lab.value
$lab | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $script:L04State 'outputs.json') -Encoding utf8

# Storage: seed synthetic records and put the account into its demo starting state.
Initialize-L04StorageBaseline -Lab $lab

# The Shared Key policy assignment starts in Audit, which keeps the deliberate 4.1 fault in place.
# ARM templates don't own it (Set-L04SharedKeyGuardrail.ps1 does), so a rebuild from zero creates it here.
& (Join-Path $PSScriptRoot 'Set-L04SharedKeyGuardrail.ps1') -Mode Audit | Out-Host

# SQL: a small table of synthetic service records, created as the Entra admin.
$rows = Initialize-L04SqlBaseline -Lab $lab
Write-Host "SQL seed: $rows service records."

# Pricing enablement can take up to 24 hours to reach each storage account. Apply and read
# back the existing defaults on these two accounts; no subscription plan is changed. While the
# plan is Free there is nothing to apply, and enabling an account on its own would bill it.
if ($storagePlan -eq 'Standard') { Set-L04StorageInheritance -Lab $lab }
else { Write-Host 'SKIP account protection: the StorageAccounts plan is Free (parked). The Defender window applies it.' }

[void](Write-L04Evidence 'baseline-after-deploy' @{ lab = $lab; workstationIp = $ip; operator = $me.userPrincipalName })
Write-Host 'Lesson 4 deployed and at CTSO-L04-BASELINE. Next: Test-L04Lab.ps1.'
