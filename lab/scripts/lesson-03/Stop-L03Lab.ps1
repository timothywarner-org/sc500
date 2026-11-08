<#
.SYNOPSIS
Deallocates the Lesson 3 runner and removes only its disposable egress charges.
.DESCRIPTION
The vault, disks, private endpoint, DNS, policies and protected backup data are retained.
NAT and its public IP are explicitly tagged rehearsal-only and checked before deletion.
#>
. (Join-Path $PSScriptRoot 'L03.Cloud.Common.ps1')
Assert-L03Context
$rg=$script:L03Config.resourceGroup
if(-not(Assert-L03Group $rg -AllowAbsent)){Write-Host 'No Lesson 3 platform group exists.';return}
$vms=@(Invoke-L03Az @('vm','list','--resource-group',$rg,'--subscription',$script:L03Config.subscriptionId))
if(@($vms|Where-Object name -EQ $script:L03Config.vmName).Count -eq 1){
    [void](Invoke-L03Az @('vm','deallocate','--name',$script:L03Config.vmName,'--resource-group',$rg,'--subscription',$script:L03Config.subscriptionId))
}
$vnets=@(Invoke-L03Az @('network','vnet','list','--resource-group',$rg,'--subscription',$script:L03Config.subscriptionId))
if(@($vnets|Where-Object name -EQ 'vnet-sc500-l03').Count -eq 1){
    $subnet=Invoke-L03Az @('network','vnet','subnet','show','--vnet-name','vnet-sc500-l03','--name','runner','--resource-group',$rg,'--subscription',$script:L03Config.subscriptionId)
    if($subnet.PSObject.Properties['natGateway'] -and $subnet.natGateway){
        [void](Invoke-L03Az @('network','vnet','subnet','update','--vnet-name','vnet-sc500-l03','--name','runner','--resource-group',$rg,'--remove','natGateway','--subscription',$script:L03Config.subscriptionId))
    }
}
$targets=@(@{name='nat-sc500-l03-egress';command=@('network','nat','gateway')},@{name='pip-sc500-l03-egress';command=@('network','public-ip')})
foreach($target in $targets){
    # Provider-specific lists returned the deployed resources when the generic ARM list did not.
    $items=@(Invoke-L03Az ($target.command+@('list','--resource-group',$rg,'--subscription',$script:L03Config.subscriptionId)))
    $item=@($items|Where-Object name -EQ $target.name)
    if($item.Count -eq 0){continue}
    $m=$item[0]|ConvertTo-Json -Depth 15|ConvertFrom-Json -AsHashtable
    if($m.tags.managedBy -ne 'sc500-l03-iac' -or $m.tags.lifecycle -ne 'rehearsal-only'){throw 'Disposable egress ownership does not match. Refusing deletion.'}
    [void](Invoke-L03Az ($target.command+@('delete','--name',$target.name,'--resource-group',$rg,'--subscription',$script:L03Config.subscriptionId)))
}
$status=@(Invoke-L03Az @('vm','list','--show-details','--resource-group',$rg,'--subscription',$script:L03Config.subscriptionId))
$remaining=@(foreach($target in $targets){
    Invoke-L03Az ($target.command+@('list','--resource-group',$rg,'--subscription',$script:L03Config.subscriptionId)) | Where-Object name -EQ $target.name
})
# An unsuccessful first deployment can leave no VM. Keep the receipt valid for that empty baseline.
[void](Write-L03Evidence 'stopped-retained-baseline' @{virtualMachines=$status;remainingRehearsalEgress=$remaining;retained=$true})
if($remaining.Count -gt 0 -or @($status|Where-Object {$_.name -eq $script:L03Config.vmName -and $_.powerState -ne 'VM deallocated'}).Count -gt 0){throw 'Compute or egress cleanup did not reach its expected state.'}
Write-Host 'Runner deallocated; rehearsal NAT/public IP removed. Baseline retained. Disk, private endpoint and applicable Defender charges continue.'
