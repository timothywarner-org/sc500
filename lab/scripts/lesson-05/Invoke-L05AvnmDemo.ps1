<#
.SYNOPSIS
    Demo 5.2: enforce a platform guardrail with Azure Virtual Network Manager security admin
    rules that workload NSGs can't override, in either direction.

.DESCRIPTION
    Runs after demo 5.1 (the least-privilege NSG rules are in place). The story:
      * Garth, the ServiceHub application engineer, adds an NSG rule so the web tier can SSH to
        the data tier while he troubleshoots. That's the introduced fault.
      * Contoso's platform policy says remote administration comes only from the platform
        management subnet, and the platform scanner must always reach SSH, even though the
        workload NSG's deny rule blocks it today.
    The security admin configuration (defined by network.bicep, not deployed at baseline) holds
    an Always Allow rule for the scanner at priority 100 and a Deny for SSH and RDP from
    everywhere else at priority 200. Deploying it changes both results without touching the NSG.

    Modes, in demo order:
      Settings        Manager scope, network group members, the admin rules, deployment state.
      AddTeamRule     Adds Garth's troubleshooting rule to nsg-servicehub (the fault).
      Probe           SSH from the web tier and from the platform scanner to the data tier.
      Deploy          Commits the security admin configuration to eastus2 and waits for it.
      EffectiveRules  Effective security admin rules on the ServiceHub VNet.
      FlowLogs        Flow-log records for SSH to the data tier, with the deciding rule.
      Undeploy        Removes the deployment (Reset-L05Lab.ps1 also does this).

.EXAMPLE
    pwsh -NoProfile -File C:\github\sc500\lab\scripts\lesson-05\Invoke-L05AvnmDemo.ps1 -Mode Deploy
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Settings', 'AddTeamRule', 'Probe', 'Deploy', 'EffectiveRules', 'FlowLogs', 'Undeploy')]
    [string]$Mode
)
. (Join-Path $PSScriptRoot 'L05.Common.ps1')
[void](Assert-L05Context)
$cfg = $script:L05Config
$rg = $cfg.resourceGroup
$h = $cfg.addressPlan.hosts
$lab = Get-L05Outputs
$manager = 'avnm-sc500-l05'
$managerPath = "/subscriptions/$($cfg.subscriptionId)/resourceGroups/$rg/providers/Microsoft.Network/networkManagers/$manager"
$api = 'api-version=2024-05-01'

function Invoke-L05Commit {
    # A commit replaces the whole set of deployed security admin configurations in a region.
    # An empty list removes the deployment.
    param([string[]]$ConfigurationIds)
    $body = @{ targetLocations = @($cfg.location); configurationIds = @($ConfigurationIds); commitType = 'SecurityAdmin' } | ConvertTo-Json -Compress
    [void](Invoke-L05Az -Raw @('rest', '--method', 'post', '--url', "https://management.azure.com$managerPath/commit?$api", '--body', $body))
    $deadline = (Get-Date).AddMinutes(10)
    do {
        Start-Sleep -Seconds 15
        $status = Invoke-L05Az @('rest', '--method', 'post', '--url', "https://management.azure.com$managerPath/listDeploymentStatus?$api",
            '--body', (@{ regions = @($cfg.location); deploymentTypes = @('SecurityAdmin') } | ConvertTo-Json -Compress))
        $state = @($status.value)[0]
        $s = if ($state) { $state.deploymentStatus } else { 'NotDeployed' }
        Write-Host "  deployment status: $s"
        # Removing the last configuration can leave no status row at all, which is also done.
        $done = $s -in 'Deployed', 'Failed' -or ($ConfigurationIds.Count -eq 0 -and $s -eq 'NotDeployed')
    } while (-not $done -and (Get-Date) -lt $deadline)
    if (-not $done) { throw 'The security admin deployment did not finish within 10 minutes.' }
    return $state
}

