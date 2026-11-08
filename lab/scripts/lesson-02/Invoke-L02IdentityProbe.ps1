<#
.SYNOPSIS
Captures the live managed-identity read/denied-write results and stops compute.
.DESCRIPTION
By default a fresh start is requested. Use -AlreadyRunning only immediately after
deployment. The identities act from inside ACI; the administrator only retrieves
the resulting logs. Tokens are never printed, saved, or passed to the controller.
.EXAMPLE
.\scripts\lesson-02\Invoke-L02IdentityProbe.ps1
.EXAMPLE
.\scripts\lesson-02\Invoke-L02IdentityProbe.ps1 -Identity UserAssigned
#>
[CmdletBinding()]
param([switch]$AlreadyRunning, [ValidateSet('Both','UserAssigned','SystemAssigned')][string]$Identity = 'Both', [ValidateRange(60,1200)][int]$TimeoutSeconds = 660)
. (Join-Path $PSScriptRoot 'L02.Cloud.Common.ps1')
Assert-L02Context
[void](Assert-L02OwnedGroup -Name $script:L02Config.targetGroup)
$initial = Get-L02Container
if (-not $initial) { throw 'Deploy the Lesson 2 container first.' }
try {
    if (-not $AlreadyRunning) {
        [void](Invoke-L02Az @('container','start','--name',$script:L02Config.containerName,'--resource-group',$script:L02Config.identityGroup,'--subscription',$script:L02Config.subscriptionId))
    }
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $log = Invoke-L02Az @('container','logs','--name',$script:L02Config.containerName,'--resource-group',$script:L02Config.identityGroup,'--container-name','identity-probe','--subscription',$script:L02Config.subscriptionId) -Raw
        if ($Identity -eq 'UserAssigned' -and $log -match 'SC500_L02_RESULT .*"identity": "user-assigned"') { break }
        if ($log -match 'SC500_L02_COMPLETE|SC500_L02_FAILED') { break }
        $current = Invoke-L02Az @('container','show','--name',$script:L02Config.containerName,'--resource-group',$script:L02Config.identityGroup,'--subscription',$script:L02Config.subscriptionId)
        if ($current.instanceView.state -in @('Failed','Succeeded','Stopped')) { break }
        Start-Sleep -Seconds 10
    } while ([DateTime]::UtcNow -lt $deadline)
    Write-L02Evidence -Name 'probe-log' -Value @{ capturedAt=[DateTime]::UtcNow.ToString('o'); log=$log }
    $results = @($log -split '\r?\n' | Where-Object { $_.StartsWith('SC500_L02_RESULT ') } | ForEach-Object { $_.Substring(17) | ConvertFrom-Json })
    $security = @($log -split '\r?\n' | Where-Object { $_.StartsWith('SC500_L02_SECURITY ') } | ForEach-Object { $_.Substring(19) | ConvertFrom-Json })
    if ($security.Count -ne 1 -or $security[0].uid -ne 10001 -or $security[0].gid -ne 10001 -or $security[0].noNewPrivileges -ne '1' -or [Convert]::ToInt64($security[0].effectiveCapabilities,16) -ne 0) { throw 'Nonroot probe security was not demonstrated.' }
    $live = Invoke-L02Az @('container','show','--name',$script:L02Config.containerName,'--resource-group',$script:L02Config.identityGroup,'--subscription',$script:L02Config.subscriptionId)
    $uami = Invoke-L02Az @('identity','show','--name',$script:L02Config.identityName,'--resource-group',$script:L02Config.identityGroup,'--subscription',$script:L02Config.subscriptionId)
    foreach ($result in $results) {
        $expected = if ($result.identity -eq 'system-assigned') { $live.identity.principalId } else { $uami.principalId }
        if ($result.principalId -ne $expected) { throw 'Token principal did not match the corresponding deployed identity.' }
    }
    $bothComplete = $log -match 'SC500_L02_COMPLETE' -and $results.Count -eq 2 -and @($results | Where-Object { -not $_.passed }).Count -eq 0
    $selectedKind = if ($Identity -eq 'SystemAssigned') { 'system-assigned' } else { 'user-assigned' }
    $complete = if ($Identity -eq 'Both') { $bothComplete } else { @($results | Where-Object { $_.identity -eq $selectedKind -and $_.passed }).Count -eq 1 }
    # Preserve a successful identity's evidence even if the other identity's endpoint fails.
    $proof = @{ capturedAt=[DateTime]::UtcNow.ToString('o'); requestedIdentity=$Identity; requestedProofComplete=$complete; bothIdentitiesComplete=$bothComplete; containerId=$live.id; identities=$results; runtimeSecurity=$security[0]; actualContainerConfiguration=$live; targetGroup=$script:L02Config.targetGroup; failures=@($log -split '\r?\n' | Where-Object { $_.StartsWith('SC500_L02_FAILED ') }) }
    $proofName = if ($complete -and $Identity -eq 'UserAssigned') { 'verified-user-identity-probe' } elseif ($complete -and $Identity -eq 'SystemAssigned') { 'verified-system-identity-probe' } elseif ($complete) { 'verified-identity-probe' } else { 'partial-identity-probe' }
    Write-L02Evidence -Name $proofName -Value $proof
    $results | Select-Object identity,readStatus,writeStatus,writeErrorCode,passed | Format-Table -AutoSize
    if (-not $complete) { throw "The live probe did not demonstrate the requested $Identity Reader boundary. Successful results and separate failures are preserved in private evidence." }
} finally {
    # A failed rehearsal must not leave hourly compute billing running unattended.
    & (Join-Path $PSScriptRoot 'Stop-L02Workload.ps1')
}
