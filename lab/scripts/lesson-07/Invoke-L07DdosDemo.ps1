<#
.SYNOPSIS
    Inspect, or briefly enable and restore, DDoS IP Protection on the lesson's public IP.
.DESCRIPTION
    Demonstrate closes HOL 7.4's implementation step with ARM configuration evidence.
    It enables the paid per-IP tier (about 0.2726 USD/hour), reads it back, then restores
    VirtualNetworkInherited in finally. It creates no DDoS plan and generates no attack.
    Configuration success does not demonstrate attack mitigation. Inspect is read-only.
.PARAMETER Mode
    Inspect or Demonstrate. Demonstrate requires the tagged lesson IP's inherited baseline.
.PARAMETER HoldSeconds
    Optional time to show the enabled setting on screen, bounded to five minutes.
.EXAMPLE
    ./Invoke-L07DdosDemo.ps1 -Mode Demonstrate
#>
[CmdletBinding()]
param([ValidateSet('Inspect','Demonstrate')][string]$Mode = 'Inspect',
      [ValidateRange(0,300)][int]$HoldSeconds = 0)
. (Join-Path $PSScriptRoot 'L07.Common.ps1')
[void](Assert-L07Context)
$cfg = $script:L07Config
function Read-LessonIp {
    $ip = Invoke-L07Az @('network','public-ip','show','--resource-group',$cfg.resourceGroup,'--name',$cfg.names.firewallPublicIp)
    if ($ip.tags.managedBy -ne $cfg.managedBy -or $ip.sku.name -ne 'Standard') {
        throw 'Expected the tagged Lesson 7 Standard public IP.'
    }
    return $ip
}
function Show-State($Ip, [string]$Phase) {
    $row = [ordered]@{ phase=$Phase; utc=[DateTime]::UtcNow.ToString('o'); resourceId=$Ip.id
        mode=(Get-L07Value $Ip 'ddosSettings.protectionMode')
        planId=(Get-L07Value $Ip 'ddosSettings.ddosProtectionPlan.id'); provisioningState=$Ip.provisioningState }
    [void](Write-L07Evidence "ddos-$($Phase.ToLowerInvariant())" $row)
    [pscustomobject]$row | Format-List | Out-Host
}
$before = Read-LessonIp
Show-State $before 'Before'
if ($Mode -eq 'Inspect') { return }
if ((Get-L07Value $before 'ddosSettings.protectionMode') -ne 'VirtualNetworkInherited' -or
    (Get-L07Value $before 'ddosSettings.ddosProtectionPlan.id')) {
    throw 'The IP is not at the recorded inherited baseline; leave an existing paid configuration intact.'
}
$hub = Invoke-L07Az @('network','vnet','show','--resource-group',$cfg.resourceGroup,'--name',$cfg.names.hubVnet)
if (Get-L07Value $hub 'enableDdosProtection') { throw 'A paid network plan already covers the hub; inspect before changing tiers.' }
$started = [DateTime]::UtcNow
try {
    # A short paid configuration cycle teaches enablement without funding a monthly network plan.
    [void](Invoke-L07Az @('network','public-ip','update','--ids',$before.id,'--ddos-protection-mode','Enabled'))
    $enabled = Read-LessonIp
    Show-State $enabled 'Enabled'
    if ((Get-L07Value $enabled 'ddosSettings.protectionMode') -ne 'Enabled' -or $enabled.provisioningState -ne 'Succeeded') {
        throw 'DDoS IP Protection enablement was not confirmed.'
    }
    Write-Host 'IP Protection configuration is enabled. No attack or mitigation result is claimed.'
    # Small intervals preserve responsiveness during an optional on-screen pause.
    for ($remaining=$HoldSeconds; $remaining -gt 0; $remaining -= 5) { Start-Sleep -Seconds ([Math]::Min(5,$remaining)) }
}
finally {
    [void](Invoke-L07Az @('network','public-ip','update','--ids',$before.id,'--ddos-protection-mode','VirtualNetworkInherited'))
    $restored = Read-LessonIp
    Show-State $restored 'Restored'
    if ((Get-L07Value $restored 'ddosSettings.protectionMode') -ne 'VirtualNetworkInherited' -or $restored.provisioningState -ne 'Succeeded') {
        throw 'DDoS paid tier may still be enabled. Restore the lesson public IP immediately.'
    }
    Write-Host ('Restored inherited baseline after {0:N1} minutes. Actual billing is separate.' -f ([DateTime]::UtcNow-$started).TotalMinutes)
}
