<#
.SYNOPSIS
Reads Lesson 3 assessment details and the security-standard mapping without modifying findings.
.DESCRIPTION
Keeps actual finding identifiers and source relationships in private evidence. Scope filtering
prevents unrelated subscription findings from appearing in the course's Contoso storyline.
#>
. (Join-Path $PSScriptRoot 'L03.Cloud.Common.ps1')
Assert-L03Context
$scope='/subscriptions/'+$script:L03Config.subscriptionId
function Get-Pages([string]$Path){
    $items=@();$next=$Path
    while($next){$page=Invoke-L03Arm $next;$items+=@($page.value);$next=if($page.PSObject.Properties['nextLink'] -and $page.nextLink){([uri]$page.nextLink).PathAndQuery}else{$null}}
    return $items
}
$query="securityresources | where type =~ 'microsoft.security/assessments' | where id contains '/resourcegroups/rg-sc500-l03-' | project id, name, title=tostring(properties.displayName), status=tostring(properties.status.code), resource=tostring(properties.resourceDetails.Id)"
# Use the current model rather than reporting an empty legacy collection as no findings.
$graph=Invoke-L03Az @('graph','query','--graph-query',$query,'--first','1000')
if($graph.total_records -gt $graph.count){throw 'Assessment query was truncated.'}
$assessments=@($graph.data)
[void](Write-L03Evidence 'completion-assessments' @{checkedAt=[DateTime]::UtcNow.ToString('o');items=$assessments})
$assessments|Select-Object name,title,status,resource|Format-Table -Wrap
$standard=$scope+'/providers/Microsoft.Security/regulatoryComplianceStandards/Microsoft-cloud-security-benchmark'
$controls=@(Get-Pages ($standard+'/regulatoryComplianceControls?api-version=2019-01-01-preview'))
[void](Write-L03Evidence 'completion-standard-controls' @{standard=$standard;controls=$controls})
$controls|Where-Object {$_.name -match 'BR|IM|DP|PV'}|Select-Object name,properties|ConvertTo-Json -Depth 10
