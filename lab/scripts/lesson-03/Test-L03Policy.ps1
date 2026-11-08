<#
.SYNOPSIS
Proves a denied and allowed request in the isolated Lesson 3 policy resource group.
.DESCRIPTION
The harmless identity has no roles, secrets, or federated credentials. Propagation failures
are reported honestly; a successful violating request is never reported as a denial.
#>
. (Join-Path $PSScriptRoot 'L03.Cloud.Common.ps1')
Assert-L03Context
[void](Assert-L03Group $script:L03Config.policyGroup)
$rg=$script:L03Config.policyGroup
$file=Join-Path $script:L03Root 'infra/lesson-03/identity-request.bicep'
$base=@('--resource-group',$rg,'--template-file',$file,'--subscription',$script:L03Config.subscriptionId)
$deny=Invoke-L03Az (@('deployment','group','create','--name','sc500-l03-denied')+$base+@('--parameters','compliant=false',('location='+$script:L03Config.location))) -AllowFailure
[void](Write-L03Evidence 'policy-denied-request' $deny)
# Always return the harmless fixture to a compliant baseline, even if policy propagation is incomplete.
$allow=Invoke-L03Az (@('deployment','group','create','--name','sc500-l03-allowed')+$base+@('--parameters','compliant=true',('location='+$script:L03Config.location)))
[void](Write-L03Evidence 'policy-allowed-request' $allow)
if($allow.properties.provisioningState -ne 'Succeeded'){throw 'The compliant request did not succeed.'}
if($deny.exitCode -eq 0 -or $deny.stderr -notmatch 'RequestDisallowedByPolicy'){
    throw 'The violating request was not proven denied by policy. The fixture was corrected; wait for propagation and repeat.'
}
Write-Host 'DENIED: missing course tag, RequestDisallowedByPolicy. ALLOWED: course=SC500, deployment Succeeded.'
# Evaluation reporting has its own clock; requesting a scan is not a claim of immediate compliance.
[void](Invoke-L03Az @('policy','state','trigger-scan','--resource-group',$rg,'--no-wait','--subscription',$script:L03Config.subscriptionId))
$states=Invoke-L03Az @('policy','state','list','--resource-group',$rg,'--subscription',$script:L03Config.subscriptionId)
[void](Write-L03Evidence 'policy-states-after-request' @{states=@($states);scanRequested=$true})
@($states)|Select-Object resourceId,policyAssignmentName,complianceState,timestamp|Format-Table -Wrap
