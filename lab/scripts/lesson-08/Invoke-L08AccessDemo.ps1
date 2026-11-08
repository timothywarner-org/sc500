<#
.SYNOPSIS
    Demo 8.2 for SC-500 Lesson 8: admin access without public IPs (Azure Bastion), and for the
    server that still has one, just-in-time access through Defender for Cloud.

.DESCRIPTION
    Nothing here signs in to a VM. Probe opens TCP 22 and reads the SSH banner, which proves the
    port is reachable without authenticating. The Bastion connection itself is yours, in the portal.
      Bastion    Bastion's SKU and state, the ServiceHub app server (vm-servicehub-prod-001)'s lack of a public IP, and the NSG rule that
                 lets Bastion reach SSH from inside the VNet.
      Probe      TCP 22 on the legacy app server (vm-legacyapp-prod-001)'s public IP, from this workstation.
      Rules      the legacy app server (vm-legacyapp-prod-001)'s NSG rules, in priority order.
      EnableJit  Put port 22 on the legacy app server (vm-legacyapp-prod-001) under a JIT policy (max 3 hours, any requested
                 source). Defender for Cloud writes its deny rule into the NSG, at priority 4096 in
                 the rehearsal, so it sits BELOW the standing allow rule and changes nothing yet.
      RemoveStanding  Delete the standing allow-ssh-admin-standing rule, the step that makes JIT
                 the only way in.
      Request    Request 1 hour of access for this workstation's current public IP.
      Policy     The JIT policy and its latest request.
      Sequence   Probe, EnableJit, Rules, Probe, RemoveStanding, Probe, Request, Rules, Probe, with
                 pauses for the NSG to update. This is the rehearsal path. A request can't be
                 withdrawn, so after a Sequence, recreate the legacy VM (Remove-L08Bounded.ps1,
                 then Deploy-L08Bounded.ps1 -Deploy) before the next run.

.PARAMETER Mode
    One of the modes above.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Invoke-L08AccessDemo.ps1 -Mode Probe
#>
[CmdletBinding()]
param([ValidateSet('Bastion', 'Probe', 'Rules', 'EnableJit', 'RemoveStanding', 'Request', 'Policy', 'Sequence')][string]$Mode = 'Bastion')
. (Join-Path $PSScriptRoot 'L08.Common.ps1')
[void](Assert-L08Context)
$cfg = $script:L08Config
$rg = $cfg.resourceGroup
$n = $cfg.names
$jit = (Get-L08JitPath) + '?api-version=2020-01-01'

function Get-LegacyIp {
    $pip = Invoke-L08Az -AllowFailure @('network', 'public-ip', 'show', '--resource-group', $rg, '--name', $n.legacyPublicIp)
    if ($pip.ExitCode -ne 0) { throw "$($n.legacyVm) isn't deployed. Run Deploy-L08Bounded.ps1 -Deploy first." }
    return ($pip.Stdout | ConvertFrom-Json).ipAddress
}

function Show-Probe {
    $ip = Get-LegacyIp
    $r = Test-L08Tcp -Address $ip -Port $cfg.jit.port
    $row = [pscustomobject]@{ Target = "$($n.legacyVm):$($cfg.jit.port)"; Result = $r.Result; Detail = $r.Detail; AtUtc = [DateTime]::UtcNow.ToString('HH:mm:ss') }
    [void](Write-L08Evidence 'access-probe' $row)
    $row | Format-Table -AutoSize | Out-String -Width 160 | Out-Host
}

function Show-Rules {
    $nsg = Invoke-L08Az @('network', 'nsg', 'show', '--resource-group', $rg, '--name', $n.legacyNsg)
    $rows = @($nsg.securityRules | Where-Object direction -eq 'Inbound' | Sort-Object priority | ForEach-Object {
            [pscustomobject]@{ Priority = $_.priority; Name = $_.name; Access = $_.access; Source = $(if ($_.sourceAddressPrefix) { $_.sourceAddressPrefix } else { @($_.sourceAddressPrefixes) -join ',' }); Port = $_.destinationPortRange }
        })
    [void](Write-L08Evidence 'access-rules' ([pscustomobject]@{ rules = $rows }))
    # The operator's IP stays off screen; slides say "Your IP".
    $me = Get-L08OperatorIp
    $rows | ForEach-Object { $_.Source = $_.Source -replace [regex]::Escape($me), 'Your IP' ; $_ } | Format-Table -AutoSize | Out-String -Width 160 | Out-Host
}

function Enable-Jit {
    $body = @{
        kind       = 'Basic'
        location   = $cfg.location
        properties = @{
            virtualMachines = @(@{
                    id    = Get-L08VmId $n.legacyVm
                    ports = @(@{ number = $cfg.jit.port; protocol = '*'; allowedSourceAddressPrefix = '*'; maxRequestAccessDuration = $cfg.jit.maxRequestAccessDuration })
                })
        }
    }
    $r = Invoke-L08Arm -Method put -Path $jit -Body $body
    [void](Write-L08Evidence 'access-jit-enabled' $r)
    Write-Host "JIT policy is $($r.properties.provisioningState) for $($n.legacyVm) port $($cfg.jit.port) (max $($cfg.jit.maxRequestAccessDuration))."
}

