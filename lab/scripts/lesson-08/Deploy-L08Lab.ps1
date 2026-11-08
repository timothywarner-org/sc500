<#
.SYNOPSIS
    Previews, or deploys, the retained SC-500 Lesson 8 servers lab.

.DESCRIPTION
    Default run: the read-only preflight (group owner, VM sizes, vCPU quota, EncryptionAtHost,
    Defender for Servers Plan 2, the budget API, same names elsewhere), then the image version and
    the lab admin's SSH public key, then ARM validation and what-if, saved as private evidence.
    Nothing is created. docs/CONTOSO-AZURE-DEPLOYMENT.md, steps 2 to 4.

    With -Deploy, one subscription-scope deployment creates rg-servers-prod-eastus2 and its budget:
      - vnet-servers-prod-eastus2-001 with snet-servers (NSG: SSH only from inside the VNet) and
        snet-legacy.
      - bas-servers-prod-eastus2-001, Bastion Developer (free, portal-only).
      - vm-servicehub-prod-001: Trusted Launch with Secure Boot and vTPM, the Guest Attestation
        extension (integrity monitoring), encryption at host, a system-assigned identity and the
        machine configuration extension. No public IP.
      - vm-datacenter-prod-001 (host name datacenter-001): prepared by cloud-init to behave like
        an on-premises server for Azure Arc (guest agent off, IMDS blocked, Connected Machine agent
        installed but not connected), with Defender for Servers off for this VM resource.
      - Two policy assignments on the group: the Linux security baseline through machine
        configuration (Arc machines included), and encryption at host (audit).
      - A daily 23:00 Central auto-shutdown schedule on each VM, and budget-rg-servers-prod-eastus2.

    The legacy app server (public IP, JIT) is bounded; Deploy-L08Bounded.ps1 creates it. The VMs
    are left running so Defender and machine configuration can report.

    Idempotent. It changes nothing outside the lesson resource group: Defender plans are read, not
    written (Set-L08DefenderWindow.ps1 owns them).

.PARAMETER Deploy
    Create or update the resources after the preview passes.

.PARAMETER Soak
    Deploy the auto-shutdown schedules Disabled, so the VMs run until the take. Agentless scanning
    runs once a day and skips a machine that's stopped during its cycle. The next deploy without
    -Soak turns the schedules back on.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Deploy-L08Lab.ps1

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Deploy-L08Lab.ps1 -Deploy -Soak

.NOTES
    Cost: see infra/lesson-08/config.json. Retained baseline is about 0.17 USD a day with the VMs
    deallocated. Bastion Developer, budgets and shutdown schedules have no charge.
#>
[CmdletBinding()]
param([switch]$Deploy, [switch]$Soak)
. (Join-Path $PSScriptRoot 'L08.Common.ps1')

[void](Assert-L08Context)
$cfg = $script:L08Config
[void](Test-L08Preflight)

# A soak keeps the schedule resources (the guardrail exists) but deploys them Disabled.
$shutdown = [ordered]@{ enabled = ($cfg.autoShutdown.enabled -and -not $Soak); time = $cfg.autoShutdown.time; timeZoneId = $cfg.autoShutdown.timeZoneId }

$b64File = { param($p) [Convert]::ToBase64String([IO.File]::ReadAllBytes($p)) }
$values = [ordered]@{
    location          = $cfg.location
    resourceGroupName = $cfg.resourceGroup
    names             = $cfg.names
    addressPlan       = $cfg.addressPlan
    vmSizes           = $cfg.vmSizes
    adminUsername     = $cfg.adminUsername
    sshPublicKey      = Get-L08AdminPublicKey
    imageVersion      = Get-L08ImageVersion
    appCustomData     = & $b64File (Join-Path $script:L08Lab 'infra/lesson-08/app-cloud-init.yaml')
    onpremCustomData  = & $b64File (Join-Path $script:L08Lab 'infra/lesson-08/onprem-cloud-init.yaml')
    policyDefinitions = $cfg.policyDefinitions
    tags              = $cfg.tags
    budget            = $cfg.budget
    autoShutdown      = $shutdown
}
$parameters = [ordered]@{}; foreach ($k in $values.Keys) { $parameters[$k] = @{ value = $values[$k] } }
[void][IO.Directory]::CreateDirectory($script:L08State)
$paramsPath = Join-Path $script:L08State 'deployment.parameters.json'
[ordered]@{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = $parameters } |
    ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $paramsPath -Encoding utf8

$template = Join-Path $script:L08Lab 'infra/lesson-08/main.bicep'
$base = @('--location', $cfg.location, '--name', $cfg.deploymentName, '--template-file', $template, '--parameters', ('@' + $paramsPath))
$validation = Invoke-L08Az (@('deployment', 'sub', 'validate') + $base)
[void](Write-L08Evidence 'arm-validation' ($validation | Select-Object -ExcludeProperty properties))
$preview = Invoke-L08Az (@('deployment', 'sub', 'what-if') + $base + @('--result-format', 'ResourceIdOnly', '--no-pretty-print'))
[void](Write-L08Evidence 'what-if' $preview)
$deletes = @($preview.changes | Where-Object changeType -eq 'Delete')
if ($deletes.Count) { throw "What-if contains $($deletes.Count) deletion(s). Nothing was deployed." }
$preview.changes | ForEach-Object { '{0,-10} {1}' -f $_.changeType, ($_.resourceId -replace '^/subscriptions/[^/]+', '') } | Out-Host
if (-not $Deploy) { Write-Host 'Preview only. Re-run with -Deploy to create the Lesson 8 lab.'; return }

$started = Get-Date
$result = Invoke-L08Az (@('deployment', 'sub', 'create') + $base)
[void](Write-L08Evidence 'deployment' ([ordered]@{ state = $result.properties.provisioningState; duration = $result.properties.duration; soak = [bool]$Soak; outputs = $result.properties.outputs.lab.value }))
if ($result.properties.provisioningState -ne 'Succeeded') { throw 'ARM did not report success.' }
Write-Host ("Retained lab deployed in {0:N0} minutes. The VMs are running." -f ((Get-Date) - $started).TotalMinutes)
Set-L08DiskTags -VmName $cfg.names.appVm, $cfg.names.onpremVm
if ($Soak) { Write-Host 'Soak: the shutdown schedules are Disabled. Redeploy without -Soak after the take, then Start-L08Lab.ps1 -Stop.' }
Write-Host "Bastion's private key file for contosoadmin: $(Get-L08AdminKeyPath)"
