<#
.SYNOPSIS Previews or deploys the isolated Windows 11 Private Access client.
.DESCRIPTION
    East US avoids the busy course region. The VNet has no peering or VPN, so a direct
    route cannot masquerade as Private Access. Passwords stay in DPAPI and the in-memory
    ARM request. Keep the VM deallocated between practice sessions; disk and public IP still bill.
#>
[CmdletBinding()]
param([switch]$Deploy)
. (Join-Path $PSScriptRoot 'L06.Common.ps1')
[void](Assert-L06Context)
# Region and size come from config.json. October 30, 2026: Standard_B2als_v2 hit a capacity restriction in
# eastus and eastus2, and every B size is restricted for this subscription in eastus, so the client moved to
# Standard_B2s in eastus2. Its VNet still has no peering or VPN, so the region changes nothing the demo proves.
$rg=$script:L06Config.clientResourceGroup;$location=$script:L06Config.clientLocation;$vmSize=$script:L06Config.windowsVmSize
$existing=Invoke-L06Az @('group','exists','-n',$rg)
if($existing){$group=Invoke-L06Az @('group','show','-n',$rg);if($group.tags.managedBy -ne $script:L06Config.managedBy){throw 'Unowned client resource group.'}}
$usage=Invoke-L06Az @('vm','list-usage','--location',$location)
if(-not $existing){foreach($name in 'cores',$script:L06Config.windowsVmFamily){$q=@($usage|Where-Object {$_.name.value -eq $name})[0];if($q.currentValue+2 -gt $q.limit){throw "Insufficient $name quota in $location."}}}
$imageFile=Join-Path $script:L06State "client-image-$location.json"
if(-not(Test-Path $imageFile)){Invoke-L06Az @('vm','image','show','--urn','MicrosoftWindowsDesktop:windows-11:win11-24h2-pro:latest','--location',$location)|ConvertTo-Json -Depth 12|Set-Content $imageFile}
$image=Get-Content $imageFile -Raw|ConvertFrom-Json
$me=Invoke-L06Az -NoSubscription @('ad','signed-in-user','show')
if($me.userPrincipalName -ne '<your-admin-upn>'){throw 'Use the course operator account.'}
$folder=Join-Path $env:LOCALAPPDATA 'SC500/Lesson06';[void][IO.Directory]::CreateDirectory($folder)
$credPath=Join-Path $folder 'client-admin.credential.xml'
if(Test-Path $credPath){$credential=Import-Clixml $credPath}else{
    $password='Ct9!'+[Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(24))
    $credential=[PSCredential]::new('contosoadmin',($password|ConvertTo-SecureString -AsPlainText -Force));$password=$null
    $credential|Export-Clixml $credPath
}
$template=Join-Path $script:L06Lab 'infra/lesson-06/client.bicep'
$compiled=Invoke-L06Az -Raw -NoSubscription @('bicep','build','--file',$template,'--stdout','--output','json')|ConvertFrom-Json -Depth 100
$parameters=@{location=@{value=$location};vmSize=@{value=$vmSize};names=@{value=$script:L06Config.names};imageVersion=@{value=$image.name};operatorPublicIp=@{value=(Invoke-RestMethod 'https://api.ipify.org?format=json').ip};operatorObjectId=@{value=$me.id};adminPassword=@{value=$credential.GetNetworkCredential().Password}}
$body=@{properties=@{mode='Incremental';template=$compiled;parameters=$parameters}}|ConvertTo-Json -Depth 100
$arm=Invoke-L06Az @('account','get-access-token','--resource','https://management.azure.com/')
$headers=@{Authorization="Bearer $($arm.accessToken)"}
try {
    if(-not $existing){Invoke-L06Az @('group','create','-n',$rg,'-l',$location,'--tags','managedBy=sc500-l06-iac','lesson=6','lifecycle=retain-deallocated')|Out-Null}
    $uri="https://management.azure.com/subscriptions/$($script:L06Config.subscriptionId)/resourceGroups/$rg/providers/Microsoft.Resources/deployments/sc500-lesson06-client"
    # Validation and what-if carry the secure parameter only in HTTPS request memory.
    $null=Invoke-RestMethod -Method Post -Uri ($uri+'/validate?api-version=2022-09-01') -Headers $headers -Body $body -ContentType 'application/json'
    $preview=Invoke-WebRequest -Method Post -Uri ($uri+'/whatIf?api-version=2022-09-01') -Headers $headers -Body $body -ContentType 'application/json'
    if($preview.StatusCode -eq 202){
        $poll=[string]$preview.Headers.Location[0]
        do {Start-Sleep -Seconds 5;$result=Invoke-RestMethod -Uri $poll -Headers $headers}while($result.status -in 'Running','InProgress')
    }else{$result=$preview.Content|ConvertFrom-Json -Depth 100}
    if($result.status -ne 'Succeeded'){throw 'Client what-if did not succeed.'}
    $changes=Get-L06Value $result 'changes'
    if($null -eq $changes){$changes=Get-L06Value $result 'properties.changes'}
    if($null -eq $changes){throw "Client what-if omitted its change list. Response keys: $($result.PSObject.Properties.Name -join ', ')"}
    if(@($changes|Where-Object changeType -eq 'Delete').Count){throw 'Client what-if contains deletion.'}
    # Persist only resource IDs and change types, not the parameter-bearing request.
    [void](Write-L06Evidence 'client-what-if' @($changes|Select-Object resourceId,changeType))
    if(-not $Deploy){Write-Host 'Client preview passed. No VM deployed.';return}
    $null=Invoke-RestMethod -Method Put -Uri ($uri+'?api-version=2022-09-01') -Headers $headers -Body $body -ContentType 'application/json'
    $deadline=[DateTime]::UtcNow.AddMinutes(20)
    do {Start-Sleep -Seconds 15;$result=Invoke-RestMethod -Uri ($uri+'?api-version=2022-09-01') -Headers $headers}while($result.properties.provisioningState -in 'Accepted','Running' -and [DateTime]::UtcNow -lt $deadline)
    [void](Write-L06Evidence 'client-deployment' @{State=$result.properties.provisioningState;Outputs=$result.properties.outputs})
    if($result.properties.provisioningState -ne 'Succeeded'){throw 'Client deployment did not succeed; inspect ARM operations.'}
    $result.properties.outputs.lab.value
}finally{$body=$null;$parameters=$null;$credential=$null;$headers=$null;$arm=$null}
