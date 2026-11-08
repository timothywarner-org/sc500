<#
.SYNOPSIS
    Shared helpers for the SC-500 Lesson 8 lab: pin the subscription, call Azure CLI safely,
    save private evidence, read deployment outputs, call ARM and Resource Graph, read each VM's
    own evidence from its serial log, and probe a TCP port without signing in.
.DESCRIPTION
    Dot-source this file from the other Lesson 8 scripts. Same design as L07.Common.ps1.
    Nothing here prints a token, a password, or a private key. The lab admin key's private half
    is written once to your local app data (not the repo, not a synced folder) because Bastion's
    portal connection asks for it; no script reads it back.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:L08Lab = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:L08Config = Get-Content (Join-Path $script:L08Lab 'infra/lesson-08/config.json') -Raw | ConvertFrom-Json
# State is kept per subscription, as Lesson 7 does, so an earlier build's public key and image pin
# (still in .azure/lesson-08) can't leak into the lab subscription build.
$script:L08State = Join-Path $script:L08Lab ".azure/lesson-08/$($script:L08Config.subscriptionId)"
$script:L08Evidence = Join-Path $script:L08State 'evidence'
$script:L08KeyDir = Join-Path $env:USERPROFILE 'SC500-keys\lesson-08'

# Call the CLI's own Python instead of az.cmd. az.cmd is a batch file, and cmd.exe mangles
# arguments that contain &, %, |, or quotes, which JMESPath and KQL are full of.
$script:L08Python = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe'
if (-not (Test-Path -LiteralPath $script:L08Python)) { throw "Azure CLI Python not found at $script:L08Python. Install Azure CLI 2.85 or later." }

function Invoke-L08Az {
    <#
    .SYNOPSIS Runs one Azure CLI command pinned to the lesson subscription.
    .PARAMETER Arguments The CLI arguments, one element per token.
    .PARAMETER Raw Return stdout as text instead of parsed JSON.
    .PARAMETER AllowFailure Return exit code, stdout, and stderr instead of throwing.
    .PARAMETER NoSubscription Omit --subscription (az rest and Graph commands reject it).
    #>
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$Raw,
        [switch]$AllowFailure,
        [switch]$NoSubscription
    )
    $start = [Diagnostics.ProcessStartInfo]::new($script:L08Python)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $all = @('-Im', 'azure.cli') + $Arguments + @('--only-show-errors')
    if (-not $NoSubscription) { $all += @('--subscription', $script:L08Config.subscriptionId) }
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

function Assert-L08Context {
    # Refuse to run against any subscription or tenant but the course's.
    $account = Invoke-L08Az @('account', 'show')
    if ($account.id -ne $script:L08Config.subscriptionId -or $account.tenantId -ne $script:L08Config.tenantId) {
        throw 'The signed-in Azure CLI context is not the course subscription and tenant.'
    }
    Write-Host "Lesson 8: $($account.name), signed in as $($account.user.name)."
    return $account
}

function Write-L08Evidence {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)]$Value)
    [void][IO.Directory]::CreateDirectory($script:L08Evidence)
    $file = Join-Path $script:L08Evidence ('{0}-{1}.json' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'), $Name)
    $Value | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $file -Encoding utf8
    return $file
}

