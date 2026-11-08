<#
.SYNOPSIS
Restores Lesson 3 outbound management connectivity, then starts its private runner.
.DESCRIPTION
Explicit NAT is required before start; the VM has no inbound public IP or open SSH rule.
#>
. (Join-Path $PSScriptRoot 'L03.Cloud.Common.ps1')
Assert-L03Context
$rg=$script:L03Config.resourceGroup
[void](Assert-L03Group $rg)
$existing=@(Invoke-L03Az @('network','nat','gateway','list','--resource-group',$rg,'--subscription',$script:L03Config.subscriptionId)|Where-Object name -EQ 'nat-sc500-l03-egress')
if($existing.Count -eq 1){
    $m=$existing[0]|ConvertTo-Json -Depth 20|ConvertFrom-Json -AsHashtable
    if($m.tags.managedBy -ne 'sc500-l03-iac' -or $m.tags.lifecycle -ne 'rehearsal-only'){throw 'Existing NAT ownership does not match.'}
    $natId=$existing[0].id
} else {
    $result=Invoke-L03Az @('deployment','group','create','--resource-group',$rg,'--name','sc500-l03-egress','--template-file',(Join-Path $script:L03Root 'infra/lesson-03/egress.bicep'),'--parameters',('location='+$script:L03Config.location),'--subscription',$script:L03Config.subscriptionId)
    $natId=$result.properties.outputs.natId.value
}
if(-not $natId.EndsWith('/natGateways/nat-sc500-l03-egress')){throw 'Unexpected NAT resource binding.'}
# Consecutive demo sections reuse a running, owned fixture instead of repeating slow management writes.
$subnet=Invoke-L03Az @('network','vnet','subnet','show','--vnet-name','vnet-sc500-l03','--name','runner','--resource-group',$rg,'--subscription',$script:L03Config.subscriptionId)
if(-not $subnet.PSObject.Properties['natGateway'] -or -not $subnet.natGateway -or $subnet.natGateway.id -ne $natId){
    [void](Invoke-L03Az @('network','vnet','subnet','update','--vnet-name','vnet-sc500-l03','--name','runner','--resource-group',$rg,'--nat-gateway',$natId,'--subscription',$script:L03Config.subscriptionId))
}
$vm=Invoke-L03Az @('vm','show','--show-details','--name',$script:L03Config.vmName,'--resource-group',$rg,'--subscription',$script:L03Config.subscriptionId)
if($vm.powerState -ne 'VM running'){
    [void](Invoke-L03Az @('vm','start','--name',$script:L03Config.vmName,'--resource-group',$rg,'--subscription',$script:L03Config.subscriptionId))
}
Write-Host 'Lesson 3 runner started with private Key Vault connectivity and temporary management egress.'
