<#
.SYNOPSIS
    Shared helpers for the SC-500 Lesson 6 lab: pin the subscription, call Azure CLI safely,
    save private evidence, read deployment outputs, and run DNS and blob tests inside VMs.
.DESCRIPTION
    Dot-source this file from the other Lesson 6 scripts. Same design as Lesson 5's
    L05.Common.ps1. No VM has an SSH private key anyone keeps, so every in-guest test goes
    through Azure Run Command. Blob reads use Microsoft Entra ID (the operator's sign-in on the
    workstation, a managed identity inside a VM), never an account key: the records account has
    Shared Key disabled. Nothing here prints a token or a password.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:L06Lab = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:L06Config = Get-Content (Join-Path $script:L06Lab 'infra/lesson-06/config.json') -Raw | ConvertFrom-Json
# Every Azure resource name comes from config.json names and naming (Cloud Adoption Framework naming guidance, https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming: the Cloud Adoption
# Framework, applied to Contoso). No script spells a resource name itself, so a rename is one edit in one file.
$script:L06Names = $script:L06Config.names
function Get-L06NatName([string]$Workload) {
    # The maintenance NAT gateway for one workload VNet, named the way maintenance-egress.bicep names it.
    $n = $script:L06Config.naming
    return "ng-$Workload-$($n.env)-$($n.region)-$($n.instance)"
}
$script:L06State = Join-Path $script:L06Lab '.azure/lesson-06'
$script:L06Evidence = Join-Path $script:L06State 'evidence'

# Call the CLI's own Python instead of az.cmd. az.cmd is a batch file, and cmd.exe mangles
# arguments that contain &, %, or quotes, which in-guest bash scripts are full of.
$script:L06Python = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe'
if (-not (Test-Path -LiteralPath $script:L06Python)) { throw "Azure CLI Python not found at $script:L06Python. Install Azure CLI 2.85 or later." }

function Invoke-L06Az {
    <#
    .SYNOPSIS Runs one Azure CLI command pinned to the lesson subscription.
    .PARAMETER Arguments The CLI arguments, one element per token.
    .PARAMETER Raw Return stdout as text instead of parsed JSON.
    .PARAMETER AllowFailure Return exit code, stdout, and stderr instead of throwing.
    .PARAMETER NoSubscription Omit --subscription (Graph and data-plane commands reject it).
    #>
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$Raw,
        [switch]$AllowFailure,
        [switch]$NoSubscription
    )
    $start = [Diagnostics.ProcessStartInfo]::new($script:L06Python)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $all = @('-Im', 'azure.cli') + $Arguments + @('--only-show-errors')
    if (-not $NoSubscription) { $all += @('--subscription', $script:L06Config.subscriptionId) }
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

function Assert-L06Context {
    # Refuse to run against any subscription or tenant but the course's.
    $account = Invoke-L06Az @('account', 'show')
    if ($account.id -ne $script:L06Config.subscriptionId -or $account.tenantId -ne $script:L06Config.tenantId) {
        throw 'The signed-in Azure CLI context is not the course subscription and tenant.'
    }
    Write-Host "Lesson 6: $($account.name), signed in as $($account.user.name)."
    return $account
}

function Write-L06Evidence {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)]$Value)
    [void][IO.Directory]::CreateDirectory($script:L06Evidence)
    $file = Join-Path $script:L06Evidence ('{0}-{1}.json' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'), $Name)
    $Value | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $file -Encoding utf8
    return $file
}

function Get-L06Outputs {
    # Read names from the deployment record in ARM, not a local file, so a stale copy can't
    # point a demo at the wrong resource.
    param([ValidateSet('Private', 'Pls', 'Dns', 'Connector')][string]$Lab = 'Private')
    $name = switch ($Lab) {
        'Private' { $script:L06Config.deploymentName }
        'Pls' { $script:L06Config.plsDeploymentName }
        'Dns' { $script:L06Config.dnsDeploymentName }
        'Connector' { $script:L06Config.connectorDeploymentName }
    }
    $d = Invoke-L06Az -AllowFailure @('deployment', 'sub', 'show', '--name', $name)
    if ($d.ExitCode -ne 0) { throw "No $Lab deployment named $name. Deploy it first." }
    $d = $d.Stdout | ConvertFrom-Json -Depth 100
    if ($d.properties.provisioningState -ne 'Succeeded') { throw "The $Lab deployment is $($d.properties.provisioningState), not Succeeded." }
    return $d.properties.outputs.lab.value
}

