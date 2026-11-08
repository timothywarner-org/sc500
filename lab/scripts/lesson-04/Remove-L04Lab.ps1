<#
.SYNOPSIS
    Decommissions the Lesson 4 lab: records what exists, confirms the Defender window is parked, then deletes rg-sc500-l04-data.

.DESCRIPTION

    READS:   every resource, lock and storage immutability policy in the group; the five Lesson 4 Defender plans.
    CHANGES: deletes rg-sc500-l04-data and everything in it (two storage accounts, the SQL server and database, the
             Log Analytics workspace, the Event Grid system topic). PERMANENT. Nothing outside the group is touched:
             NetworkWatcherRG and the Lesson 5 groups stay.
    REFUSES: if any Lesson 4 Defender plan still reads Standard (park it first with Set-L04DefenderWindow.ps1 -State
             Close), if the group carries a lock, or if a container has a locked immutability policy.

.PARAMETER Execute
    Without it, the script only records and reports. With it, it deletes the group and waits until it's gone.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-04\Remove-L04Lab.ps1
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-04\Remove-L04Lab.ps1 -Execute
#>
[CmdletBinding()]
param([switch]$Execute, [string]$LogPath = (Join-Path ([IO.Path]::GetTempPath()) 'sc500-l04-remove.log'))
$ErrorActionPreference = 'Stop'
Start-Transcript -Path $LogPath -Append | Out-Null
try {
    $cfg = Get-Content (Join-Path $PSScriptRoot '..\..\infra\lesson-04\config.json') -Raw | ConvertFrom-Json
    $sub = $cfg.subscriptionId; $rg = $cfg.resourceGroup
    if ($rg -ne 'rg-sc500-l04-data') { throw "Unexpected group $rg in lesson-04 config." }
    $tenant = az account show --subscription $sub --query tenantId -o tsv
    if ($tenant -ne '<your-tenant-id>') { throw "Wrong tenant $tenant." }

    # Record first, so the deletion leaves an exact inventory behind in the git-ignored evidence tree.
    $resources = az graph query -q "resources | where subscriptionId == '$sub' and resourceGroup =~ '$rg' | project id, name, type, sku, tags" --first 200 -o json | ConvertFrom-Json
    $evidence = Join-Path $PSScriptRoot '..\..\.azure\lesson-04\evidence'
    New-Item -ItemType Directory -Force -Path $evidence | Out-Null
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $resources | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $evidence "decommission-inventory-$stamp.json") -Encoding utf8
    Write-Host "Inventory: $($resources.count) resources in $rg"
    $resources.data | ForEach-Object { Write-Host ('  {0,-45} {1}' -f $_.type, $_.name) }

    # Guards: plans parked, no locks, no locked immutability.
    foreach ($p in 'StorageAccounts', 'SqlServers', 'SqlServerVirtualMachines', 'OpenSourceRelationalDatabases', 'CosmosDbs') {
        $tier = az security pricing show --subscription $sub -n $p --query pricingTier -o tsv
        Write-Host ('  plan {0,-30} {1}' -f $p, $tier)
        if ($tier -ne 'Free') { throw "$p reads $tier. Park it first: Set-L04DefenderWindow.ps1 -State Close." }
    }
    $locks = az lock list --subscription $sub -g $rg -o json | ConvertFrom-Json
    if (@($locks).Count) { throw "Group has $(@($locks).Count) lock(s); not deleting." }
    foreach ($sa in ($resources.data | Where-Object type -eq 'microsoft.storage/storageaccounts')) {
        $cons = az storage container-rm list --subscription $sub -g $rg --storage-account $sa.name --query "[].{n:name, imm:immutabilityPolicy.state, hold:hasLegalHold}" -o json | ConvertFrom-Json
        foreach ($c in $cons) {
            Write-Host ('  {0}/{1} immutability={2} legalHold={3}' -f $sa.name, $c.n, $c.imm, $c.hold)
            if ($c.imm -eq 'Locked' -or $c.hold) { throw "$($sa.name)/$($c.n) is immutable or on legal hold; not deleting." }
        }
    }
    if (-not $Execute) { Write-Host 'Report only. Re-run with -Execute to delete.'; return }

    Write-Host "[$(Get-Date -Format s)] Deleting $rg (permanent)."
    az group delete --subscription $sub --name $rg --yes --no-wait
    $deadline = (Get-Date).AddMinutes(30)
    do { Start-Sleep -Seconds 30; $exists = az group exists --subscription $sub --name $rg } while ($exists -eq 'true' -and (Get-Date) -lt $deadline)
    if ($exists -eq 'true') { Write-Host "FAIL: $rg still exists after 30 minutes; check the portal's Activity log."; exit 1 }
    Write-Host "PASS: $rg no longer exists. Groups left in the subscription:"
    az group list --subscription $sub --query "[].name" -o tsv
}
finally { Stop-Transcript | Out-Null }