switch ($Mode) {
    'Settings' {
        $m = Invoke-L05Az @('rest', '--method', 'get', '--url', "https://management.azure.com$managerPath`?$api")
        $members = Invoke-L05Az @('rest', '--method', 'get', '--url', "https://management.azure.com$managerPath/networkGroups/ng-servicehub-workloads/staticMembers?$api")
        $rules = Invoke-L05Az @('rest', '--method', 'get', '--url', "https://management.azure.com$managerPath/securityAdminConfigurations/sac-contoso-platform-baseline/ruleCollections/rc-platform-remote-access/rules?$api")
        $status = Invoke-L05Az @('rest', '--method', 'post', '--url', "https://management.azure.com$managerPath/listDeploymentStatus?$api",
            '--body', (@{ regions = @($cfg.location); deploymentTypes = @('SecurityAdmin') } | ConvertTo-Json -Compress))
        $view = [ordered]@{
            Scope      = @($m.properties.networkManagerScopes.subscriptions)
            Access     = @($m.properties.networkManagerScopeAccesses)
            Members    = @($members.value | ForEach-Object { ($_.properties.resourceId -split '/')[-1] })
            Rules      = @($rules.value | Sort-Object { $_.properties.priority } | ForEach-Object {
                    [pscustomobject]@{ Priority = $_.properties.priority; Name = $_.name; Action = $_.properties.access; Source = ($_.properties.sources.addressPrefix -join ','); Ports = ($_.properties.destinationPortRanges -join ',') } })
            Deployment = if (@($status.value).Count) { @($status.value)[0].deploymentStatus } else { 'Not deployed' }
        }
        [void](Write-L05Evidence 'avnm-settings' $view)
        "Scope: $($view.Scope -join ', ')  Access: $($view.Access -join ', ')"
        "Network group ng-servicehub-workloads: $($view.Members -join ', ')"
        $view.Rules | Format-Table -AutoSize | Out-String
        "Security admin deployment in $($cfg.location): $($view.Deployment)"
    }
    'AddTeamRule' {
        [void](Invoke-L05Az @('network', 'nsg', 'rule', 'create', '--resource-group', $rg, '--nsg-name', 'nsg-servicehub', '--name', 'Allow-SSH-Web-To-Data-Troubleshooting',
                '--priority', '300', '--access', 'Allow', '--direction', 'Inbound', '--protocol', 'Tcp',
                '--source-asgs', 'asg-servicehub-web', '--destination-asgs', 'asg-servicehub-data', '--source-port-ranges', '*', '--destination-port-ranges', '22',
                '--description', 'Garth: temporary SSH from web to data while troubleshooting.'))
        $r = Invoke-L05Az @('network', 'nsg', 'rule', 'show', '--resource-group', $rg, '--nsg-name', 'nsg-servicehub', '--name', 'Allow-SSH-Web-To-Data-Troubleshooting')
        [void](Write-L05Evidence 'avnm-team-rule' $r)
        "Added $($r.name) at priority $($r.priority): $($r.access) TCP $($r.destinationPortRange) from asg-servicehub-web to asg-servicehub-data."
    }
    'Probe' {
        $target = [pscustomobject]@{ Name = 'data-ssh'; Ip = $h.data; Port = 22 }
        $rows = @(Test-L05Paths -ResourceGroup $rg -FromVm 'vm-servicehub-web' -Targets @($target))
        $rows += @(Test-L05Paths -ResourceGroup $rg -FromVm 'vm-platform-scan' -Targets @($target))
        [void](Write-L05Evidence 'avnm-probe' $rows)
        $rows | Select-Object From, To, Port, Result, Answer | Format-Table -AutoSize | Out-String -Width 200
    }
    'Deploy' {
        $state = Invoke-L05Commit -ConfigurationIds @($lab.securityAdminConfigId)
        [void](Write-L05Evidence 'avnm-deploy' $state)
        "Deployment $($state.deploymentStatus) at $($state.commitTime). Admin rules apply with eventual consistency; allow a minute before probing."
    }
    'EffectiveRules' {
        $e = Invoke-L05Az @('rest', '--method', 'post', '--url', "https://management.azure.com$($lab.spokeVnetId)/listNetworkManagerEffectiveSecurityAdminRules?$api", '--body', '{}')
        # Each entry keeps its rule settings under 'properties'. The effective 'priority' there
        # is the evaluation order on this VNet (0, 1, ...), not the priority the platform team
        # configured, so we read the configured value from the rule itself and show both.
        $rows = @($e.value | Sort-Object { $_.properties.priority } | ForEach-Object {
                $p = $_.properties
                $configured = Invoke-L05Az @('rest', '--method', 'get', '--url', "https://management.azure.com$($_.id)?$api")
                [pscustomobject]@{
                    Order    = $p.priority
                    Priority = $configured.properties.priority
                    Name     = ($_.id -split '/')[-1]
                    Action   = $p.access
                    Source   = ($p.sources.addressPrefix -join ',')
                    Ports    = ($p.destinationPortRanges -join ',')
                } })
        [void](Write-L05Evidence 'avnm-effective' $rows)
        if (-not $rows.Count) { 'No security admin rules are in effect on vnet-sc500-l05-servicehub.' }
        else { $rows | Format-Table -AutoSize | Out-String -Width 200 }
    }
    'FlowLogs' {
        Get-L05FlowTuples -VnetName 'vnet-sc500-l05-servicehub' -DestinationPort 22 -EvidenceName 'avnm-flowlogs'
    }
    'Undeploy' {
        $state = Invoke-L05Commit -ConfigurationIds @()
        [void](Write-L05Evidence 'avnm-undeploy' $state)
        'Security admin configuration removed from the region.'
    }
}
