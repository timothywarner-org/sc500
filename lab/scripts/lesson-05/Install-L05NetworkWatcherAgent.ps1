<#
.SYNOPSIS
    Starts the retained Lesson 5 VMs and installs the Network Watcher agent on the four Connection troubleshoot sources.

.DESCRIPTION
    WHY: the Lesson 5 demo tests paths with Network Watcher Connection troubleshoot from vm-servicehub-web,
    vm-servicehub-app, vm-platform-scan and vm-branch-client. The GA path for that test needs the
    NetworkWatcherAgentLinux VM extension on the SOURCE VM. Learn also lists an agentless experience, but it's in
    preview, so the course doesn't depend on it. Installing the agent doesn't reboot the VM.

    READS:   VM power state and extension state, in the subscription and tenant pinned by lesson-05\config.json.
    CHANGES: starts the four retained B2s VMs (compute billing, about 0.17 USD an hour together) and adds one VM
             extension per source VM. It never redeploys the lab and never touches NSGs, AVNM, gateways or connections.
    IDEMPOTENT: re-running on a VM that already has the extension leaves it in place (az vm extension set is a PUT).

    Stop compute afterward with Start-L05Lab.ps1 -Stop. The extension stays installed on the disk.

.PARAMETER LogPath
    Transcript path, so a hidden run can be read back afterward.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-05\Install-L05NetworkWatcherAgent.ps1
#>
[CmdletBinding()]
param([string]$LogPath = (Join-Path ([IO.Path]::GetTempPath()) 'sc500-l05-nw-agent.log'))
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path (Split-Path $LogPath) | Out-Null
Start-Transcript -Path $LogPath -Append | Out-Null
try {
    # Pin the subscription and tenant from the lesson config, never from whatever az happens to default to.
    $cfg = Get-Content (Join-Path $PSScriptRoot '..\..\infra\lesson-05\config.json') -Raw | ConvertFrom-Json
    $sub = $cfg.subscriptionId
    $acctTenant = az account show --subscription $sub --query tenantId -o tsv
    if ($acctTenant -ne $cfg.tenantId) { throw "Signed-in tenant $acctTenant isn't the course tenant $($cfg.tenantId)." }

    Write-Host "[$(Get-Date -Format s)] Starting the retained VMs with the repo's own script."
    pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Start-L05Lab.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Start-L05Lab.ps1 failed.' }

    # Only the SOURCE side of each demo probe needs the agent. The data VM is a destination only.
    $targets = @(
        @{ rg = $cfg.resourceGroup;    vm = 'vm-servicehub-web' },
        @{ rg = $cfg.resourceGroup;    vm = 'vm-servicehub-app' },
        @{ rg = $cfg.resourceGroup;    vm = 'vm-platform-scan' },
        @{ rg = $cfg.vpnResourceGroup; vm = 'vm-branch-client' }
    )
    foreach ($t in $targets) {
        Write-Host "[$(Get-Date -Format s)] Requesting NetworkWatcherAgentLinux on $($t.vm) (no reboot)."
        az vm extension set --subscription $sub --resource-group $t.rg --vm-name $t.vm `
            --name NetworkWatcherAgentLinux --publisher Microsoft.Azure.NetworkWatcher --version 1.4 --no-wait
        if ($LASTEXITCODE -ne 0) { throw "Extension request failed on $($t.vm)." }
    }

    # Poll until every source reports Succeeded, or give up after 15 minutes and say which ones didn't.
    $deadline = (Get-Date).AddMinutes(15)
    do {
        Start-Sleep -Seconds 20
        $pending = @()
        foreach ($t in $targets) {
            $s = az vm extension show --subscription $sub -g $t.rg --vm-name $t.vm -n NetworkWatcherAgentLinux --query provisioningState -o tsv 2>$null
            Write-Host ('  {0,-20} {1}' -f $t.vm, $s)
            if ($s -ne 'Succeeded') { $pending += $t.vm }
        }
    } while ($pending.Count -gt 0 -and (Get-Date) -lt $deadline)
    if ($pending.Count) { Write-Host "FAIL: not Succeeded after 15 minutes: $($pending -join ', ')"; exit 1 }
    Write-Host 'PASS: NetworkWatcherAgentLinux Succeeded on all four sources.'
}
finally { Stop-Transcript | Out-Null }