function Remove-Standing {
    # JIT adds rules; it never removes yours. A standing allow above JIT's deny keeps the port open.
    $r = Invoke-L08Az -AllowFailure @('network', 'nsg', 'rule', 'show', '--resource-group', $rg, '--nsg-name', $n.legacyNsg, '--name', 'allow-ssh-admin-standing')
    if ($r.ExitCode -ne 0) { Write-Host 'The standing rule is already gone.'; return }
    [void](Invoke-L08Az -Raw @('network', 'nsg', 'rule', 'delete', '--resource-group', $rg, '--nsg-name', $n.legacyNsg, '--name', 'allow-ssh-admin-standing'))
    [void](Write-L08Evidence 'access-standing-removed' ([pscustomobject]@{ rule = 'allow-ssh-admin-standing'; removedUtc = [DateTime]::UtcNow.ToString('o') }))
    Write-Host 'Deleted allow-ssh-admin-standing. JIT is now the only way in.'
}

function Request-Jit {
    $me = Get-L08OperatorIp
    $body = @{
        virtualMachines = @(@{ id = Get-L08VmId $n.legacyVm; ports = @(@{ number = $cfg.jit.port; duration = $cfg.jit.requestDuration; allowedSourceAddressPrefix = $me }) })
        justification   = 'SC-500 Lesson 8 demo: patch window'
    }
    $r = Invoke-L08Arm -Method post -Path ((Get-L08JitPath) + '/initiate?api-version=2020-01-01') -Body $body
    $port = @(@($r.virtualMachines)[0].ports)[0]
    $row = [pscustomobject]@{ Port = $port.number; Status = $port.status; StatusReason = Get-L08Value $port 'statusReason'; EndTimeUtc = $port.endTimeUtc }
    [void](Write-L08Evidence 'access-jit-request' $row)
    $row | Format-Table -AutoSize | Out-String -Width 160 | Out-Host
}

switch ($Mode) {
    'Bastion' {
        $b = Invoke-L08Az @('resource', 'show', '--resource-group', $rg, '--resource-type', 'Microsoft.Network/bastionHosts', '--name', $n.bastion)
        $vm = Invoke-L08Az @('vm', 'show', '--resource-group', $rg, '--name', $n.appVm, '--show-details')
        $nsg = Invoke-L08Az @('network', 'nsg', 'show', '--resource-group', $rg, '--name', $n.serversNsg)
        $rule = @($nsg.securityRules | Where-Object name -eq 'allow-ssh-from-vnet')[0]
        $row = [pscustomobject]@{
            Bastion         = "$($b.name) ($($b.sku.name), $($b.properties.provisioningState))"
            'App public IP' = $(if ("$($vm.publicIps)") { $vm.publicIps } else { 'none' })
            'App private IP' = $vm.privateIps
            'NSG rule'      = "$($rule.name): $($rule.access) TCP $($rule.destinationPortRange) from $($rule.sourceAddressPrefix)"
        }
        [void](Write-L08Evidence 'access-bastion' $row)
        $row | Format-List | Out-String -Width 160 | Out-Host
        Write-Host "Connect in the portal: $($n.appVm) > Connect > Bastion, username $($cfg.adminUsername), SSH private key from local file."
    }
    'Probe' { Show-Probe }
    'Rules' { Show-Rules }
    'EnableJit' { Enable-Jit; Start-Sleep -Seconds 20; Show-Rules }
    'RemoveStanding' { Remove-Standing; Start-Sleep -Seconds 10; Show-Rules }
    'Request' { Request-Jit; Start-Sleep -Seconds 20; Show-Rules }
    'Policy' {
        $p = Invoke-L08Arm -Path $jit -AllowNotFound
        if (-not $p) { Write-Host 'No JIT policy yet.' }
        else {
            [void](Write-L08Evidence 'access-jit-policy' $p)
            $req = @(Get-L08Value $p 'properties.requests') | Select-Object -Last 1
            [pscustomobject]@{
                State       = $p.properties.provisioningState
                Port        = @(@($p.properties.virtualMachines)[0].ports)[0].number
                MaxDuration = @(@($p.properties.virtualMachines)[0].ports)[0].maxRequestAccessDuration
                LastRequest = $(if ($req) { "$($req.startTimeUtc) by $($req.requestor)" } else { 'none' })
            } | Format-List | Out-String -Width 160 | Out-Host
        }
    }
    'Sequence' {
        Write-Host '== 1. Standing access'; Show-Probe
        Write-Host '== 2. Enable JIT'; Enable-Jit; Start-Sleep -Seconds 30; Show-Rules; Show-Probe
        Write-Host '== 3. Remove the standing rule'; Remove-Standing; Start-Sleep -Seconds 15; Show-Probe
        Write-Host '== 4. Request access'; Request-Jit; Start-Sleep -Seconds 30; Show-Rules; Show-Probe
    }
}
