<#
.SYNOPSIS
    Decommissions the whole Lesson 5 lab after the take: records what exists, then deletes the VPN lab, the network
    lab and the Lesson 5 flow logs, and proves they're gone.

.DESCRIPTION

    READS:   every resource and lock in rg-sc500-l05-network and rg-sc500-l05-vpn, and the flow logs on
             NetworkWatcher_eastus2 that point at a Lesson 5 VNet.
    CHANGES: deletes rg-sc500-l05-vpn and rg-sc500-l05-network and everything in them (VMs, disks, NICs, ASGs, NSGs,
             VNets, both VPN gateways and their public IPs, both connections, the network manager, the flow-log
             storage account, the Log Analytics workspace), plus the Lesson 5 flow-log resources, which live in
             NetworkWatcherRG and would otherwise outlive their VNets. PERMANENT. NetworkWatcherRG itself and the
             network watcher stay (Azure creates them per region, and they're free).
    REFUSES: if the subscription or tenant isn't the course's, if either group isn't tagged managedBy=sc500-l05-iac,
             or if either group carries a lock.

.PARAMETER Execute
    Without it, the script records and reports only. With it, it deletes and waits until everything is gone.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-05\Remove-L05Lab.ps1
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-05\Remove-L05Lab.ps1 -Execute
#>
[CmdletBinding()]
param([switch]$Execute, [string]$LogPath = (Join-Path ([IO.Path]::GetTempPath()) 'sc500-l05-remove.log'))
$ErrorActionPreference = 'Stop'
Start-Transcript -Path $LogPath -Append | Out-Null
try {
    $cfg = Get-Content (Join-Path $PSScriptRoot '..\..\infra\lesson-05\config.json') -Raw | ConvertFrom-Json
    $sub = $cfg.subscriptionId
    $groups = @($cfg.vpnResourceGroup, $cfg.resourceGroup)   # VPN first: its connections reference the hub gateway
    if ($sub -ne '<your-subscription-id>') { throw "Unexpected subscription $sub in lesson-05 config." }
    $tenant = az account show --subscription $sub --query tenantId -o tsv
    if ($tenant -ne $cfg.tenantId) { throw "Signed in to tenant $tenant, not $($cfg.tenantId)." }

    # 'az group exists' returned something other than a bare "true" on the first run (17:31) and the script wrongly
    # reported both groups missing. Read the subscription's group list instead and test membership.
    function Get-GroupNames { @(az group list --subscription $sub --query "[].name" -o tsv | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) }

    # 1. Record first, so the deletion leaves an exact inventory in the git-ignored evidence tree.
    $evidence = Join-Path $PSScriptRoot '..\..\.azure\lesson-05\evidence'
    New-Item -ItemType Directory -Force -Path $evidence | Out-Null
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $inventory = [ordered]@{ recordedUtc = $stamp; groups = [ordered]@{}; flowLogs = @() }
    $present = @()
    foreach ($rg in $groups) {
        if ((Get-GroupNames) -notcontains $rg) { Write-Host "$rg doesn't exist; nothing to delete there."; continue }
        $tag = az group show --subscription $sub --name $rg --query "tags.managedBy" -o tsv
        if ($tag -ne $cfg.managedBy) { throw "$rg isn't tagged managedBy=$($cfg.managedBy) (reads '$tag'). Nothing was deleted." }
        $locks = @(az lock list --subscription $sub -g $rg -o json | ConvertFrom-Json)
        if ($locks.Count) { throw "$rg has $($locks.Count) lock(s). Nothing was deleted." }
        $res = az resource list --subscription $sub -g $rg --query "[].{name:name, type:type}" -o json | ConvertFrom-Json
        $inventory.groups[$rg] = $res
        $present += $rg
        Write-Host "$rg ($(@($res).Count) resources):"
        $res | Sort-Object type | ForEach-Object { Write-Host ('  {0,-55} {1}' -f $_.type, $_.name) }
    }
    # Flow logs are child resources of the regional network watcher, so they don't go away with the VNet's group.
    $fls = az network watcher flow-log list --subscription $sub --location $cfg.location --query "[?contains(targetResourceId, 'rg-sc500-l05')].{name:name, target:targetResourceId}" -o json | ConvertFrom-Json
    $inventory.flowLogs = $fls
    $fls | ForEach-Object { Write-Host ('  flow log {0,-40} -> {1}' -f $_.name, ($_.target -split '/')[-1]) }
    $inventory | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $evidence "decommission-inventory-$stamp.json") -Encoding utf8
    Write-Host "Inventory written: .azure\lesson-05\evidence\decommission-inventory-$stamp.json"
    if (-not $Execute) { Write-Host 'Report only. Re-run with -Execute to delete.'; return }

    # 2. Flow logs first, while their target VNets still exist.
    foreach ($f in $fls) {
        Write-Host "[$(Get-Date -Format s)] Deleting flow log $($f.name)."
        az network watcher flow-log delete --subscription $sub --location $cfg.location --name $f.name | Out-Null
    }
    # 3. The VPN group, then the network group. Gateways take 10 to 20 minutes to delete; both run at once.
    foreach ($rg in $present) {
        Write-Host "[$(Get-Date -Format s)] Deleting $rg (permanent)."
        az group delete --subscription $sub --name $rg --yes --no-wait
        Start-Sleep -Seconds 20   # let the VPN group's connections release the hub gateway before the network group starts
    }
    $deadline = (Get-Date).AddMinutes(45)
    do {
        Start-Sleep -Seconds 30
        $names = Get-GroupNames
        $left = @($present | Where-Object { $names -contains $_ })
        Write-Host "[$(Get-Date -Format s)] still deleting: $($left -join ', ')"
    } while ($left.Count -and (Get-Date) -lt $deadline)

    # 4. Read back. Absence is something we observed, never assumed.
    $flLeft = @(az network watcher flow-log list --subscription $sub --location $cfg.location --query "[?contains(targetResourceId, 'rg-sc500-l05')].name" -o tsv)
    Write-Host 'Groups left in the subscription:'
    az group list --subscription $sub --query "[].name" -o tsv
    if ($left.Count -or ($flLeft | Where-Object { $_ })) {
        Write-Host "FAIL: still present: $($left -join ', ') $($flLeft -join ', '). Check the portal's Activity log; billing may not have stopped."
        exit 1
    }
    Write-Host 'PASS: the Lesson 5 groups and flow logs no longer exist.'
}
finally { Stop-Transcript | Out-Null }
