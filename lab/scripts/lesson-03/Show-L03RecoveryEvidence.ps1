<#
.SYNOPSIS
Shows current vault state beside dated, real Resource Guard and restore results.
.DESCRIPTION
Reads Azure and existing private receipts. It does not trigger a restore, remove
protection, grant access, or present a captured request as a newly executed request.
#>
. (Join-Path $PSScriptRoot 'L03.Cloud.Common.ps1')
Assert-L03Context
$lab=Get-L03Outputs
$vault=Invoke-L03Az @('backup','vault','show','--name',$lab.recoveryVaultName,'--resource-group',$script:L03Config.resourceGroup)
Write-Host 'CURRENT VAULT SETTINGS'
$vault.properties.securitySettings|ConvertTo-Json -Depth 8
foreach($kind in @('resource-guard-rehearsal','restore-rehearsal','completion-restored-record')){
    $file=Get-ChildItem -LiteralPath $script:L03Evidence -Filter ('*-'+$kind+'.json')|Sort-Object Name -Descending|Select-Object -First 1
    if(-not $file){throw ('Missing captured evidence: '+$kind)}
    Write-Host ('CAPTURED REHEARSAL: '+$file.Name)
    Get-Content -LiteralPath $file.FullName -Raw
}
