<#
.SYNOPSIS
Validates, previews, or deploys the retained Lesson 1 lab in your subscription.
.DESCRIPTION
Uses incremental subscription deployment. Existing non-course groups are never adopted.
Apply hardens managed disks, captures deployment output, and deallocates both VMs by default.
Private SSH material stays under the user's .ssh directory, outside this synced project.
.EXAMPLE
./scripts/Deploy-Sc500Lesson01.ps1 -Mode WhatIf
.EXAMPLE
./scripts/Deploy-Sc500Lesson01.ps1 -Mode Apply
#>
[CmdletBinding()]
param(
    [ValidateSet('Validate','WhatIf','Apply')][string]$Mode = 'WhatIf',
    [string]$SshPublicKeyPath = (Join-Path $env:USERPROFILE '.ssh/sc500_lesson01.pub'),
    [switch]$KeepRunning
)
. (Join-Path $PSScriptRoot 'Sc500.Common.ps1')
$null = Assert-Sc500Context
$config = $script:Sc500Config
& (Join-Path $PSScriptRoot 'Initialize-Sc500Prerequisites.ps1')
foreach ($name in $config.resourceGroups) {
    $exists = Invoke-Sc500Az -Arguments @('group','exists','--name',$name,'--subscription',$config.subscriptionId)
    if ($exists) { $null = Assert-Sc500OwnedGroup -Name $name }
}
if (-not (Test-Path -LiteralPath $SshPublicKeyPath)) {
    $privatePath = $SshPublicKeyPath -replace '\.pub$',''
    if ($privatePath -eq $SshPublicKeyPath -or (Test-Path -LiteralPath $privatePath)) { throw 'Provide a valid SSH public-key path; existing private keys will not be overwritten.' }
    New-Item -ItemType Directory -Path (Split-Path $privatePath -Parent) -Force | Out-Null
    & ssh-keygen -q -t ed25519 -N '' -C 'sc500-lesson01' -f $privatePath
    if ($LASTEXITCODE -ne 0) { throw 'SSH key generation failed.' }
}
$parameters = @{
    location = @{value=$config.location}
    vmSize = @{value=$config.vmSize}
    imageVersion = @{value=$config.imageVersion}
    sshPublicKey = @{value=([IO.File]::ReadAllText($SshPublicKeyPath).Trim())}
}
$parameterPath = Join-Path $script:Sc500Root '.azure/lesson01.parameters.json'
New-Item -ItemType Directory -Path (Split-Path $parameterPath -Parent) -Force | Out-Null
@{ '$schema'='https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#';contentVersion='1.0.0.0';parameters=$parameters } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $parameterPath
$template = Join-Path $script:Sc500Root 'infra/main.bicep'
$null = Invoke-Sc500Az -Arguments @('bicep','build','--file',$template,'--outfile',(Join-Path $script:Sc500Root '.azure/main.json'))
$common = @('--subscription',$config.subscriptionId,'--location',$config.location,'--name','sc500-lesson01','--template-file',$template,'--parameters',"@$parameterPath")
$validation = Invoke-Sc500Az -Arguments (@('deployment','sub','validate') + $common)
Write-Host 'ARM validation passed.'
Write-Sc500Evidence -Name 'arm-validation' -Value $validation | Write-Host
if ($Mode -eq 'Validate') { return }
$preview = Invoke-Sc500Az -Arguments (@('deployment','sub','what-if','--no-pretty-print') + $common)
Write-Sc500Evidence -Name 'what-if' -Value $preview | Write-Host
if (@($preview.changes | Where-Object changeType -eq 'Delete').Count) { throw 'What-if proposes deletion. Deployment stopped.' }
$preview.changes | Select-Object changeType,resourceId | Format-Table -AutoSize
if ($Mode -eq 'WhatIf') { Write-Host 'Preview complete. No Azure resources were created.'; return }
$deploymentFailure = $null
$deallocationFailures = [System.Collections.Generic.List[string]]::new()
try {
    $deployment = Invoke-Sc500Az -Arguments (@('deployment','sub','create') + $common)
    Write-Sc500Evidence -Name 'deployment' -Value $deployment | Write-Host
    foreach ($fixture in $config.virtualMachines) {
        # Disk export controls are disk properties, not VM inline managedDisk properties.
        $null = Assert-Sc500OwnedGroup -Name $fixture.group
        $null = Invoke-Sc500Az -Arguments @('disk','update','--subscription',$config.subscriptionId,'--resource-group',$fixture.group,'--name',('osdisk-'+$fixture.name),'--network-access-policy','DenyAll','--public-network-access','Disabled','--set',('tags.course=SC500'),('tags.managedBy='+$config.ownershipTag),('tags.lifecycle=retain-until-recording-complete'))
    }
}
catch { $deploymentFailure = $_ }
finally {
    if (-not $KeepRunning) {
        foreach ($fixture in $config.virtualMachines) {
            # A partial deployment can leave billable compute behind; attempt each owned VM independently.
            try {
                $exists = Invoke-Sc500Az -Arguments @('group','exists','--name',$fixture.group,'--subscription',$config.subscriptionId)
                if (-not $exists) { continue }
                $null = Assert-Sc500OwnedGroup -Name $fixture.group
                $vms = @(Invoke-Sc500Az -Arguments @('vm','list','--resource-group',$fixture.group,'--subscription',$config.subscriptionId))
                if (@($vms | Where-Object name -eq $fixture.name).Count) {
                    $null = Invoke-Sc500Az -Arguments @('vm','deallocate','--subscription',$config.subscriptionId,'--resource-group',$fixture.group,'--name',$fixture.name)
                }
            }
            catch { $deallocationFailures.Add("$($fixture.name): $($_.Exception.Message)") }
        }
    }
}
if ($deallocationFailures.Count) { Write-Warning ('Deallocation requires attention: '+($deallocationFailures -join '; ')) }
if ($null -ne $deploymentFailure) { throw $deploymentFailure }
if ($deallocationFailures.Count) { throw 'Baseline deployed, but not every VM was deallocated. Inspect the preceding warning.' }
Write-Host 'Baseline retained. VM compute is deallocated unless -KeepRunning was selected. Disks remain billable.'
& (Join-Path $PSScriptRoot 'Test-Sc500Lesson01.ps1')
