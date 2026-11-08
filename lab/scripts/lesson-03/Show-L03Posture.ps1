<#
.SYNOPSIS
Reads Defender coverage, standards and Lesson 3 findings without changing paid plans.
.DESCRIPTION
Only redacted metadata is written. An empty result is preserved as an empty result.
#>
. (Join-Path $PSScriptRoot 'L03.Cloud.Common.ps1')
Assert-L03Context
$scope='/subscriptions/'+$script:L03Config.subscriptionId
function Get-L03Paged {
    param([string]$Path)
    $items=@();$next=$Path
    while($next){
        $page=Invoke-L03Arm $next;$items+=@($page.value)
        $next=if($page.PSObject.Properties['nextLink'] -and $page.nextLink){([Uri]$page.nextLink).PathAndQuery}else{$null}
    }
    return $items
}
$plans=Get-L03Paged ($scope+'/providers/Microsoft.Security/pricings?api-version=2024-01-01')
$coverage=@($plans|Where-Object name -In @('CloudPosture','VirtualMachines','KeyVaults')|ForEach-Object{
    [pscustomobject]@{plan=$_.name;tier=$_.properties.pricingTier;subPlan=if($_.properties.PSObject.Properties['subPlan']){$_.properties.subPlan}else{$null};extensions=if($_.properties.PSObject.Properties['extensions']){$_.properties.extensions}else{@()}}
})
[void](Write-L03Evidence 'defender-coverage' $coverage)
$coverage|ConvertTo-Json -Depth 15
$results=[ordered]@{checkedAt=[DateTime]::UtcNow.ToString('o');lesson='03';planChangesMade=$false}
foreach($surface in @(
    @{name='standards';path='/providers/Microsoft.Security/regulatoryComplianceStandards?api-version=2019-01-01-preview'}
)){
    try{
        $items=@(Get-L03Paged ($scope+$surface.path))
        if($surface.name -ne 'standards'){$items=@($items|Where-Object {($_|ConvertTo-Json -Depth 30 -Compress) -match 'rg-sc500-l03-'})}
        # Full findings can include sensitive investigation details. Retain only identifiers and status.
        $safe=@($items|ForEach-Object{[pscustomobject]@{id=$_.id;name=$_.name;type=$_.type;status=if($_.properties.PSObject.Properties['status']){$_.properties.status}else{$null};state=if($_.properties.PSObject.Properties['state']){$_.properties.state}else{$null}}})
        $results[$surface.name]=@{observedCount=$safe.Count;items=$safe;readSucceeded=$true}
        Write-Host ($surface.name+': '+$safe.Count+' observed record(s).')
    }catch{
        $results[$surface.name]=@{readSucceeded=$false;error=$_.Exception.Message}
        Write-Warning ($surface.name+': read did not complete. This is not an empty findings result.')
    }
}
[void](Write-L03Evidence 'posture-results' $results)
# The individual recommendation model supersedes the retired grouped findings API.
& (Join-Path $PSScriptRoot 'Get-L03DetectionEvidence.ps1')
Write-Host 'Plan state and available evidence inspected. No subscription plan, standard, recommendation, or scanner setting was changed.'
