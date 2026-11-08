<#
.SYNOPSIS
Previews or deploys the isolated Lesson 3 lab in the course lab subscription named by infra/lesson-03/config.json.
.DESCRIPTION
Defaults to validation and what-if. Deploy uses only the two lesson-owned groups.
The runner public key is generated in memory; no SSH private key is saved or needed.
.EXAMPLE
./scripts/lesson-03/Deploy-L03Lab.ps1 -Deploy
#>
param([switch]$Deploy)
. (Join-Path $PSScriptRoot 'L03.Cloud.Common.ps1')
Assert-L03Context
foreach($rg in @($script:L03Config.resourceGroup,$script:L03Config.policyGroup)){[void](Assert-L03Group $rg -AllowAbsent)}
$stateDir=Join-Path $script:L03Root '.azure/lesson-03'
[void][IO.Directory]::CreateDirectory($stateDir)
$paramsPath=Join-Path $stateDir 'deployment.parameters.json'
if(-not(Test-Path $paramsPath)){
    $definitions=Invoke-L03Az @('policy','definition','list','--subscription',$script:L03Config.subscriptionId)
    $allowed=@($definitions | Where-Object { $_.displayName -eq 'Allowed locations' -and $_.policyType -eq 'BuiltIn' })
    if($allowed.Count -ne 1){throw 'Exactly one built-in Allowed locations definition must resolve.'}
    $role=@(Invoke-L03Az @('role','definition','list','--name','Key Vault Secrets User','--subscription',$script:L03Config.subscriptionId))
    if($role.Count -ne 1){throw 'Key Vault Secrets User could not be resolved unambiguously.'}
    $image=Invoke-L03Az @('vm','image','show','--urn','Canonical:ubuntu-24_04-lts:server:latest','--location',$script:L03Config.location,'--subscription',$script:L03Config.subscriptionId)
    # SSH is disabled at the network boundary. Discarding the private key prevents an unused credential file.
    $rsa=[Security.Cryptography.RSA]::Create(3072)
    try {
        $key=$rsa.ExportParameters($false)
        $stream=[IO.MemoryStream]::new()
        foreach($part in @([Text.Encoding]::ASCII.GetBytes('ssh-rsa'),$key.Exponent,([byte[]]@(0)+$key.Modulus))){
            $bytes=[byte[]]$part;$length=[BitConverter]::GetBytes([uint32]$bytes.Length);[Array]::Reverse($length)
            $stream.Write($length);$stream.Write($bytes)
        }
        $publicKey='ssh-rsa '+[Convert]::ToBase64String($stream.ToArray())+' sc500-run-command-only'
        $stream.Dispose()
    } finally {$rsa.Dispose()}
    $values=@{location=$script:L03Config.location;vmSize=$script:L03Config.vmSize;imageVersion=$image.name;sshPublicKey=$publicKey;allowedLocationsPolicyId=$allowed[0].id;secretsUserRoleId=$role[0].id}
    $parameters=@{};foreach($key in $values.Keys){$parameters[$key]=@{value=$values[$key]}}
    @{ '$schema'='https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#';contentVersion='1.0.0.0';parameters=$parameters}|ConvertTo-Json -Depth 10|Set-Content $paramsPath -Encoding utf8
}
$file=Join-Path $script:L03Root 'infra/lesson-03/main.bicep'
$argsBase=@('--subscription',$script:L03Config.subscriptionId,'--location',$script:L03Config.location,'--name',$script:L03Config.deploymentName,'--template-file',$file,'--parameters',('@'+$paramsPath))
$validation=Invoke-L03Az (@('deployment','sub','validate')+$argsBase)
[void](Write-L03Evidence 'arm-validation' $validation)
$preview=Invoke-L03Az (@('deployment','sub','what-if')+$argsBase+@('--result-format','FullResourcePayloads','--no-pretty-print'))
[void](Write-L03Evidence 'what-if' $preview)
if(@($preview.changes|Where-Object changeType -EQ 'Delete').Count -gt 0){throw 'Preview contains a deletion. No deployment was attempted.'}
Write-Host 'Bicep and ARM validation completed. Preview saved in the private lesson evidence folder.'
if(-not $Deploy){Write-Host 'No resources deployed. Use -Deploy for the reviewed lesson scope.';return}
# Existing user authorization covers this isolated, retained lab; no paid subscription plan is changed.
try {
    $result=Invoke-L03Az (@('deployment','sub','create')+$argsBase)
    [void](Write-L03Evidence 'deployment' $result)
    if($result.properties.provisioningState -ne 'Succeeded'){throw 'ARM did not report a successful deployment.'}
    # The VM create API rejected its advertised implicit disk control. Apply and read back the supported disk update API instead.
    $disk=Invoke-L03Az @('disk','update','--name','disk-sc500-l03-runner','--resource-group',$script:L03Config.resourceGroup,'--network-access-policy','DenyAll','--public-network-access','Disabled','--subscription',$script:L03Config.subscriptionId)
    [void](Write-L03Evidence 'disk-export-controls' $disk)
    if($disk.networkAccessPolicy -ne 'DenyAll' -or $disk.publicNetworkAccess -ne 'Disabled'){throw 'Managed disk export controls did not read back as intended.'}
    $result.properties.outputs|ConvertTo-Json -Depth 20|Set-Content (Join-Path $stateDir 'outputs.json') -Encoding utf8
    Write-Host 'Lesson 3 infrastructure deployed. Run the preparation and request probes before recording.'
} catch {
    # A partial deployment can still have running compute. Preserve its resources but stop its costs.
    $original=$_
    try{& (Join-Path $PSScriptRoot 'Stop-L03Lab.ps1')}catch{Write-Warning ('Stop also needs attention: '+$_.Exception.Message)}
    throw $original
}
