<#
.SYNOPSIS Starts or deallocates the three retained Private Access demo VMs.
.DESCRIPTION
    Restores the app's maintenance egress before starting it, narrows client RDP to the
    operator's current public address, and writes a credential-free RDP file. Stopping
    deallocates every named guest before removing NAT. Disks and Windows public IPs remain.
.PARAMETER Stop Deallocate the app, connector and client, then remove maintenance NAT.
#>
[CmdletBinding()]
param([switch]$Stop)
. (Join-Path $PSScriptRoot 'L06.Common.ps1')
[void](Assert-L06Context)
$targets=@(
    @{Group=$script:L06Config.resourceGroup;Vm=$script:L06Names.appVm},
    @{Group=$script:L06Config.connectorResourceGroup;Vm=$script:L06Names.connectorVm},
    @{Group=$script:L06Config.clientResourceGroup;Vm=$script:L06Names.clientVm}
)
# Validate every owner before the first write so a partial mismatch cannot start unrelated VMs.
foreach($target in $targets){
    $group=Invoke-L06Az @('group','show','-n',$target.Group)
    if($group.tags.managedBy -ne $script:L06Config.managedBy){throw "Unowned group: $($target.Group)"}
}
if(-not $Stop){& (Join-Path $PSScriptRoot 'Set-L06MaintenanceEgress.ps1') -Lab Private -Enable}
foreach($target in $targets){
    $verb=if($Stop){'deallocate'}else{'start'}
    Write-Host "$verb $($target.Vm)"
    Invoke-L06Az @('vm',$verb,'-g',$target.Group,'-n',$target.Vm) | Out-Null
}
if($Stop){
    & (Join-Path $PSScriptRoot 'Set-L06MaintenanceEgress.ps1') -Lab Private
}else{
    $ip=(Invoke-RestMethod 'https://api.ipify.org?format=json').ip
    Invoke-L06Az @('network','nsg','rule','update','-g',$script:L06Config.clientResourceGroup,'--nsg-name',$script:L06Names.clientNsg,'-n','RDP-Operator-Only','--source-address-prefixes',"$ip/32") | Out-Null
    $public=Invoke-L06Az @('network','public-ip','show','-g',$script:L06Config.clientResourceGroup,'-n',$script:L06Names.clientPip)
    # The RDP file goes to the git-ignored lab state folder on L:, never %LOCALAPPDATA%: on 2026-10-31 a run from a
    # packaged (MSIX) host wrote it to a virtualized AppData copy, so Explorer showed the folder as unavailable.
    $folder=$script:L06State;[void][IO.Directory]::CreateDirectory($folder)
    $rdp=Join-Path $folder 'Lesson06-client.rdp'
    # Registered Windows PCs can use AzureAD\UPN. The user's password stays in the Windows prompt.
    @("full address:s:$($public.ipAddress)",'username:s:AzureAD\<your-admin-upn>','prompt for credentials:i:1','authentication level:i:2','redirectclipboard:i:1','screen mode id:i:2') | Set-Content -LiteralPath $rdp -Encoding unicode
    Write-Host "RDP file: $rdp. Sign in as the pilot user, then open Global Secure Access. A user tunnel has not been tested by this script."
}
$states=foreach($target in $targets){Invoke-L06Az @('vm','show','-g',$target.Group,'-n',$target.Vm,'--show-details','--query','{name:name,power:powerState}')}
[void](Write-L06Evidence 'private-access-power' $states)
$states | Format-Table