function Get-L08Value {
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

function Invoke-L08Arm {
    <#
    .SYNOPSIS Calls an ARM path (starting with /subscriptions or /providers) through az rest.
    .PARAMETER Body An object; sent as compact JSON.
    .PARAMETER AllowNotFound Return $null on 404 instead of throwing.
    #>
    param(
        [ValidateSet('get', 'put', 'post', 'delete', 'patch')][string]$Method = 'get',
        [Parameter(Mandatory)][string]$Path,
        $Body,
        [switch]$AllowNotFound
    )
    $cli = @('rest', '--method', $Method, '--url', "https://management.azure.com$Path")
    if ($null -ne $Body) { $cli += @('--headers', 'Content-Type=application/json', '--body', ($Body | ConvertTo-Json -Depth 30 -Compress)) }
    $r = Invoke-L08Az -NoSubscription -AllowFailure $cli
    if ($r.ExitCode -ne 0) {
        if ($AllowNotFound -and $r.Stderr -match '(Not Found|NotFound|ResourceNotFound|404)') { return $null }
        throw "ARM $Method $Path failed: $($r.Stderr.Trim())"
    }
    if ([string]::IsNullOrWhiteSpace($r.Stdout)) { return $null }
    return $r.Stdout | ConvertFrom-Json -Depth 100
}

function Invoke-L08Graph {
    <# .SYNOPSIS Runs an Azure Resource Graph query over the lesson subscription; returns rows. #>
    param([Parameter(Mandatory)][string]$Query)
    $body = @{ subscriptions = @($script:L08Config.subscriptionId); query = $Query; options = @{ resultFormat = 'objectArray' } }
    $r = Invoke-L08Arm -Method post -Path '/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' -Body $body
    return @($r.data)
}

function Get-L08Outputs {
    # Read names from the deployment record in ARM, not a local file, so a stale copy can't point
    # a demo at the wrong resource.
    param([ValidateSet('Retained', 'Legacy')][string]$Lab = 'Retained')
    $cfg = $script:L08Config
    $d = if ($Lab -eq 'Retained') { Invoke-L08Az -AllowFailure @('deployment', 'sub', 'show', '--name', $cfg.deploymentName) }
         else { Invoke-L08Az -AllowFailure @('deployment', 'group', 'show', '--resource-group', $cfg.resourceGroup, '--name', $cfg.legacyDeploymentName) }
    if ($d.ExitCode -ne 0) { throw "No $Lab deployment found. Deploy it first." }
    $d = $d.Stdout | ConvertFrom-Json -Depth 100
    if ($d.properties.provisioningState -ne 'Succeeded') { throw "The $Lab deployment is $($d.properties.provisioningState), not Succeeded." }
    if ($Lab -eq 'Retained') { return $d.properties.outputs.lab.value }
    return $d.properties.outputs
}

function Get-L08OperatorIp {
    # The legacy VM's standing SSH rule and JIT requests name the operator's current public IP.
    return (Invoke-RestMethod -Uri 'https://api.ipify.org?format=json' -TimeoutSec 15).ip
}

function Get-L08AdminPublicKey {
    <#
    .SYNOPSIS Returns the lab admin's SSH public key, creating the key pair on first use.
    .DESCRIPTION Bastion's portal connection asks for the private key file, so this lesson keeps
             one: an RSA 3072 key in PEM form at %LOCALAPPDATA%\SC500\lesson-08, which inherits
             the user profile's permissions. It's never printed and never read back by a script.
             The public half is saved beside the lab state and reused, because Azure won't change
             the key on an existing VM.
    #>
    [void][IO.Directory]::CreateDirectory($script:L08State)
    $pubPath = Join-Path $script:L08State 'ssh-public-key.txt'
    $keyPath = Join-Path $script:L08KeyDir 'contosoadmin-bastion.pem'
    if (-not (Test-Path -LiteralPath $pubPath)) {
        if (Test-Path -LiteralPath $keyPath) { throw "A private key exists at $keyPath but its public half is missing. Restore ssh-public-key.txt or move the key aside." }
        [void][IO.Directory]::CreateDirectory($script:L08KeyDir)
        $rsa = [Security.Cryptography.RSA]::Create(3072)
        try {
            [IO.File]::WriteAllText($keyPath, $rsa.ExportRSAPrivateKeyPem() + "`n", [Text.Encoding]::ASCII)
            $key = $rsa.ExportParameters($false)
            $stream = [IO.MemoryStream]::new()
            foreach ($part in @([Text.Encoding]::ASCII.GetBytes('ssh-rsa'), $key.Exponent, ([byte[]]@(0) + $key.Modulus))) {
                $bytes = [byte[]]$part; $length = [BitConverter]::GetBytes([uint32]$bytes.Length); [Array]::Reverse($length)
                $stream.Write($length); $stream.Write($bytes)
            }
            ('ssh-rsa ' + [Convert]::ToBase64String($stream.ToArray()) + ' contosoadmin-l08-bastion') | Set-Content -LiteralPath $pubPath -Encoding ascii
            $stream.Dispose()
        }
        finally { $rsa.Dispose() }
    }
    # A retained public key cannot restore a missing private key. Packaged desktop apps can
    # virtualize AppData, so fail before promising that another Windows process can sign in.
    if (-not (Test-Path -LiteralPath $keyPath -PathType Leaf)) {
        throw "The public key exists, but the Bastion private key is missing at $keyPath. Recover the matching key before deploying; do not silently generate a replacement. See infra/lesson-08/README.md."
    }
    return (Get-Content -LiteralPath $pubPath -Raw).Trim()
}

function Get-L08AdminKeyPath { return (Join-Path $script:L08KeyDir 'contosoadmin-bastion.pem') }

function Set-L08DiskTags {
    <#
    .SYNOPSIS Copies each named VM's tags onto its OS disk, incrementally.
    .DESCRIPTION An OS disk created from a VM's storage profile doesn't inherit the VM's tags, and a
             template can't tag it. Lesson 7 does the same, so every resource in the group answers
             to the same workload, env and owner tags (Test-L08Lab.ps1 checks this).
    #>
    param([Parameter(Mandatory)][string[]]$VmName)
    foreach ($name in $VmName) {
        $vm = Invoke-L08Az @('vm', 'show', '--resource-group', $script:L08Config.resourceGroup, '--name', $name)
        $pairs = @($vm.tags.PSObject.Properties | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value })
        [void](Invoke-L08Az (@('resource', 'tag', '--is-incremental', '--ids', $vm.storageProfile.osDisk.managedDisk.id, '--tags') + $pairs))
        Write-Host "Tagged $($vm.storageProfile.osDisk.name) with $name's tags."
    }
}

