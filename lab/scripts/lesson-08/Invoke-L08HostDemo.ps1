<#
.SYNOPSIS
    Demo 8.1 for SC-500 Lesson 8: what Trusted Launch and encryption at host look like on a
    server, from Azure's side and from the guest's side.

.DESCRIPTION
    Read-only except -Mode Scan, which asks Azure Policy to evaluate the resource group now.
      Profile      Security type, Secure Boot, vTPM, and encryption at host for the ServiceHub app server (vm-servicehub-prod-001), and for
                   the legacy app server (vm-legacyapp-prod-001) when the bounded part exists.
      Guest        the ServiceHub app server (vm-servicehub-prod-001)'s own boot evidence from its serial log: Secure Boot state, the vTPM
                   devices, the kernel lockdown mode, and the temp disk.
      Attestation  The Guest Attestation extension (integrity monitoring) and its reported status.
      Disks        Each OS disk's server-side encryption type.
      Policy       Compliance with the "encryption at host enabled" assignment on the group.
      Scan         Start a policy evaluation for the group (takes several minutes to land).
      All          Profile, Guest, Attestation, Disks, and Policy.

.PARAMETER Mode
    One of the modes above.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Invoke-L08HostDemo.ps1 -Mode Profile
#>
[CmdletBinding()]
param([ValidateSet('Profile', 'Guest', 'Attestation', 'Disks', 'Policy', 'Scan', 'All')][string]$Mode = 'All')
. (Join-Path $PSScriptRoot 'L08.Common.ps1')
[void](Assert-L08Context)
$cfg = $script:L08Config
$rg = $cfg.resourceGroup
$n = $cfg.names

function Get-LabVms {
    # the datacenter server (vm-datacenter-prod-001) is left out: it plays an on-premises server, so its Azure-side settings aren't
    # part of this story.
    return @(Invoke-L08Az @('vm', 'list', '--resource-group', $rg, '--show-details') | Where-Object { $_.name -in @($n.appVm, $n.legacyVm) } | Sort-Object name)
}

if ($Mode -in 'Profile', 'All') {
    Write-Host '== Security profile'
    $rows = foreach ($vm in Get-LabVms) {
        $sp = Get-L08Value $vm 'securityProfile'
        [pscustomobject]@{
            VM               = $vm.name
            SecurityType     = $(if (Get-L08Value $sp 'securityType') { $sp.securityType } else { 'Standard' })
            SecureBoot       = [bool](Get-L08Value $sp 'uefiSettings.secureBootEnabled')
            vTPM             = [bool](Get-L08Value $sp 'uefiSettings.vTpmEnabled')
            EncryptionAtHost = [bool](Get-L08Value $sp 'encryptionAtHost')
            PublicIp         = $(if ("$($vm.publicIps)") { 'yes' } else { 'none' })
        }
    }
    [void](Write-L08Evidence 'host-profile' $rows)
    $rows | Format-Table -AutoSize | Out-String -Width 160 | Out-Host
}

if ($Mode -in 'Guest', 'All') {
    Write-Host "== $($n.appVm), from the guest (serial log, latest boot)"
    $lines = @(Get-L08BootLog -VmName $n.appVm -Prefix 'CONTOSO-EVIDENCE')
    $begins = @(for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -like 'CONTOSO-EVIDENCE begin*') { $i } })
    # @() around the if: an if statement that yields an empty array assigns $null otherwise.
    $block = @(if ($begins.Count) { $lines[$begins[-1]..($lines.Count - 1)] })
    [void](Write-L08Evidence 'host-guest' $block)
    if ($block.Count) { $block | ForEach-Object { $_ -replace '^CONTOSO-EVIDENCE ', '' } | Out-Host } else { Write-Host '(no evidence yet; the VM prints it about a minute after boot)' }
}

if ($Mode -in 'Attestation', 'All') {
    Write-Host '== Integrity monitoring (Guest Attestation extension)'
    $view = Invoke-L08Az @('vm', 'get-instance-view', '--resource-group', $rg, '--name', $n.appVm)
    $ext = @((Get-L08Value $view 'instanceView.extensions') | Where-Object { $_.name -eq 'GuestAttestation' })
    $status = if ($ext.Count) {
        [pscustomobject]@{
            Extension = 'GuestAttestation'
            Status    = (@($ext[0].statuses) | ForEach-Object { $_.displayStatus }) -join '; '
            Message   = ((@($ext[0].statuses) | ForEach-Object { Get-L08Value $_ 'message' }) -join ' ') -replace '\s+', ' '
        }
    } else { [pscustomobject]@{ Extension = 'GuestAttestation'; Status = 'not reported yet'; Message = '' } }
    [void](Write-L08Evidence 'host-attestation' $status)
    $status | Format-List | Out-String -Width 160 | Out-Host
}

if ($Mode -in 'Disks', 'All') {
    Write-Host '== OS disk encryption (server-side)'
    $rows = foreach ($vm in Get-LabVms) {
        $disk = Invoke-L08Az @('disk', 'show', '--ids', $vm.storageProfile.osDisk.managedDisk.id)
        [pscustomobject]@{ VM = $vm.name; Disk = $disk.name; EncryptionType = $disk.encryption.type; EncryptionAtHost = [bool](Get-L08Value $vm 'securityProfile.encryptionAtHost') }
    }
    [void](Write-L08Evidence 'host-disks' $rows)
    $rows | Format-Table -AutoSize | Out-String -Width 160 | Out-Host
}

if ($Mode -in 'Policy', 'All') {
    Write-Host "== Policy: $($n.encryptionAtHostAssignment)"
    $states = @(Invoke-L08Az @('policy', 'state', 'list', '--resource-group', $rg, '--filter', "policyAssignmentName eq '$($n.encryptionAtHostAssignment)'"))
    $rows = @(foreach ($s in $states) { [pscustomobject]@{ Resource = ($s.resourceId -split '/')[-1]; Compliance = $s.complianceState; Evaluated = $s.timestamp } })
    [void](Write-L08Evidence 'host-policy' ([pscustomobject]@{ rows = $rows }))
    if ($rows.Count) { $rows | Sort-Object Resource | Format-Table -AutoSize | Out-String -Width 160 | Out-Host } else { Write-Host '(no results yet; run -Mode Scan and allow several minutes)' }
}

if ($Mode -eq 'Scan') {
    [void](Invoke-L08Az -Raw @('policy', 'state', 'trigger-scan', '--resource-group', $rg, '--no-wait'))
    Write-Host 'Policy evaluation started for the group. Results usually land within 10 to 30 minutes.'
}
