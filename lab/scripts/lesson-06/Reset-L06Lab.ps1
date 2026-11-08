<#
.SYNOPSIS
    Returns the Lesson 6 lab to CTSO-L06-BASELINE after you finish.

.DESCRIPTION
      1. Deletes pep-servicehubrecords-blob-001, if demo 6.1 created it. Its DNS zone group goes with it, so the
         A record leaves the private DNS zone too.
      2. Turns the records account's public network access back on (the baseline fault), and
         re-seeds the synthetic record if it's missing.
      3. If the bounded Private Link service lab exists, deletes the partner's endpoint so the
         service has no connections.
      4. If the bounded hybrid DNS lab exists, empties the field-office DNS server's conditional
         forwarders.
    It never removes a bounded lab; Remove-L06Bounded.ps1 does that. Run Test-L06Lab.ps1 after.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Reset-L06Lab.ps1
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L06.Common.ps1')
[void](Assert-L06Context)
$cfg = $script:L06Config
$lab = Get-L06Outputs -Lab Private
$rg = $cfg.resourceGroup
$record = [ordered]@{}

$pe = Invoke-L06Az -AllowFailure @('network', 'private-endpoint', 'show', '--resource-group', $rg, '--name', $script:L06Names.recordsEndpoint)
if ($pe.ExitCode -eq 0) {
    Write-Host "Deleting $($script:L06Names.recordsEndpoint) and its DNS zone group."
    [void](Invoke-L06Az -Raw @('network', 'private-endpoint', 'delete', '--resource-group', $rg, '--name', $script:L06Names.recordsEndpoint))
}
$record.recordsEndpoint = 'absent'

Write-Host 'Turning public network access back on for the records account.'
[void](Invoke-L06Az @('storage', 'account', 'update', '--resource-group', $rg, '--name', $lab.recordsAccountName, '--public-network-access', 'Enabled', '--default-action', 'Allow'))
$record.publicNetworkAccess = 'Enabled'

# The firewall change can take up to a minute to reach the data plane, so retry the seed check.
$seed = Join-Path $script:L06Lab ('infra/lesson-06/seed/' + $cfg.seedBlob)
for ($i = 1; $i -le 6; $i++) {
    $exists = Invoke-L06Az -NoSubscription -AllowFailure @('storage', 'blob', 'exists', '--account-name', $lab.recordsAccountName, '--container-name', $cfg.recordsContainer, '--name', $cfg.seedBlob, '--auth-mode', 'login')
    if ($exists.ExitCode -eq 0) {
        if (-not ($exists.Stdout | ConvertFrom-Json).exists) {
            [void](Invoke-L06Az -NoSubscription -Raw @('storage', 'blob', 'upload', '--account-name', $lab.recordsAccountName, '--container-name', $cfg.recordsContainer,
                    '--name', $cfg.seedBlob, '--file', $seed, '--auth-mode', 'login', '--overwrite'))
            Write-Host "Re-seeded $($cfg.seedBlob)."
        }
        $record.seedBlob = 'present'
        break
    }
    if ($i -eq 6) { throw "Couldn't reach the records account after re-enabling public access: $($exists.Stderr.Trim())" }
    Start-Sleep -Seconds 15
}

if (Invoke-L06Az @('group', 'exists', '--name', $cfg.plsResourceGroup)) {
    $partner = Invoke-L06Az -AllowFailure @('network', 'private-endpoint', 'show', '--resource-group', $cfg.plsResourceGroup, '--name', $script:L06Names.partnerEndpoint)
    if ($partner.ExitCode -eq 0) {
        Write-Host "Deleting the partner endpoint $($script:L06Names.partnerEndpoint)."
        [void](Invoke-L06Az -Raw @('network', 'private-endpoint', 'delete', '--resource-group', $cfg.plsResourceGroup, '--name', $script:L06Names.partnerEndpoint))
    }
    $record.partnerEndpoint = 'absent'
}

if (Invoke-L06Az @('group', 'exists', '--name', $cfg.dnsResourceGroup)) {
    Write-Host 'Emptying the field-office conditional forwarders.'
    $dns = Get-L06Outputs -Lab Dns
    $out = Invoke-L06Guest -ResourceGroup $cfg.dnsResourceGroup -VmName $dns.fieldOfficeVm -Script "sed -i '/^[^#]/d' /etc/contoso-onprem-dns/forwarders; grep -vc '^#' /etc/contoso-onprem-dns/forwarders || true"
    $record.fieldOfficeForwarders = "$out non-comment lines"
}
# Deleting the DNS lab's resolver also removed snet-dns-inbound's delegation on September 26
# (Azure cleans it up with the inbound endpoint). Put it back, so the next DNS lab deployment
# finds the subnet the way the retained template defines it. Idempotent.
$sub = Invoke-L06Az @('network', 'vnet', 'subnet', 'show', '--resource-group', $rg, '--vnet-name', $script:L06Names.hubVnet, '--name', 'snet-dns-inbound')
if (-not @(@(Get-L06Value $sub 'delegations') | Where-Object { $_.serviceName -eq 'Microsoft.Network/dnsResolvers' }).Count) {
    Write-Host 'Restoring the snet-dns-inbound delegation to Microsoft.Network/dnsResolvers.'
    [void](Invoke-L06Az @('network', 'vnet', 'subnet', 'update', '--resource-group', $rg, '--vnet-name', $script:L06Names.hubVnet, '--name', 'snet-dns-inbound',
            '--delegations', 'Microsoft.Network/dnsResolvers'))
}
$record.dnsInboundDelegation = 'Microsoft.Network/dnsResolvers'
[void](Write-L06Evidence 'reset' $record)
$record.GetEnumerator() | ForEach-Object { '{0,-22} {1}' -f $_.Key, $_.Value }
Write-Host 'Reset complete. Run Test-L06Lab.ps1 to confirm the baseline.'
