<#
.SYNOPSIS
Reads real Lesson 3 Defender findings and alerts without creating sample alerts.
.DESCRIPTION
Keeps resource and event identifiers, titles and statuses. Omits credentials, raw
investigation payloads and unrelated findings. Zero means zero observed, never PASS.
#>
. (Join-Path $PSScriptRoot 'L03.Cloud.Common.ps1')
Assert-L03Context
function Get-L03DefenderPages([string]$Path){
    $next=$Path
    while($next){
        $page=Invoke-L03Arm -Path $next -AsHashtable
        $page.value
        $next=if($page.ContainsKey('nextLink') -and $page['nextLink']){([uri]$page['nextLink']).PathAndQuery}else{$null}
    }
}
$scope='/subscriptions/'+$script:L03Config.subscriptionId+'/providers/Microsoft.Security/'
# Resource Graph is Microsoft's documented current recommendation model and includes category metadata.
$query="securityresources | where type =~ 'microsoft.security/assessments' | where id contains '/resourcegroups/rg-sc500-l03-' | where properties.metadata.recommendationCategory == 'ExposedSecrets' | project id, name, displayName=tostring(properties.displayName), recommendationCategory=tostring(properties.metadata.recommendationCategory), status=properties.status, resourceId=tostring(properties.resourceDetails.Id), secretType=tostring(properties.additionalData.SecretTypeDisplayName), scanner=tostring(properties.additionalData.SecretScannerName), portalUrl=tostring(properties.links.azurePortal)"
$graph=Invoke-L03Az @('graph','query','--subscriptions',$script:L03Config.subscriptionId,'--graph-query',$query,'--first','1000')
if($graph.total_records -gt $graph.count){throw 'Secret recommendation query was truncated; do not report an incomplete count.'}
$alerts=@(Get-L03DefenderPages ($scope+'alerts?api-version=2022-01-01'))
function Select-L03SafeEvidence($Items){
    @($Items|Where-Object {($_|ConvertTo-Json -Depth 50 -Compress) -match 'rg-sc500-l03-'}|ForEach-Object{
        # CLI models flatten some properties; retain an allowlist, never the whole provider payload.
        $data=$_|ConvertTo-Json -Depth 50|ConvertFrom-Json -AsHashtable
        $safe=[ordered]@{id=$data.id;name=$data.name}
        if($data.ContainsKey('properties')){$data=$data.properties}
        if($data.ContainsKey('metadata')){$safe['recommendationCategory']=$data.metadata['recommendationCategory']}
        foreach($key in @('id','name','displayName','alertDisplayName','alertType','status','severity','timeGenerated','timeGeneratedUtc','startTimeUtc','endTimeUtc','resourceDetails','compromisedEntity','resourceIdentifiers')){
            if($data.ContainsKey($key)){$safe[$key]=$data[$key]}
        }
        [pscustomobject]$safe
    })
}
$secrets=@($graph.data)
$scopedAlerts=@(Select-L03SafeEvidence $alerts)
$record=@{checkedAt=[DateTime]::UtcNow.ToString('o');secretAssessments=$secrets;alerts=$scopedAlerts;secretFindingCount=$secrets.Count;alertCount=$scopedAlerts.Count;sampleAlertsCreated=$false;model='Individual recommendations; grouped subassessments deprecated 2026-07-31'}
[void](Write-L03Evidence 'detection-evidence' $record)
$record|ConvertTo-Json -Depth 15
