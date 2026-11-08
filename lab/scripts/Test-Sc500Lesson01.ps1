<#
.SYNOPSIS
Checks the deployed Lesson 1 infrastructure and captures actual state.
.DESCRIPTION
This is an administrator-side configuration check, not proof of Debra's effective access or PIM activation.
It fails on missing resources, failed provisioning, unexpected public exposure, or missing disk protection.
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'Sc500.Common.ps1')
$null = Assert-Sc500Context
$results = @()
foreach ($fixture in $script:Sc500Config.virtualMachines) {
    $null = Assert-Sc500OwnedGroup -Name $fixture.group
    $vm = Invoke-Sc500Az -Arguments @('vm','show','--subscription',$script:Sc500Config.subscriptionId,'--resource-group',$fixture.group,'--name',$fixture.name)
    $view = Invoke-Sc500Az -Arguments @('vm','get-instance-view','--subscription',$script:Sc500Config.subscriptionId,'--resource-group',$fixture.group,'--name',$fixture.name)
    $disk = Invoke-Sc500Az -Arguments @('disk','show','--subscription',$script:Sc500Config.subscriptionId,'--resource-group',$fixture.group,'--name',('osdisk-'+$fixture.name))
    $nic = Invoke-Sc500Az -Arguments @('network','nic','show','--ids',$vm.networkProfile.networkInterfaces[0].id,'--subscription',$script:Sc500Config.subscriptionId)
    $subnetId = $nic.ipConfigurations[0].subnet.id
    $subnet = Invoke-Sc500Az -Arguments @('network','vnet','subnet','show','--ids',$subnetId,'--subscription',$script:Sc500Config.subscriptionId)
    $checks = [ordered]@{
        Provisioned = $vm.provisioningState -eq 'Succeeded'
        NoPublicIp = @($nic.ipConfigurations | Where-Object { $_.PSObject.Properties['publicIPAddress'] -and $_.publicIPAddress }).Count -eq 0
        NoDefaultOutbound = $subnet.defaultOutboundAccess -eq $false
        NetworkSecurityGroupAttached = -not [string]::IsNullOrEmpty($subnet.networkSecurityGroup.id)
        TrustedLaunch = $vm.securityProfile.securityType -eq 'TrustedLaunch'
        SecureBoot = $vm.securityProfile.uefiSettings.secureBootEnabled -eq $true
        VirtualTpm = $vm.securityProfile.uefiSettings.vTpmEnabled -eq $true
        EncryptionAtHost = $vm.securityProfile.encryptionAtHost -eq $true
        PasswordAuthenticationDisabled = $vm.osProfile.linuxConfiguration.disablePasswordAuthentication -eq $true
        DiskExportDisabled = $disk.networkAccessPolicy -eq 'DenyAll' -and $disk.publicNetworkAccess -eq 'Disabled'
    }
    $results += [ordered]@{ name=$fixture.name;id=$vm.id;powerState=@($view.instanceView.statuses | Where-Object code -like 'PowerState/*')[0].code;checks=$checks;passed=($checks.Values -notcontains $false) }
}
$report = @{ checkedAt=(Get-Date -AsUTC -Format o);subscriptionId=$script:Sc500Config.subscriptionId;configuration=$results;passed=(@($results | Where-Object { -not $_.passed }).Count -eq 0);operatorAuthorizationVerified=$false;note='Effective access, PIM activation, completed access reviews, and recording rehearsal require separate evidence.' }
$path = Write-Sc500Evidence -Name 'baseline-state' -Value $report
$report | ConvertTo-Json -Depth 12
Write-Host "Evidence: $path"
if (-not $report.passed) { throw 'One or more deployed configuration checks failed.' }