function Get-L06Value {
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

function New-L06SshPublicKey {
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
        $publicKey = 'ssh-rsa ' + [Convert]::ToBase64String($stream.ToArray()) + ' sc500-l06-run-command-only'
        $stream.Dispose()
        return $publicKey
    }
    finally { $rsa.Dispose() }
}

function Get-L06SshPublicKey {
    # One public key and one image version per lesson, saved on first use and reused, because
    # Azure refuses to change either on an existing VM.
    [void][IO.Directory]::CreateDirectory($script:L06State)
    $keyPath = Join-Path $script:L06State 'ssh-public-key.txt'
    if (-not (Test-Path -LiteralPath $keyPath)) { New-L06SshPublicKey | Set-Content -LiteralPath $keyPath -Encoding ascii }
    return (Get-Content -LiteralPath $keyPath -Raw).Trim()
}

function Get-L06ImageVersion {
    $imagePath = Join-Path $script:L06State 'image-version.txt'
    if (-not (Test-Path -LiteralPath $imagePath)) {
        [void][IO.Directory]::CreateDirectory($script:L06State)
        $image = Invoke-L06Az @('vm', 'image', 'show', '--urn', 'Canonical:ubuntu-24_04-lts:server:latest', '--location', $script:L06Config.location)
        $image.name | Set-Content -LiteralPath $imagePath -Encoding ascii
    }
    return (Get-Content -LiteralPath $imagePath -Raw).Trim()
}

function Assert-L06GuestReady {
    <# .SYNOPSIS Rejects agent-backed work while a VM or extension is unhealthy or busy. #>
    param([Parameter(Mandatory)][string]$ResourceGroup,[Parameter(Mandatory)][string]$VmName)
    # Failed extensions can retry and serialize unrelated commands behind a long timeout.
    $vm = Invoke-L06Az @('vm','get-instance-view','--resource-group',$ResourceGroup,'--name',$VmName)
    $view = $vm.instanceView
    $codes = @($view.statuses | ForEach-Object code)
    if ('PowerState/running' -notin $codes -or 'ProvisioningState/succeeded' -notin $codes) { throw "$VmName is not running and provisioned. Wait for startup; no command was queued." }
    $agentCodes = @(Get-L06Value $view 'vmAgent.statuses' | ForEach-Object code)
    if ('ProvisioningState/succeeded' -notin $agentCodes) { throw "$VmName agent is not ready; no command was queued." }
    $bad = @(Invoke-L06Az @('vm','extension','list','--resource-group',$ResourceGroup,'--vm-name',$VmName) | Where-Object provisioningState -ne 'Succeeded')
    if ($bad.Count) { throw "$VmName has unhealthy/busy extensions: $($bad.name -join ', '). Enable maintenance egress and let them finish; no command was queued." }
}

function Invoke-L06Guest {
    <#
    .SYNOPSIS Runs a bash script inside a lab VM with Run Command and returns its stdout.
    .DESCRIPTION Run Command travels through the Azure control plane and the VM agent, not the
             network paths the lesson tests, so it can't be confused with a test result. The
             readiness preflight prevents queuing behind a failed or updating extension.
    #>
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(Mandatory)][string]$Script
    )
    Assert-L06GuestReady -ResourceGroup $ResourceGroup -VmName $VmName
    $r = Invoke-L06Az @('vm', 'run-command', 'invoke', '--resource-group', $ResourceGroup, '--name', $VmName,
        '--command-id', 'RunShellScript', '--scripts', $Script)
    $message = [string]$r.value[0].message
    # The message is "Enable succeeded: \n[stdout]\n...\n[stderr]\n...". Keep stdout only.
    if ($message -match '(?s)\[stdout\]\s*(.*?)\s*\[stderr\]') { return $Matches[1].Trim() }
    return $message.Trim()
}

