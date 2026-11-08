<#
.SYNOPSIS
    Creates the bounded legacy VM for SC-500 Lesson 8 demos 8.1 and 8.2.

.DESCRIPTION
    the legacy app server (vm-legacyapp-prod-001) is the server Contoso hasn't modernized: a public IP, the Standard security
    type, no encryption at host, and an NSG rule that lets the operator's current IP reach SSH at
    any time. Demo 8.2 replaces that standing access with just-in-time access; demo 8.1 shows it
    as the encryption-at-host policy's exception.

    Default run: what-if only. -Deploy creates it (a few minutes). It bills about 0.016 USD an
    hour until Remove-L08Bounded.ps1 deletes it and its JIT policy.

.PARAMETER Deploy
    Create or update the legacy VM after the preview passes.

.PARAMETER Soak
    Deploy the legacy VM's shutdown schedule Disabled, so it keeps running until the take. Without
    it, the schedule deallocates the VM Central and card 2.2's probe would print False.
    The next deploy without -Soak turns the guardrail back on.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Deploy-L08Bounded.ps1 -Deploy

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Deploy-L08Bounded.ps1 -Deploy -Soak
#>
[CmdletBinding()]
param([switch]$Deploy, [switch]$Soak)
. (Join-Path $PSScriptRoot 'L08.Common.ps1')

[void](Assert-L08Context)
$cfg = $script:L08Config
$lab = Get-L08Outputs

$values = [ordered]@{
    location         = $cfg.location
    names            = $cfg.names
    addressPlan      = $cfg.addressPlan
    vmSize           = $cfg.vmSizes.legacy
    adminUsername    = $cfg.adminUsername
    sshPublicKey     = Get-L08AdminPublicKey
    imageVersion     = Get-L08ImageVersion
    operatorPublicIp = Get-L08OperatorIp
    legacySubnetId   = $lab.legacySubnetId
    tags             = $cfg.tags
    # The legacy server is bounded and short-lived. Its schedule always exists; -Soak deploys it
    # Disabled for the night before a take, the same way Deploy-L08Lab.ps1 -Soak does.
    autoShutdown     = [ordered]@{ enabled = ($cfg.autoShutdown.enabled -and -not $Soak); time = $cfg.autoShutdown.time; timeZoneId = $cfg.autoShutdown.timeZoneId }
}
$parameters = [ordered]@{}; foreach ($k in $values.Keys) { $parameters[$k] = @{ value = $values[$k] } }
$paramsPath = Join-Path $script:L08State 'legacy.parameters.json'
[ordered]@{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = $parameters } |
    ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $paramsPath -Encoding utf8

$template = Join-Path $script:L08Lab 'infra/lesson-08/legacy.bicep'
$base = @('--resource-group', $cfg.resourceGroup, '--name', $cfg.legacyDeploymentName, '--template-file', $template, '--parameters', ('@' + $paramsPath))
$preview = Invoke-L08Az (@('deployment', 'group', 'what-if') + $base + @('--result-format', 'ResourceIdOnly', '--no-pretty-print'))
[void](Write-L08Evidence 'legacy-what-if' $preview)
$deletes = @($preview.changes | Where-Object changeType -eq 'Delete')
if ($deletes.Count) { throw "What-if contains $($deletes.Count) deletion(s). Nothing was deployed." }
$preview.changes | ForEach-Object { '{0,-10} {1}' -f $_.changeType, ($_.resourceId -replace '^/subscriptions/[^/]+', '') } | Out-Host
if (-not $Deploy) { Write-Host 'Preview only. Re-run with -Deploy to create the legacy VM.'; return }

$started = Get-Date
$result = Invoke-L08Az (@('deployment', 'group', 'create') + $base)
if ($result.properties.provisioningState -ne 'Succeeded') { throw 'ARM did not report success.' }
$out = $result.properties.outputs
Set-L08DiskTags -VmName $cfg.names.legacyVm
[void](Write-L08Evidence 'legacy-deployment' ([ordered]@{ state = $result.properties.provisioningState; duration = $result.properties.duration; vm = $out.legacyVmName.value }))
Write-Host ("Legacy VM deployed in {0:N0} minutes at its public IP. It bills until Remove-L08Bounded.ps1 deletes it." -f ((Get-Date) - $started).TotalMinutes)
