<#
.SYNOPSIS
    Deploys the SC-500 Lesson 13 lab: a Microsoft Sentinel workspace for ServiceHub, every ingestion
    route the lesson demonstrates, and two private collector VMs.
.DESCRIPTION
    Design goal: minimal or no cost, VMs deallocated until they're needed.
      (no switch)  ARM what-if. Changes nothing.
      -Deploy      main.bicep creates rg-secops-shared-eastus2: the workspace (90-day retention, 1 GB daily
                   cap) with Microsoft Sentinel enabled, the ServiceHubAudit_CL table, five data
                   collection rules, your Monitoring Metrics Publisher role on the ServiceHub DCR, a
                   Linux forwarder and a Windows collector with the Azure Monitor Agent and their DCR
                   associations, and a temporary NAT gateway. It also sends the subscription's Activity
                   log to the workspace. Then it creates two empty security groups for the role demo,
                   installs the Syslog/CEF forwarder configuration, and configures WEF on the collector.
                   The VMs are left running; run Stop-L13Lab.ps1 when the session ends.
    Nothing here is tenant scoped: Microsoft Entra, Microsoft 365, Defender XDR, and the Defender
    portal connection are your steps (see the technical prep). No script signs in as anyone.
    Secrets: the Linux VM gets a public key whose private half is never created on disk, and the
    Windows VM gets a random password that exists only in this process and a deleted temporary
    parameter file. Nobody signs in to either VM; Run Command manages them.
    Costs: Sentinel's free trial covers the first 10 GB/day of Analytics ingestion for 31 days, and
    this lab ingests kilobytes. Activity log ingestion is free. VM compute and the NAT gateway bill
    only while running; disks bill while deallocated.
.PARAMETER Deploy Create or update the lab and configure both collectors.
.PARAMETER SkipGuests Deploy the Azure resources only (skip forwarder and WEF configuration).
.PARAMETER GuestsOnly Skip the ARM deployment and rerun only the forwarder and WEF configuration
    (the VMs must be running; Start-L13Lab.ps1 starts them).
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Deploy-L13Lab.ps1
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Deploy-L13Lab.ps1 -Deploy
#>
[CmdletBinding()]
param([switch]$Deploy, [switch]$SkipGuests, [switch]$GuestsOnly)
. (Join-Path $PSScriptRoot 'L13.Common.ps1')
$cfg = $script:L13Config
$started = Get-Date
[void](Assert-L13Context)
$me = Invoke-L13Az -NoSubscription @('ad', 'signed-in-user', 'show', '--query', '{id:id,upn:userPrincipalName}')
[void][IO.Directory]::CreateDirectory($script:L13State)

function New-L13PublicKey {
    # An OpenSSH ssh-rsa public key from an in-memory RSA key. The private key is never exported.
    $rsa = [Security.Cryptography.RSA]::Create(3072)
    try {
        $p = $rsa.ExportParameters($false)
        $ms = [IO.MemoryStream]::new()
        $write = {
            param([byte[]]$bytes)
            $len = [BitConverter]::GetBytes([int]$bytes.Length); [Array]::Reverse($len)
            $ms.Write($len, 0, 4); $ms.Write($bytes, 0, $bytes.Length)
        }
        & $write ([Text.Encoding]::ASCII.GetBytes('ssh-rsa'))
        # SSH mpints are big-endian and need a leading zero byte when the high bit is set.
        foreach ($v in @($p.Exponent, $p.Modulus)) { if ($v[0] -band 0x80) { $v = [byte[]](@(0) + $v) }; & $write $v }
        return 'ssh-rsa ' + [Convert]::ToBase64String($ms.ToArray()) + ' sc500-l13-no-private-key'
    }
    finally { $rsa.Dispose() }
}

function New-L13Password {
    # 28 random characters with every class Windows requires. Held in memory only.
    $sets = @('ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789', '!@#%^*-_=+')
    $all = -join $sets
    $chars = foreach ($i in 1..24) { $all[[Security.Cryptography.RandomNumberGenerator]::GetInt32($all.Length)] }
    $chars += foreach ($s in $sets) { $s[[Security.Cryptography.RandomNumberGenerator]::GetInt32($s.Length)] }
    return -join ($chars | Sort-Object { [Security.Cryptography.RandomNumberGenerator]::GetInt32(1000) })
}

