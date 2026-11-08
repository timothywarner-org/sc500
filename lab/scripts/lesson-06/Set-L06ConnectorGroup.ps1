<#
.SYNOPSIS Assigns the registered Lesson 6 host to its isolated connector group.
.DESCRIPTION
    Requires the operator's cached Graph sign-in. Matches the expected machine name and
    current public IP before assigning; refuses ambiguous or unrelated connectors.
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L06.Common.ps1')
[void](Assert-L06Context)
Import-Module Microsoft.Graph.Authentication
Connect-MgGraph -TenantId $script:L06Config.tenantId -Scopes 'Application.ReadWrite.All' -ContextScope CurrentUser -NoWelcome
$base='https://graph.microsoft.com/beta/onPremisesPublishingProfiles/applicationProxy'
$public=Invoke-L06Az @('network','public-ip','show','-g',$script:L06Config.connectorResourceGroup,'-n',$script:L06Names.connectorPip)
$connectors=@((Invoke-MgGraphRequest -Method GET -Uri "$base/connectors").value | Where-Object machineName -eq $script:L06Names.connectorComputer)
if($connectors.Count -ne 1 -or $connectors[0].externalIp -ne $public.ipAddress){throw 'No unique registered Lesson 6 connector matches the deployed host.'}
$groups=@((Invoke-MgGraphRequest -Method GET -Uri "$base/connectorGroups").value | Where-Object name -eq 'CTSO-L06-Connectors')
if($groups.Count -ne 1){throw 'Create the isolated pilot connector group first.'}
$connector=$connectors[0];$group=$groups[0]
$members=@((Invoke-MgGraphRequest -Method GET -Uri "$base/connectorGroups/$($group.id)/members").value)
if($connector.id -notin @($members|ForEach-Object id)){
    $body=@{'@odata.id'="$base/connectorGroups/$($group.id)"}|ConvertTo-Json
    Invoke-MgGraphRequest -Method POST -Uri "$base/connectors/$($connector.id)/memberOf/`$ref" -Body $body -ContentType 'application/json'|Out-Null
}
$readback=Invoke-MgGraphRequest -Method GET -Uri "$base/connectorGroups/$($group.id)/members"
[void](Write-L06Evidence 'connector-group-assignment' $readback)
if($connector.id -notin @($readback.value|ForEach-Object id)){throw 'Connector group readback did not match.'}
$readback.value | Select-Object machineName,status,version
