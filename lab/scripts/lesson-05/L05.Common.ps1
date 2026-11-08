<#
.SYNOPSIS
    Shared helpers for the SC-500 Lesson 5 lab: pin the subscription, call Azure CLI safely,
    save private evidence, read deployment outputs, and run connection probes inside VMs.
.DESCRIPTION
    Dot-source this file from the other Lesson 5 scripts. None of the VMs has a public IP or
    an SSH private key anyone keeps, so every in-guest test goes through Azure Run Command.
    Nothing here prints a secret; the VPN pre-shared key never leaves the deploy script's memory.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:L05Lab = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:L05Config = Get-Content (Join-Path $script:L05Lab 'infra/lesson-05/config.json') -Raw | ConvertFrom-Json
$script:L05State = Join-Path $script:L05Lab '.azure/lesson-05'
$script:L05Evidence = Join-Path $script:L05State 'evidence'

# Call the CLI's own Python instead of az.cmd. az.cmd is a batch file, and cmd.exe mangles
# arguments that contain &, %, or quotes, which in-guest bash scripts are full of.
$script:L05Python = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe'
if (-not (Test-Path -LiteralPath $script:L05Python)) { throw "Azure CLI Python not found at $script:L05Python. Install Azure CLI 2.85 or later." }

function Invoke-L05Az {
    <#
    .SYNOPSIS Runs one Azure CLI command pinned to the lesson subscription.
    .PARAMETER Arguments The CLI arguments, one element per token.
    .PARAMETER AllowFailure Return exit code, stdout, and stderr instead of throwing.
    .PARAMETER NoSubscription Omit --subscription (Graph and data-plane commands reject it).
    #>
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$Raw,
        [switch]$AllowFailure,
        [switch]$NoSubscription
    )
    $start = [Diagnostics.ProcessStartInfo]::new($script:L05Python)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $all = @('-Im', 'azure.cli') + $Arguments + @('--only-show-errors')
    if (-not $NoSubscription) { $all += @('--subscription', $script:L05Config.subscriptionId) }
    if (-not $Raw) { $all += @('--output', 'json') }
    foreach ($a in $all) { $start.ArgumentList.Add($a) }
    $p = [Diagnostics.Process]::new(); $p.StartInfo = $start
    try {
        [void]$p.Start()
        $outTask = $p.StandardOutput.ReadToEndAsync(); $errTask = $p.StandardError.ReadToEndAsync()
        $p.WaitForExit()
        $stdout = $outTask.GetAwaiter().GetResult(); $stderr = $errTask.GetAwaiter().GetResult()
        if ($AllowFailure) { return [pscustomobject]@{ ExitCode = $p.ExitCode; Stdout = $stdout; Stderr = $stderr } }
        if ($p.ExitCode -ne 0) { throw "Azure CLI failed ($($p.ExitCode)): $($stderr.Trim())" }
        if ($Raw) { return $stdout.Trim() }
        if (-not [string]::IsNullOrWhiteSpace($stdout)) { return $stdout | ConvertFrom-Json -Depth 100 }
    }
    finally { $p.Dispose() }
}

function Assert-L05Context {
    # Refuse to run against any subscription or tenant but the course's.
    $account = Invoke-L05Az @('account', 'show')
    if ($account.id -ne $script:L05Config.subscriptionId -or $account.tenantId -ne $script:L05Config.tenantId) {
        throw 'The signed-in Azure CLI context is not the course subscription and tenant.'
    }
    Write-Host "Lesson 5: $($account.name), signed in as $($account.user.name)."
    return $account
}

function Write-L05Evidence {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)]$Value)
    [void][IO.Directory]::CreateDirectory($script:L05Evidence)
    $file = Join-Path $script:L05Evidence ('{0}-{1}.json' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'), $Name)
    $Value | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $file -Encoding utf8
    return $file
}

function Get-L05Outputs {
    # Read names from the deployment record in ARM, not a local file, so a stale copy can't
    # point a demo at the wrong resource.
    param([ValidateSet('Network', 'Wan', 'Vpn')][string]$Lab = 'Network')
    $name = switch ($Lab) { 'Network' { $script:L05Config.deploymentName } 'Wan' { $script:L05Config.wanDeploymentName } 'Vpn' { $script:L05Config.vpnDeploymentName } }
    $d = Invoke-L05Az -AllowFailure @('deployment', 'sub', 'show', '--name', $name)
    if ($d.ExitCode -ne 0) { throw "No $Lab deployment named $name. Deploy it first." }
    $d = $d.Stdout | ConvertFrom-Json -Depth 100
    if ($d.properties.provisioningState -ne 'Succeeded') { throw "The $Lab deployment is $($d.properties.provisioningState), not Succeeded." }
    return $d.properties.outputs.lab.value
}

