<#
.SYNOPSIS
    Demo 6.3 support: read-only checks around Microsoft Entra Private Access for the ServiceHub
    private API. Separate scoped setup scripts configure the pilot; the user sign-in is interactive.

.DESCRIPTION
    Private Access needs an interactive Global Administrator sign-in to register the first
    connector, tenant-level settings (activating Global Secure Access, the Private access
    traffic forwarding profile), and a signed-in user on a device with the Global Secure Access
    client. These modes only read and test; Set-L06PrivateAccessPilot.ps1 configures the pilot
    with the authenticated operator's delegated permissions:
      Readiness  Private Access licensing in the tenant, the signed-in admin's directory roles,
                 and the private network connectors registered so far.
      Target     From the bounded connector host, tests the ServiceHub private API
                 (10.60.16.4:8080) the connector will publish. Needs Deploy-L06Bounded.ps1
                 -Lab Connector and the retained VM running.
      Connectors Lists registered private network connectors and their status (after you
                 installs one).
    The click-by-click Private Access steps are in the Lesson 6 technical preparation page.

.PARAMETER Mode
    Readiness, Target, or Connectors.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Invoke-L06PrivateAccessDemo.ps1 -Mode Readiness
#>
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Readiness', 'Target', 'Connectors')][string]$Mode)
. (Join-Path $PSScriptRoot 'L06.Common.ps1')
[void](Assert-L06Context)
$cfg = $script:L06Config

function Get-Connectors {
    # Reuse the Graph permission grant used during setup; an Azure token is a different audience.
    Import-Module Microsoft.Graph.Authentication
    Connect-MgGraph -TenantId $cfg.tenantId -Scopes 'NetworkAccess.ReadWrite.All','Application.ReadWrite.All','Policy.ReadWrite.ConditionalAccess','Group.ReadWrite.All','User.Read.All' -ContextScope CurrentUser -NoWelcome
    $r=Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/beta/onPremisesPublishingProfiles/applicationProxy/connectors' -OutputType PSObject
    $items = @($r.value)
    return @($items | ForEach-Object { [pscustomobject]@{ Connector = $_.machineName; Status = $_.status; ExternalIp = $_.externalIp } })
}

switch ($Mode) {
    'Readiness' {
        $skus = @((Invoke-L06Az -NoSubscription @('rest', '--method', 'get', '--url', 'https://graph.microsoft.com/v1.0/subscribedSkus')).value)
        $plans = foreach ($s in $skus) {
            foreach ($p in @($s.servicePlans | Where-Object { $_.servicePlanName -in 'Entra_Premium_Private_Access', 'AAD_PREMIUM', 'AAD_PREMIUM_P2' })) {
                [pscustomobject]@{ Sku = $s.skuPartNumber; Plan = $p.servicePlanName; Status = $p.provisioningStatus; Assigned = "$($s.consumedUnits) of $($s.prepaidUnits.enabled)" }
            }
        }
        $roles = @((Invoke-L06Az -NoSubscription @('rest', '--method', 'get', '--url', 'https://graph.microsoft.com/v1.0/me/memberOf')).value |
                Where-Object { $_.'@odata.type' -eq '#microsoft.graph.directoryRole' } | ForEach-Object { $_.displayName })
        $view = [ordered]@{
            PrivateAccessPlans = @($plans | Where-Object Plan -eq 'Entra_Premium_Private_Access' | ForEach-Object { "$($_.Sku): $($_.Status), $($_.Assigned) assigned" })
            EntraIdPremium     = @($plans | Where-Object Plan -ne 'Entra_Premium_Private_Access' | ForEach-Object { "$($_.Sku) $($_.Plan)" } | Select-Object -Unique)
            SignedInRoles      = $roles
            Connectors         = @(Get-Connectors | ForEach-Object { "$($_.Connector): $($_.Status)" })
        }
        if (-not $view.Connectors.Count) { $view.Connectors = 'none registered yet' }
        [void](Write-L06Evidence 'private-access-readiness' $view)
        $view.GetEnumerator() | ForEach-Object { '{0,-19} {1}' -f $_.Key, ($_.Value -join '; ') }
    }
    'Target' {
        $c = Get-L06Outputs -Lab Connector
        Assert-L06GuestReady -ResourceGroup $c.resourceGroup -VmName $c.vm
        $target = "$($cfg.addressPlan.hosts.app):$($cfg.ports.app)"
        $ps = "`$t = Test-NetConnection -ComputerName $($cfg.addressPlan.hosts.app) -Port $($cfg.ports.app) -WarningAction SilentlyContinue; " +
              "`$b = try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 -Uri 'http://$target/').Content.Trim() } catch { 'no answer' }; " +
              "'TARGET|' + `$t.TcpTestSucceeded + '|' + `$b"
        $r = Invoke-L06Az @('vm', 'run-command', 'invoke', '--resource-group', $c.resourceGroup, '--name', $c.vm, '--command-id', 'RunPowerShellScript', '--scripts', $ps)
        $msg = [string]@($r.value)[0].message
        $row = if ($msg -match 'TARGET\|(\w+)\|(.*)') { [pscustomobject]@{ From = "$($c.vm) ($($c.privateIp))"; To = $target; TcpOpen = $Matches[1]; Answer = $Matches[2].Trim() } }
               else { [pscustomobject]@{ From = $c.vm; To = $target; TcpOpen = 'unknown'; Answer = $msg.Trim() } }
        [void](Write-L06Evidence 'private-access-target' $row)
        $row | Format-List | Out-String -Width 200
        if($row.TcpOpen -ne 'True' -or $row.Answer -notmatch 'Contoso ServiceHub'){throw 'Connector target probe failed; transport completion is not app reachability.'}
    }
    'Connectors' {
        $rows = @(Get-Connectors)
        # An empty list is a real answer (nothing registered yet), so record it as such rather
        # than passing an empty value to the evidence writer.
        $record = if ($rows.Count) { $rows } else { [pscustomobject]@{ Connector = 'none registered yet'; Status = ''; ExternalIp = '' } }
        [void](Write-L06Evidence 'private-access-connectors' $record)
        if (-not $rows.Count) { 'No private network connectors are registered in the tenant yet.' }
        else { $rows | Format-Table -AutoSize | Out-String -Width 200 }
    }
}