function Get-L08TagSet {
    <#
    .SYNOPSIS Returns the common tags from config.json plus a workload and env, as an ordered hashtable.
    .DESCRIPTION CAF's functional tags (workload, env, region) sit beside the course's own (managedby,
             lesson, scenario, lifecycle). Keys are lowercase, as CAF recommends; Azure treats tag
             keys case-insensitively, so scripts that read tags.managedBy still match.
    #>
    param([Parameter(Mandatory)][string]$Workload, [Parameter(Mandatory)][string]$Env, [hashtable]$Extra = @{})
    $t = [ordered]@{}
    foreach ($p in $script:L08Config.tags.PSObject.Properties) { $t[$p.Name] = "$($p.Value)" }
    $t['workload'] = $Workload; $t['env'] = $Env
    foreach ($k in $Extra.Keys) { $t[$k] = "$($Extra[$k])" }
    return $t
}

function Test-L08Preflight {
    <#
    .SYNOPSIS Read-only checks that stop a deployment before ARM does: the group's owner, VM size
             restrictions, family and regional vCPU quota, the EncryptionAtHost feature, Defender
             for Servers Plan 2, the budget API, and same-named resources in other groups.
    .DESCRIPTION Same design as Test-L07Preflight (docs/CONTOSO-AZURE-DEPLOYMENT.md, step 2).
             Returns rows with Result PASS, WARN or FAIL in words; throws when any row is FAIL.
    #>
    param([int]$VcpusNeeded = $script:L08Config.vcpusNeeded)
    $cfg = $script:L08Config
    $rows = [Collections.Generic.List[object]]::new()
    function Add-Row([string]$Result, [string]$Check, [string]$Detail) { $rows.Add([pscustomobject]@{ Result = $Result; Check = $Check; Detail = $Detail }) }

    # 1. The resource group is absent, or this lesson's.
    if (Invoke-L08Az @('group', 'exists', '--name', $cfg.resourceGroup)) {
        $owner = "$(Get-L08Value (Invoke-L08Az @('group', 'show', '--name', $cfg.resourceGroup)) 'tags.managedby')"
        Add-Row $(if ($owner -eq $cfg.managedBy) { 'PASS' } else { 'FAIL' }) 'Resource group owner' "$($cfg.resourceGroup) exists, tagged managedby='$owner'"
    }
    else { Add-Row 'PASS' 'Resource group owner' "$($cfg.resourceGroup) doesn't exist yet" }

    # 2. Each VM size is offered and not restricted for this subscription in the region.
    foreach ($size in @($cfg.vmSizes.PSObject.Properties.Value | Sort-Object -Unique)) {
        $sku = @(Invoke-L08Az @('vm', 'list-skus', '--location', $cfg.location, '--size', $size, '--resource-type', 'virtualMachines')) | Where-Object name -eq $size
        if (-not $sku) { Add-Row 'FAIL' "VM size $size" "not offered in $($cfg.location)"; continue }
        $blocked = @($sku[0].restrictions | Where-Object type -eq 'Location')
        Add-Row $(if ($blocked.Count) { 'FAIL' } else { 'PASS' }) "VM size $size" $(if ($blocked.Count) { "restricted: $(@($blocked | ForEach-Object reasonCode) -join ', ')" } else { "available in $($cfg.location)" })
    }

    # 3. The lab's vCPUs fit the family and regional quota (deallocated VMs still count).
    $usage = @(Invoke-L08Az @('vm', 'list-usage', '--location', $cfg.location))
    foreach ($q in @($cfg.vmFamily, 'cores')) {
        $u = @($usage | Where-Object { $_.name.value -eq $q })
        if (-not $u) { Add-Row 'WARN' "Quota $q" 'not reported'; continue }
        $free = [int]$u[0].limit - [int]$u[0].currentValue
        Add-Row $(if ($free -ge $VcpusNeeded) { 'PASS' } else { 'FAIL' }) "Quota $q" "$($u[0].currentValue) of $($u[0].limit) used, $VcpusNeeded needed"
    }

    # 4. Encryption at host needs the feature registered (a subscription change this lab doesn't make).
    $feature = Invoke-L08Az @('feature', 'show', '--namespace', 'Microsoft.Compute', '--name', 'EncryptionAtHost')
    Add-Row $(if ($feature.properties.state -eq 'Registered') { 'PASS' } else { 'FAIL' }) 'EncryptionAtHost feature' "$($feature.properties.state)"

    # 5. JIT and agentless scanning need Plan 2. Set-L08DefenderWindow.ps1 -State Open turns it on.
    $plan = Invoke-L08Arm -Path "/subscriptions/$($cfg.subscriptionId)/providers/Microsoft.Security/pricings/VirtualMachines?api-version=2024-01-01"
    $p2 = (Get-L08Value $plan 'properties.pricingTier') -eq 'Standard' -and (Get-L08Value $plan 'properties.subPlan') -eq 'P2'
    Add-Row $(if ($p2) { 'PASS' } else { 'FAIL' }) 'Defender for Servers Plan 2' $(if ($p2) { 'on for the subscription' } else { 'off: run Set-L08DefenderWindow.ps1 -State Open first' })

    # 6. Budgets are supported for this subscription's offer (a list call fails when they aren't).
    if ($cfg.budget.enabled) {
        $b = Invoke-L08Az -AllowFailure @('consumption', 'budget', 'list')
        Add-Row $(if ($b.ExitCode -eq 0) { 'PASS' } else { 'FAIL' }) 'Cost budgets' $(if ($b.ExitCode -eq 0) { 'the Consumption API answers' } else { 'the Consumption API refused; set budget.enabled to false and say why in the README' })
    }

    # 7. Another lesson's lab may hold same-named resources in its own group. Azure allows that, but
    #    a portal picker would show both, so the demo opens resources by full resource ID.
    $wanted = @($cfg.names.PSObject.Properties | ForEach-Object { "$($_.Value)" })
    #    Resource Graph, not az resource list: CLI 2.85.0's list returned [] on November 1, 2026 while ARM listed 21.
    $clash = @(Invoke-L08Graph -Query 'resources | project name, group = resourceGroup' | Where-Object { $wanted -contains $_.name -and $_.group -ne $cfg.resourceGroup })
    Add-Row $(if ($clash.Count) { 'WARN' } else { 'PASS' }) 'Same names in other groups' $(if ($clash.Count) { @($clash | ForEach-Object { "$($_.name) in $($_.group)" }) -join '; ' } else { 'none' })

    [void](Write-L08Evidence 'preflight' $rows)
    $rows | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Out-Host
    if (@($rows | Where-Object Result -eq 'FAIL').Count) { throw 'Preflight FAILED. Nothing was validated or deployed.' }
    return $rows
}