if ($GuestsOnly) {
    $lab = Get-L13Outputs
    foreach ($vm in @($cfg.names.forwarderVm, $cfg.names.collectorVm)) { Assert-L13Running -Vm $vm }
}
else {
    # A VM's admin credentials can't change after creation, and this script generates new ones every
    # run, so the hosts module only runs when a VM is missing.
    $vmNames = @(Invoke-L13Az -AllowFailure @('vm', 'list', '--resource-group', $cfg.resourceGroup, '--query', '[].name') |
        ForEach-Object { if ($_.ExitCode -eq 0 -and $_.Stdout) { $_.Stdout | ConvertFrom-Json } })
    $deployHosts = -not (($vmNames -contains $cfg.names.forwarderVm) -and ($vmNames -contains $cfg.names.collectorVm))
    if (-not $deployHosts) { Write-Host 'Both collector VMs exist; the hosts module is skipped so their credentials stay unchanged.' }
    $params = [ordered]@{
        location = @{ value = $cfg.location }; resourceGroupName = @{ value = $cfg.resourceGroup }
        names = @{ value = $cfg.names }; workspace = @{ value = $cfg.workspace }; customTable = @{ value = $cfg.customTable }
        collection = @{ value = $cfg.collection }; vm = @{ value = $cfg.vm }; operatorObjectId = @{ value = $me.id }
        roles = @{ value = $cfg.roles }; tags = @{ value = $cfg.tags }; baseline = @{ value = $cfg.baseline }
        linuxPublicKey = @{ value = (New-L13PublicKey) }; windowsAdminPassword = @{ value = (New-L13Password) }
        deployHosts = @{ value = $deployHosts }
    }
    # The parameter file holds the generated password, so it lives in the user's temp folder (not the
    # repo, not a synced folder) and is deleted in the finally block below.
    $paramFile = Join-Path ([IO.Path]::GetTempPath()) ("sc500-l13-" + [guid]::NewGuid().ToString('N') + '.parameters.json')
    try {
        @{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = $params } |
            ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $paramFile -Encoding utf8
        $common = @('--name', $cfg.deploymentName, '--location', $cfg.location, '--template-file', (Join-Path $script:L13Infra 'main.bicep'), '--parameters', "@$paramFile")
        if (-not $Deploy) {
            Write-Host '== ARM what-if (nothing changes)'
            Invoke-L13Az -Raw (@('deployment', 'sub', 'what-if') + $common + @('--result-format', 'ResourceIdOnly', '--no-pretty-print')) | Out-Host
            return
        }
        Write-Host 'Deploying the Sentinel workspace, collection rules, and collectors. Allow about ten minutes.'
        $d = Invoke-L13Az (@('deployment', 'sub', 'create') + $common)
    }
    finally { Remove-Item -LiteralPath $paramFile -ErrorAction SilentlyContinue }

    if ($d.properties.provisioningState -ne 'Succeeded') { throw "Deployment ended $($d.properties.provisioningState)." }
    $lab = $d.properties.outputs.lab.value
    Write-Host "Workspace $($lab.workspace) with Sentinel; forwarder $($cfg.names.forwarderVm); collector $($cfg.names.collectorVm)."
}

# ---- Empty security groups for demo 13.1 (no members; the role assignments are the demo) -----------
$groups = [ordered]@{}
if (-not $GuestsOnly) { foreach ($g in @(@{ key = 'analysts'; name = $cfg.names.analystGroup; nick = 'sc500-soc-analysts' }, @{ key = 'engineers'; name = $cfg.names.engineerGroup; nick = 'sc500-soc-engineers' })) {
    $found = @(Invoke-L13Az -NoSubscription @('ad', 'group', 'list', '--filter', "displayName eq '$($g.name)'", '--query', '[].id'))
    if ($found.Count -eq 0) {
        $new = Invoke-L13Az -NoSubscription @('ad', 'group', 'create', '--display-name', $g.name, '--mail-nickname', $g.nick,
            '--description', 'SC-500 Lesson 13 Microsoft Sentinel role demo. No members.')
        $groups[$g.key] = $new.id; Write-Host "Created group $($g.name)."
    }
    else { $groups[$g.key] = $found[0]; Write-Host "Group $($g.name) already exists." }
} }

$guests = [ordered]@{}
if (-not $SkipGuests -and ($GuestsOnly -or $Deploy)) {
    Write-Host 'Configuring the Linux forwarder for Syslog and CEF (Microsoft''s AMA forwarder script).'
    $guests.forwarder = Invoke-L13Guest -Vm $cfg.names.forwarderVm -Name 'Install-L13Forwarder.sh'
    Write-Host $guests.forwarder
    Write-Host 'Configuring Windows Event Forwarding on the collector.'
    $guests.collector = Invoke-L13Guest -Vm $cfg.names.collectorVm -Name 'Set-L13Wef.ps1' -Values @{
        SUBSCRIPTION = $cfg.names.wefSubscription; QUERY = $cfg.collection.wefQuery }
    Write-Host $guests.collector
}

# Run Command reports success whenever the script ran, so check each guest's own success markers.
$guestProblems = @()
if ($guests.Contains('forwarder') -and $guests.forwarder -notmatch 'Installation completed successfully') { $guestProblems += 'forwarder configuration' }
if ($guests.Contains('collector') -and $guests.collector -notmatch 'RunTimeStatus: Active') { $guestProblems += 'WEF subscription' }
[void](Write-L13Evidence 'deploy' ([ordered]@{
    deployedUtc = [DateTime]::UtcNow.ToString('o'); minutes = [math]::Round(((Get-Date) - $started).TotalMinutes, 1)
    lab = $lab; groups = $groups; guests = $guests; guestProblems = $guestProblems
}))
if ($guestProblems) { throw "Guest configuration didn't finish: $($guestProblems -join ', '). Read the output above and rerun with -GuestsOnly." }
Write-Host ("Done in {0:N1} minutes. The VMs are running with temporary egress; run Stop-L13Lab.ps1 when the session ends." -f ((Get-Date) - $started).TotalMinutes)