function Get-L05HubVpnResources {
    <#
    .SYNOPSIS Returns any bounded VPN gateway and public IP still present in the retained hub.
    .DESCRIPTION An authenticated, successful inventory is required before reporting absence.
        Authentication, authorization, throttling, or service errors must never mean "deleted".
    #>
    # Why: the generic 'az resource list' inventory came back without the hub gateway
    # while 'az network vnet-gateway list' still showed it, so Remove-L05Bounded.ps1 -Lab Vpn reported "absent" and
    # left a billing gateway behind. Ask each resource provider directly, and flatten, because a JSON array can
    # arrive as one object.
    $rg = $script:L05Config.resourceGroup
    $items = foreach ($kind in 'vnet-gateway', 'public-ip') { Invoke-L05Az @('network', $kind, 'list', '--resource-group', $rg) }
    $inventory = @($items | ForEach-Object { $_ } | Where-Object { $_ })
    @($inventory | Where-Object { $_.name -in 'vgw-contoso-platform-hub', 'pip-vgw-contoso-platform-hub' })
}

function Get-L05Value {
    <#
    .SYNOPSIS Reads a dotted property path from ARM JSON, returning $null when any part is
             missing. ARM omits optional properties, and StrictMode would otherwise throw.
    #>
    param($Object, [Parameter(Mandatory)][string]$Path)
    $cur = $Object
    foreach ($part in $Path -split '\.') {
        if ($null -eq $cur) { return $null }
        $prop = $cur.PSObject.Properties[$part]
        if ($null -eq $prop) { return $null }
        $cur = $prop.Value
    }
    return $cur
}

function New-L05SshPublicKey {
    # Linux VMs need an SSH key, but nobody signs in to these fixtures; tests use Run Command.
    # The private half is never written anywhere and is discarded with the RSA object.
    $rsa = [Security.Cryptography.RSA]::Create(3072)
    try {
        $key = $rsa.ExportParameters($false)
        $stream = [IO.MemoryStream]::new()
        foreach ($part in @([Text.Encoding]::ASCII.GetBytes('ssh-rsa'), $key.Exponent, ([byte[]]@(0) + $key.Modulus))) {
            $bytes = [byte[]]$part; $length = [BitConverter]::GetBytes([uint32]$bytes.Length); [Array]::Reverse($length)
            $stream.Write($length); $stream.Write($bytes)
        }
        $publicKey = 'ssh-rsa ' + [Convert]::ToBase64String($stream.ToArray()) + ' sc500-l05-run-command-only'
        $stream.Dispose()
        return $publicKey
    }
    finally { $rsa.Dispose() }
}

function Invoke-L05Guest {
    <#
    .SYNOPSIS Runs a bash script inside a lab VM with Run Command and returns its stdout.
    .DESCRIPTION Run Command travels through the Azure control plane and the VM agent, not
             the network paths the lesson tests, so it can't be confused with a probe result.
    #>
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(Mandatory)][string]$Script
    )
    $r = Invoke-L05Az @('vm', 'run-command', 'invoke', '--resource-group', $ResourceGroup, '--name', $VmName,
        '--command-id', 'RunShellScript', '--scripts', $Script)
    $message = [string]$r.value[0].message
    # The message is "Enable succeeded: \n[stdout]\n...\n[stderr]\n...". Keep stdout only.
    if ($message -match '(?s)\[stdout\]\s*(.*?)\s*\[stderr\]') { return $Matches[1].Trim() }
    return $message.Trim()
}

function Test-L05Paths {
    <#
    .SYNOPSIS Probes several TCP destinations from one VM in a single Run Command call.
    .PARAMETER Targets Objects with Name, Ip, and Port.
    .OUTPUTS One row per target: OPEN when the TCP handshake completed within four seconds,
             BLOCKED when it didn't. For HTTP listeners the first response line is captured.
    .NOTES A dropped SYN and a refused connection both read BLOCKED here; the NSG, admin rule,
           or firewall evidence says which control made the decision.
    #>
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$FromVm,
        [Parameter(Mandatory)][object[]]$Targets
    )
    $lines = foreach ($t in $Targets) {
        # bash's /dev/tcp opens a real TCP connection without installing anything. SSH answers
        # with a banner line; the HTTP listeners answer a GET with one line of text.
        $answer = if ($t.Port -eq 22) { "timeout 4 bash -c 'exec 3<>/dev/tcp/$($t.Ip)/22; head -n 1 <&3' 2>/dev/null | tr -d '\r'" }
                  else { "curl -s -m 4 http://$($t.Ip):$($t.Port)/ 2>/dev/null | head -n 1" }
        "if timeout 4 bash -c 'exec 3<>/dev/tcp/$($t.Ip)/$($t.Port)' 2>/dev/null; then r=OPEN; else r=BLOCKED; fi; " +
        "body=`$($answer); echo `"PROBE|$($t.Name)|$($t.Ip)|$($t.Port)|`$r|`$body`""
    }
    $out = Invoke-L05Guest -ResourceGroup $ResourceGroup -VmName $FromVm -Script ($lines -join "`n")
    foreach ($line in ($out -split "`n")) {
        if ($line -match '^PROBE\|([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)\|(.*)$') {
            [pscustomobject]@{ From = $FromVm; To = $Matches[1]; Ip = $Matches[2]; Port = [int]$Matches[3]; Result = $Matches[4]; Answer = $Matches[5].Trim() }
        }
    }
}