function Get-L08ImageVersion {
    $imagePath = Join-Path $script:L08State 'image-version.txt'
    if (-not (Test-Path -LiteralPath $imagePath)) {
        [void][IO.Directory]::CreateDirectory($script:L08State)
        $image = Invoke-L08Az @('vm', 'image', 'show', '--urn', 'Canonical:ubuntu-24_04-lts:server:latest', '--location', $script:L08Config.location)
        $image.name | Set-Content -LiteralPath $imagePath -Encoding ascii
    }
    return (Get-Content -LiteralPath $imagePath -Raw).Trim()
}

function Get-L08BootLog {
    <#
    .SYNOPSIS Returns the lines of a VM's serial log that start with a prefix, newest boot last.
    .DESCRIPTION The lab VMs print their own evidence to the serial console, and managed boot
             diagnostics hands the log back without SSH, Run Command, or a guest agent. That's
             the only way to read the datacenter server (vm-datacenter-prod-001) once its guest agent is off.
    #>
    param([Parameter(Mandatory)][string]$VmName, [Parameter(Mandatory)][string]$Prefix)
    # The command streams the log itself; tsv keeps a table default in the user's az config from
    # rejecting it.
    $text = Invoke-L08Az -Raw @('vm', 'boot-diagnostics', 'get-boot-log', '--resource-group', $script:L08Config.resourceGroup, '--name', $VmName, '--output', 'tsv')
    # The CLI prints the log as a Python bytes literal (b'...\r\n...'), escapes and all. Undo the
    # literal, turn escaped line breaks back into lines, and drop color codes and raw bytes.
    if ($text.StartsWith("b'") -or $text.StartsWith('b"')) { $text = $text.Substring(2, $text.Length - 3) }
    $text = $text -replace '\\r\\n', "`n" -replace '\\n', "`n" -replace '\\r', '' -replace '\\x1b\[[0-9;]*[A-Za-z]', '' -replace '\\x[0-9a-f]{2}', ''
    $hits = @(($text -split "`r?`n") | ForEach-Object { $_ -replace '\x1b\[[0-9;]*[A-Za-z]', '' } | Where-Object { $_ -cmatch [regex]::Escape($Prefix) } | ForEach-Object { $_.Substring($_.IndexOf($Prefix)).Trim() })
    # cloud-init echoes a script's output to the console too, so drop a line that repeats the one before it.
    $out = [Collections.Generic.List[string]]::new()
    foreach ($h in $hits) { if ($out.Count -eq 0 -or $out[$out.Count - 1] -ne $h) { $out.Add($h) } }
    return , $out.ToArray()
}