function Get-L06GuestBlobScript {
    <#
    .SYNOPSIS Builds the bash that reads the synthetic record from inside a VM with its managed
             identity, optionally forcing the IP the client connects to.
    .DESCRIPTION The token comes from the VM's instance metadata endpoint and is used only inside
             the VM; it never crosses Run Command's output. The script prints one BLOB| line:
             HTTP status, the service's x-ms-error-code (if any), and the record's first line.
    .PARAMETER ConnectIp When set, curl --resolve pins the TCP connection to this address. The
             hybrid DNS demo uses it to connect exactly where the field-office DNS answered.
    .PARAMETER ClientId The user-assigned identity's client ID; empty for a system-assigned one.
    #>
    param(
        [Parameter(Mandatory)][string]$BlobHost,
        [Parameter(Mandatory)][string]$Container,
        [Parameter(Mandatory)][string]$Blob,
        [string]$ConnectIp = '',
        [string]$ClientId = ''
    )
    $idArg = if ($ClientId) { "&client_id=$ClientId" } else { '' }
    $resolve = if ($ConnectIp) { "--resolve ${BlobHost}:443:$ConnectIp" } else { '' }
    @"
tok=`$(curl -s -H Metadata:true 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F$idArg' | python3 -c 'import sys,json; print(json.load(sys.stdin).get("access_token",""))')
if [ -z "`$tok" ]; then echo 'BLOB|0|NoManagedIdentityToken|'; exit 0; fi
code=`$(curl -s -m 10 $resolve -o /tmp/l06-blob.out -D /tmp/l06-blob.hdr -w '%{http_code}' -H "Authorization: Bearer `$tok" -H 'x-ms-version: 2023-11-03' 'https://$BlobHost/$Container/$Blob')
err=`$(grep -i '^x-ms-error-code:' /tmp/l06-blob.hdr 2>/dev/null | cut -d' ' -f2 | tr -d '\r')
first=`$(head -c 160 /tmp/l06-blob.out 2>/dev/null | tr -d '\n\r')
echo "BLOB|`$code|`$err|`$first"
rm -f /tmp/l06-blob.out /tmp/l06-blob.hdr
"@
}

function ConvertFrom-L06BlobLine {
    param([Parameter(Mandatory)][string]$Output, [Parameter(Mandatory)][string]$From)
    foreach ($line in ($Output -split "`n")) {
        if ($line -match '^BLOB\|([^|]*)\|([^|]*)\|(.*)$') {
            $status, $code, $body = [int]$Matches[1], $Matches[2], $Matches[3].Trim()
            # On a denial the body is the service's XML error; show its <Message> sentence (the
            # same text the workstation read shows) instead of raw XML.
            if ($body -match '<Message>([^<]+?)(RequestId:|<)') { $body = $Matches[1].Trim() }
            return [pscustomobject]@{ From = $From; HttpStatus = $status; ErrorCode = $code; Content = $body }
        }
    }
    return [pscustomobject]@{ From = $From; HttpStatus = 0; ErrorCode = 'NoResult'; Content = $Output }
}

function Resolve-L06Name {
    <#
    .SYNOPSIS Resolves a name on the workstation (public DNS) and returns the CNAME chain and
             addresses, so the demo can show the privatelink hop public DNS adds.
    #>
    param([Parameter(Mandatory)][string]$Name)
    $answers = @(Resolve-DnsName -Name $Name -Type A -DnsOnly -ErrorAction Stop)
    [pscustomobject]@{
        Name    = $Name
        Chain   = @($answers | Where-Object QueryType -eq 'CNAME' | ForEach-Object { $_.NameHost })
        Address = @($answers | Where-Object QueryType -eq 'A' | ForEach-Object { $_.IPAddress })
    }
}