function Get-L05FlowTuples {
    <#
    .SYNOPSIS Reads the newest VNet flow-log blobs for one VNet and returns flows to a port.
    .DESCRIPTION Flow logs land in insights-logs-flowlogflowevent as one block blob per NIC per
             hour, appended every minute. Reading the blob directly shows each flow's rule name
             and state within a couple of minutes; traffic analytics takes longer. Access uses
             Microsoft Entra ID (the operator holds Storage Blob Data Reader), never a key.
    .PARAMETER Hours How many hourly blobs back to read.
    #>
    param(
        [Parameter(Mandatory)][string]$VnetName,
        [Parameter(Mandatory)][int]$DestinationPort,
        [int]$Hours = 2,
        [string]$EvidenceName = 'flowlogs'
    )
    $lab = Get-L05Outputs
    $flowLogName = ('fl-' + $VnetName).ToUpperInvariant()
    $container = 'insights-logs-flowlogflowevent'
    $blobs = @(Invoke-L05Az -NoSubscription @('storage', 'blob', 'list', '--account-name', $lab.flowStoreName, '--container-name', $container,
            '--auth-mode', 'login', '--prefix', 'flowLogResourceID=/', '--num-results', '5000',
            # Blob paths join the watcher and flow-log names: .../NETWORKWATCHER_EASTUS2_FL-VNET-.../y=...
            '--query', "[?contains(name, '_$flowLogName/')].{name:name, modified:properties.lastModified}"))
    $cutoff = [DateTime]::UtcNow.AddHours(-$Hours)
    # ConvertFrom-Json turns the timestamp into local time; compare in UTC or the cutoff is off
    # by the workstation's offset.
    $recent = @($blobs | Where-Object { ([DateTime]$_.modified).ToUniversalTime() -gt $cutoff } | Sort-Object { ([DateTime]$_.modified).ToUniversalTime() } -Descending)
    $temp = Join-Path ([IO.Path]::GetTempPath()) ('sc500-l05-flow-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($temp)
    try {
        $rows = foreach ($b in $recent) {
            $file = Join-Path $temp (([guid]::NewGuid().ToString('N')) + '.json')
            [void](Invoke-L05Az -NoSubscription -Raw @('storage', 'blob', 'download', '--account-name', $lab.flowStoreName, '--container-name', $container,
                    '--auth-mode', 'login', '--name', $b.name, '--file', $file))
            $doc = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -Depth 50
            foreach ($rec in $doc.records) {
                foreach ($f in $rec.flowRecords.flows) {
                    foreach ($g in $f.flowGroups) {
                        foreach ($t in $g.flowTuples) {
                            $x = $t -split ','
                            if ([int]$x[4] -ne $DestinationPort) { continue }
                            [pscustomobject]@{
                                TimeUtc   = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$x[0]).UtcDateTime.ToString('HH:mm:ss')
                                Source    = $x[1]; Destination = $x[2]; Port = [int]$x[4]
                                Direction = if ($x[6] -eq 'I') { 'In' } else { 'Out' }
                                State     = switch ($x[7]) { 'D' { 'Denied' } 'B' { 'Allowed (begin)' } 'E' { 'Allowed (end)' } 'C' { 'Allowed (continuing)' } default { $x[7] } }
                                Rule      = $g.rule
                                AclId     = $f.aclID
                                # The raw record, kept in the evidence file so a slide or an
                                # auditor can quote the exact tuple rather than our parse of it.
                                Tuple     = $t
                            }
                        }
                    }
                }
            }
        }
    }
    finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
    # Keep the destination side's view: inbound records at the target NIC carry the decision of
    # the NSG or admin rule protecting it. The source NIC logs the same flow as outbound, which
    # only tells you the sender was allowed to send. The same tuple can repeat when a blob is
    # re-read, so de-duplicate.
    $rows = @($rows | Where-Object Direction -eq 'In' |
            Sort-Object TimeUtc, Source, Destination, Port, State, Rule -Unique |
            Sort-Object TimeUtc -Descending | Select-Object -First 20)
    [void](Write-L05Evidence $EvidenceName $rows)
    if (-not $rows.Count) { "No flows to port $DestinationPort in the last $Hours hour(s) yet. Flow logs arrive about a minute after the traffic; run the probe, wait, and read again." }
    else { $rows | Select-Object TimeUtc, Source, Destination, Port, Direction, State, Rule | Format-Table -AutoSize | Out-String -Width 220 }
}