function Test-L08Tcp {
    <#
    .SYNOPSIS Opens a TCP connection and reads the first line the server sends (an SSH banner),
             without authenticating. Returns Open with the banner, or Closed with the reason.
    #>
    param([Parameter(Mandatory)][string]$Address, [int]$Port = 22, [int]$TimeoutMs = 8000)
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $task = $client.ConnectAsync($Address, $Port)
        if (-not $task.Wait($TimeoutMs)) { return [pscustomobject]@{ Result = 'Closed'; Detail = "timed out after $($TimeoutMs / 1000) s" } }
        $stream = $client.GetStream(); $stream.ReadTimeout = $TimeoutMs
        $buffer = [byte[]]::new(256)
        $n = $stream.Read($buffer, 0, $buffer.Length)
        $banner = ([Text.Encoding]::ASCII.GetString($buffer, 0, $n) -split "`r?`n")[0]
        return [pscustomobject]@{ Result = 'Open'; Detail = $banner }
    }
    catch {
        $e = $_.Exception; if ($e.InnerException) { $e = $e.InnerException }
        return [pscustomobject]@{ Result = 'Closed'; Detail = $e.Message }
    }
    finally { $client.Dispose() }
}

function Get-L08VmId([string]$Name) {
    return "/subscriptions/$($script:L08Config.subscriptionId)/resourceGroups/$($script:L08Config.resourceGroup)/providers/Microsoft.Compute/virtualMachines/$Name"
}

function Get-L08JitPath {
    # One JIT policy for the lesson, in the lab resource group.
    $cfg = $script:L08Config
    return "/subscriptions/$($cfg.subscriptionId)/resourceGroups/$($cfg.resourceGroup)/providers/Microsoft.Security/locations/$($cfg.location)/jitNetworkAccessPolicies/default"
}
