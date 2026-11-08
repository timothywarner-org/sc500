<#
.SYNOPSIS
    Read Defender health and service connectivity on both running Lesson 7 guests.
.DESCRIPTION
    Preparation only. Requires the bounded firewall and settled extensions before Run Command,
    so a configuration retry cannot silently become an demo stall. Changes no protection
    settings. Saves dated private evidence, including elapsed seconds and the guest result.
.EXAMPLE
    ./scripts/lesson-07/Test-L07GuestHealth.ps1
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L07.Common.ps1')
[void](Assert-L07Context)
$cfg=$script:L07Config
$firewall=Get-L07Firewall
if (-not $firewall -or $firewall.properties.provisioningState -ne 'Succeeded') { throw 'Wait for a successful firewall deployment first; the guests require its approved egress.' }
$guest=@'
set -eu
test "$(mdatp health --field healthy)" = "true"
mdatp health --field health_issues
mdatp health --field passive_mode_enabled
mdatp connectivity test
printf '\nSC500_MDE_HEALTHY_AND_CONNECTED\n'
'@
foreach($name in @($cfg.names.prodVm,$cfg.names.nonprodVm)) {
    $vm=Invoke-L07Az @('vm','show','-g',$cfg.resourceGroup,'-n',$name,'--show-details')
    if($vm.tags.managedBy -ne $cfg.managedBy -or $vm.powerState -ne 'VM running') { throw "$name is not the expected running lesson guest." }
    $extensions=@(Invoke-L07Az @('vm','extension','list','-g',$cfg.resourceGroup,'--vm-name',$name))
    if(@($extensions | Where-Object provisioningState -ne 'Succeeded').Count) { throw "$name has an unfinished extension. Diagnose it before starting another guest command." }
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $result=Invoke-L07Az @('vm','run-command','invoke','-g',$cfg.resourceGroup,'-n',$name,'--command-id','RunShellScript','--scripts',$guest)
    $message=($result.value | ForEach-Object message) -join "`n"
    $pass=$message.Contains('SC500_MDE_HEALTHY_AND_CONNECTED') -and $message -notmatch '\[ERROR\]|\[FAILED\]'
    $receipt=[ordered]@{vm=$name;seconds=[math]::Round($watch.Elapsed.TotalSeconds,1);passed=$pass;result=$result}
    [void](Write-L07Evidence "$name-guest-health" $receipt)
    Write-Host "$name : healthy and connected = $pass; elapsed $($receipt.seconds) seconds."
    if(-not $pass) { throw "Defender health/connectivity failed on $name. Read its private evidence receipt." }
}
