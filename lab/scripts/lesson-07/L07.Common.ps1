<#
.SYNOPSIS
    Shared helpers for the SC-500 Lesson 7 lab: pin the subscription, call Azure CLI safely,
    save private evidence, read deployment outputs, build the TLS inspection CA in memory,
    and read the lab's results through the firewall instead of through Run Command.
.DESCRIPTION
    Dot-source this file from the other Lesson 7 scripts. Same design as L06.Common.ps1.
    Every resource name comes from infra/lesson-07/config.json (Cloud Adoption Framework naming guidance, https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming),
    and private state lives under .azure/lesson-07/<subscription ID>/, so a lab rebuilt in a new
    subscription never reuses the old subscription's CA, key, or image pin.
    Nothing here prints a token, a password, or a private key. The inspection CA's private keys
    exist only in memory: the intermediate goes straight into Key Vault, and the root's private
    key is discarded as soon as it has signed the intermediate.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:L07Lab = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:L07Config = Get-Content (Join-Path $script:L07Lab 'infra/lesson-07/config.json') -Raw | ConvertFrom-Json
# State is per subscription: an earlier build left its public CA, SSH key and image pin
# in .azure/lesson-07 itself. A new subscription means a new vault and new VMs, so it must start
# from a fresh CA pair instead of trusting a root whose intermediate no longer exists anywhere.
$script:L07State = Join-Path $script:L07Lab (".azure/lesson-07/{0}" -f $script:L07Config.subscriptionId)
$script:L07Evidence = Join-Path $script:L07State 'evidence'

# Call the CLI's own Python instead of az.cmd. az.cmd is a batch file, and cmd.exe mangles
# arguments that contain &, %, |, or quotes, which KQL and JMESPath are full of.
$script:L07Python = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe'
if (-not (Test-Path -LiteralPath $script:L07Python)) { throw "Azure CLI Python not found at $script:L07Python. Install Azure CLI 2.85 or later." }

function Invoke-L07Az {
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
    $start = [Diagnostics.ProcessStartInfo]::new($script:L07Python)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $all = @('-Im', 'azure.cli') + $Arguments + @('--only-show-errors')
    if (-not $NoSubscription) { $all += @('--subscription', $script:L07Config.subscriptionId) }
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

function Assert-L07Context {
    # Refuse to run against any subscription or tenant but the course's.
    $account = Invoke-L07Az @('account', 'show')
    if ($account.id -ne $script:L07Config.subscriptionId -or $account.tenantId -ne $script:L07Config.tenantId) {
        throw 'The signed-in Azure CLI context is not the course subscription and tenant.'
    }
    Write-Host "Lesson 7: $($account.name), signed in as $($account.user.name)."
    return $account
}

function Write-L07Evidence {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)]$Value)
    [void][IO.Directory]::CreateDirectory($script:L07Evidence)
    $file = Join-Path $script:L07Evidence ('{0}-{1}.json' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'), $Name)
    $Value | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $file -Encoding utf8
    return $file
}

function Get-L07Firewall {
    <# .SYNOPSIS Read the lesson firewall; an API failure must never look like stopped billing. #>
    # Query the Network provider directly. ARM's generic resource inventory can lag creation.
    # Authentication/network errors must throw instead of masquerading as stopped billing.
    $cfg = $script:L07Config
    $uri = "https://management.azure.com/subscriptions/$($cfg.subscriptionId)/resourceGroups/$($cfg.resourceGroup)/providers/Microsoft.Network/azureFirewalls?api-version=2024-05-01"
    $items = @((Invoke-L07Az @('rest', '--method', 'get', '--url', $uri)).value)
    if ($items.Count -gt 1 -or ($items.Count -eq 1 -and $items[0].name -ne $cfg.names.firewall)) {
        throw 'Unexpected firewall resources in the lesson group; inspect billing and ownership.'
    }
    if ($items.Count -eq 0) { return $null }
    return $items[0]
}

function Get-L07DeploymentOutput {
    # Read names from the deployment record in ARM, not a local file, so a stale copy can't
    # point a demo at the wrong resource.
    param([ValidateSet('Retained', 'Policy', 'Firewall')][string]$Lab = 'Retained')
    $cfg = $script:L07Config
    $d = switch ($Lab) {
        'Retained' { Invoke-L07Az -AllowFailure @('deployment', 'sub', 'show', '--name', $cfg.deploymentName) }
        'Policy' { Invoke-L07Az -AllowFailure @('deployment', 'group', 'show', '--resource-group', $cfg.resourceGroup, '--name', $cfg.policyDeploymentName) }
        'Firewall' { Invoke-L07Az -AllowFailure @('deployment', 'group', 'show', '--resource-group', $cfg.resourceGroup, '--name', $cfg.firewallDeploymentName) }
    }
    if ($d.ExitCode -ne 0) { throw "No $Lab deployment found. Deploy it first." }
    $d = $d.Stdout | ConvertFrom-Json -Depth 100
    if ($d.properties.provisioningState -ne 'Succeeded') { throw "The $Lab deployment is $($d.properties.provisioningState), not Succeeded." }
    if ($Lab -eq 'Retained') { return $d.properties.outputs.lab.value }
    return $d.properties.outputs
}

function Get-L07Value {
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

function Get-L07OperatorIp {
    # The DNAT rule and the Key Vault firewall allow only the operator's current public address.
    return (Invoke-RestMethod -Uri 'https://api.ipify.org?format=json' -TimeoutSec 15).ip
}

function New-L07SshPublicKey {
    # Linux VMs need an SSH key, but nobody signs in to these fixtures. The private half is never
    # written anywhere and is discarded with the RSA object.
    $rsa = [Security.Cryptography.RSA]::Create(3072)
    try {
        $key = $rsa.ExportParameters($false)
        $stream = [IO.MemoryStream]::new()
        foreach ($part in @([Text.Encoding]::ASCII.GetBytes('ssh-rsa'), $key.Exponent, ([byte[]]@(0) + $key.Modulus))) {
            $bytes = [byte[]]$part; $length = [BitConverter]::GetBytes([uint32]$bytes.Length); [Array]::Reverse($length)
            $stream.Write($length); $stream.Write($bytes)
        }
        $publicKey = 'ssh-rsa ' + [Convert]::ToBase64String($stream.ToArray()) + ' contoso-lab-fixture-no-sign-in'
        $stream.Dispose()
        return $publicKey
    }
    finally { $rsa.Dispose() }
}

function Get-L07SshPublicKey {
    # One public key and one image version per lesson, saved on first use and reused, because
    # Azure refuses to change either on an existing VM.
    [void][IO.Directory]::CreateDirectory($script:L07State)
    $keyPath = Join-Path $script:L07State 'ssh-public-key.txt'
    if (-not (Test-Path -LiteralPath $keyPath)) { New-L07SshPublicKey | Set-Content -LiteralPath $keyPath -Encoding ascii }
    return (Get-Content -LiteralPath $keyPath -Raw).Trim()
}

function Get-L07ImageVersion {
    $imagePath = Join-Path $script:L07State 'image-version.txt'
    if (-not (Test-Path -LiteralPath $imagePath)) {
        [void][IO.Directory]::CreateDirectory($script:L07State)
        $image = Invoke-L07Az @('vm', 'image', 'show', '--urn', 'Canonical:ubuntu-24_04-lts:server:latest', '--location', $script:L07Config.location)
        $image.name | Set-Content -LiteralPath $imagePath -Encoding ascii
    }
    return (Get-Content -LiteralPath $imagePath -Raw).Trim()
}

function New-L07InspectionCa {
    <#
    .SYNOPSIS Builds the TLS inspection CA pair in memory: a self-signed lab root and an
             intermediate it signs, to Microsoft's stated requirements for Azure Firewall Premium.
    .DESCRIPTION Requirements (Azure Firewall Premium certificates, Microsoft Learn): RSA 4096,
             Basic Constraints critical with CA=TRUE and path length at least 1, Key Usage
             critical with KeyCertSign, valid at least a year forward, a single certificate (no
             chain), exportable, delivered as a password-less PFX.
             Returns the two PUBLIC certificates as PEM and the intermediate's PFX as base64.
             The root's private key is disposed before this function returns; nobody can issue
             from this root again. The caller must import the PFX and then drop it.
    #>
    $x = 'System.Security.Cryptography.X509Certificates'
    $now = [DateTimeOffset]::UtcNow
    $usage = [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]'KeyCertSign, CrlSign, DigitalSignature'
    $sha256 = [Security.Cryptography.HashAlgorithmName]::SHA256
    $pkcs1 = [Security.Cryptography.RSASignaturePadding]::Pkcs1
    $rootKey = [Security.Cryptography.RSA]::Create(4096)
    $interKey = [Security.Cryptography.RSA]::Create(4096)
    $root = $null; $inter = $null; $pfx = $null
    try {
        $rootReq = New-Object "$x.CertificateRequest" 'CN=Contoso Perimeter Lab Root CA, O=Contoso SC-500 lab fixture', $rootKey, $sha256, $pkcs1
        $rootReq.CertificateExtensions.Add((New-Object "$x.X509BasicConstraintsExtension" $true, $false, 0, $true))
        $rootReq.CertificateExtensions.Add((New-Object "$x.X509KeyUsageExtension" $usage, $true))
        $rootReq.CertificateExtensions.Add((New-Object "$x.X509SubjectKeyIdentifierExtension" $rootReq.PublicKey, $false))
        $root = $rootReq.CreateSelfSigned($now.AddDays(-1), $now.AddYears(3))

        $interReq = New-Object "$x.CertificateRequest" 'CN=Contoso Perimeter Inspection CA, O=Contoso SC-500 lab fixture', $interKey, $sha256, $pkcs1
        $interReq.CertificateExtensions.Add((New-Object "$x.X509BasicConstraintsExtension" $true, $true, 1, $true))
        $interReq.CertificateExtensions.Add((New-Object "$x.X509KeyUsageExtension" $usage, $true))
        $interReq.CertificateExtensions.Add((New-Object "$x.X509SubjectKeyIdentifierExtension" $interReq.PublicKey, $false))
        $interReq.CertificateExtensions.Add([System.Security.Cryptography.X509Certificates.X509AuthorityKeyIdentifierExtension]::CreateFromCertificate($root, $true, $false))
        $serial = [byte[]]::new(16); [Security.Cryptography.RandomNumberGenerator]::Fill($serial); $serial[0] = $serial[0] -band 0x7F
        $interPublic = $interReq.Create($root, $now.AddDays(-1), $now.AddYears(2), $serial)
        # Build the PFX by hand. X509Certificate2.Export on Windows stamps the key's storage
        # provider ("Microsoft Software Key Storage Provider") into the file, and Azure Firewall
        # rejects that: "RSA was encrypted using an unsupported Microsoft CSP". Pkcs12Builder
        # writes only the certificate, the PKCS#8 key, and the local key ID that pairs them,
        # sealed with an empty password, the same shape as Microsoft's openssl script. The key
        # bag uses the classic PKCS#12 3DES scheme, which every PFX reader accepts.
        Add-Type -AssemblyName System.Security.Cryptography.Pkcs
        $pkcs = 'System.Security.Cryptography.Pkcs'
        $sha1 = [Security.Cryptography.HashAlgorithmName]::SHA1
        $keyId = New-Object "$pkcs.Pkcs9LocalKeyId" (, [byte[]]$interPublic.GetCertHash())
        $certBags = New-Object "$pkcs.Pkcs12SafeContents"
        $certBag = $certBags.AddCertificate($interPublic); [void]$certBag.Attributes.Add($keyId)
        $keyBags = New-Object "$pkcs.Pkcs12SafeContents"
        $pbe = [Security.Cryptography.PbeParameters]::new([Security.Cryptography.PbeEncryptionAlgorithm]::TripleDes3KeyPkcs12, $sha1, 2048)
        $keyBag = $keyBags.AddShroudedKey($interKey, [string]::Empty, $pbe); [void]$keyBag.Attributes.Add($keyId)
        $builder = New-Object "$pkcs.Pkcs12Builder"
        $builder.AddSafeContentsUnencrypted($certBags)
        $builder.AddSafeContentsUnencrypted($keyBags)
        $builder.SealWithMac([string]::Empty, $sha1, 2048)
        $pfx = $builder.Encode()
        # Prove the file round-trips and pairs the key with the certificate before it leaves.
        $check = [System.Security.Cryptography.X509Certificates.X509CertificateLoader]::LoadPkcs12($pfx, [string]::Empty, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
        try { if (-not $check.HasPrivateKey -or $check.Thumbprint -ne $interPublic.Thumbprint) { throw 'The inspection CA PFX did not round-trip.' } }
        finally { $check.Dispose() }
        return [pscustomobject]@{
            RootPem           = $root.ExportCertificatePem()
            RootThumbprint    = $root.Thumbprint
            InterPem          = $interPublic.ExportCertificatePem()
            InterThumbprint   = $interPublic.Thumbprint
            InterNotAfterUtc  = $interPublic.NotAfter.ToUniversalTime().ToString('o')
            InterPfxBase64    = [Convert]::ToBase64String($pfx)
        }
    }
    finally {
        if ($pfx) { [Array]::Clear($pfx, 0, $pfx.Length) }
        if ($inter) { $inter.Dispose() }
        if ($root) { $root.Dispose() }
        $rootKey.Dispose(); $interKey.Dispose()
    }
}

function Get-L07TagSet {
    <#
    .SYNOPSIS Returns the common tags from config.json plus a workload and env, as an ordered hashtable.
    .DESCRIPTION The Cloud Adoption Framework's functional tags (workload, env, region) sit beside the
             course's own (managedby, lesson, scenario, lifecycle). Keys are lowercase, as CAF
             recommends; Azure treats tag keys case-insensitively.
    #>
    param([Parameter(Mandatory)][string]$Workload, [Parameter(Mandatory)][string]$Env, [hashtable]$Extra = @{})
    $t = [ordered]@{}
    foreach ($p in $script:L07Config.tags.PSObject.Properties) { $t[$p.Name] = "$($p.Value)" }
    $t['workload'] = $Workload; $t['env'] = $Env
    foreach ($k in $Extra.Keys) { $t[$k] = "$($Extra[$k])" }
    return $t
}

function Test-L07Preflight {
    <#
    .SYNOPSIS Read-only checks that stop a deployment before ARM does: owner of the group, VM SKU
             restrictions and family quota in the region, the Key Vault name, the budget API, and
             same-named resources that another lesson's lab already holds.
    .DESCRIPTION Born from the October 30 Lesson 6 redeploy, where a capacity-blocked SKU, a stale
             Entra device and a taken global name each cost a failed deployment. Returns rows with
             Result PASS, WARN or FAIL in words; throws when any row is FAIL.
    #>
    $cfg = $script:L07Config
    $rows = [Collections.Generic.List[object]]::new()
    function Add-Row([string]$Result, [string]$Check, [string]$Detail) { $rows.Add([pscustomobject]@{ Result = $Result; Check = $Check; Detail = $Detail }) }

    # 1. The resource group is absent, or this lesson's.
    if (Invoke-L07Az @('group', 'exists', '--name', $cfg.resourceGroup)) {
        $rg = Invoke-L07Az @('group', 'show', '--name', $cfg.resourceGroup)
        $owner = "$(Get-L07Value $rg 'tags.managedby')"
        if ($owner -eq $cfg.managedBy) { Add-Row 'PASS' 'Resource group owner' "$($cfg.resourceGroup) exists and is tagged managedby=$owner" }
        else { Add-Row 'FAIL' 'Resource group owner' "$($cfg.resourceGroup) exists but is tagged managedby='$owner'" }
    }
    else { Add-Row 'PASS' 'Resource group owner' "$($cfg.resourceGroup) doesn't exist yet" }

    # 2. The VM size isn't restricted for this subscription in the region.
    $sku = @(Invoke-L07Az @('vm', 'list-skus', '--location', $cfg.location, '--size', $cfg.vmSize, '--resource-type', 'virtualMachines')) |
        Where-Object name -eq $cfg.vmSize
    if (-not $sku) { Add-Row 'FAIL' "VM size $($cfg.vmSize)" "not offered in $($cfg.location)" }
    else {
        # A Location restriction blocks the size outright for this subscription. The lab doesn't pin
        # a zone, so Zone restrictions don't matter here.
        $blocked = @($sku[0].restrictions | Where-Object type -eq 'Location')
        if ($blocked.Count) { Add-Row 'FAIL' "VM size $($cfg.vmSize)" "restricted: $(@($blocked | ForEach-Object reasonCode) -join ', ')" }
        else { Add-Row 'PASS' "VM size $($cfg.vmSize)" "available to this subscription in $($cfg.location)" }
    }

    # 3. Two more vCPUs fit the family and regional quota (allocated and deallocated VMs both count).
    $usage = @(Invoke-L07Az @('vm', 'list-usage', '--location', $cfg.location))
    foreach ($q in @($cfg.vmFamily, 'cores')) {
        $u = @($usage | Where-Object { $_.name.value -eq $q })
        if (-not $u) { Add-Row 'WARN' "Quota $q" 'not reported'; continue }
        $free = [int]$u[0].limit - [int]$u[0].currentValue
        Add-Row $(if ($free -ge 2) { 'PASS' } else { 'FAIL' }) "Quota $q" "$($u[0].currentValue) of $($u[0].limit) used, 2 needed"
    }

    # 4. The Key Vault name is free, or already this lesson's vault.
    $mine = Invoke-L07Az -AllowFailure @('keyvault', 'show', '--name', $cfg.names.keyVault, '--resource-group', $cfg.resourceGroup)
    if ($mine.ExitCode -eq 0) { Add-Row 'PASS' "Key Vault $($cfg.names.keyVault)" 'already this lesson''s vault' }
    else {
        $uri = "https://management.azure.com/subscriptions/$($cfg.subscriptionId)/providers/Microsoft.KeyVault/checkNameAvailability?api-version=2023-07-01"
        $body = @{ name = $cfg.names.keyVault; type = 'Microsoft.KeyVault/vaults' } | ConvertTo-Json -Compress
        $chk = Invoke-L07Az -NoSubscription @('rest', '--method', 'post', '--url', $uri, '--body', $body, '--headers', 'Content-Type=application/json')
        $deleted = @(Invoke-L07Az @('keyvault', 'list-deleted', '--resource-type', 'vault', '--query', "[?name=='$($cfg.names.keyVault)'].name"))
        if ($deleted.Count) { Add-Row 'FAIL' "Key Vault $($cfg.names.keyVault)" 'soft-deleted in this subscription; purge it or wait out retention' }
        elseif ($chk.nameAvailable) { Add-Row 'PASS' "Key Vault $($cfg.names.keyVault)" 'name available' }
        else { Add-Row 'FAIL' "Key Vault $($cfg.names.keyVault)" "name unavailable: $($chk.reason). Take the next instance number in config.json" }
    }

    # 5. Budgets are supported for this subscription's offer (a list call fails when they aren't).
    if ($cfg.budget.enabled) {
        $b = Invoke-L07Az -AllowFailure @('consumption', 'budget', 'list')
        if ($b.ExitCode -eq 0) { Add-Row 'PASS' 'Cost budgets' 'the Consumption API answers for this subscription' }
        else { Add-Row 'FAIL' 'Cost budgets' 'the Consumption API refused; set budget.enabled to false in config.json and say why in the README' }
    }

    # 6. Another lesson's lab may hold resources with the same names in its own group. Azure allows
    #    that (names are unique per resource group), but a portal picker would show both.
    $wanted = @($cfg.names.PSObject.Properties | ForEach-Object { "$($_.Value)" })
    $all = @(Invoke-L07Az @('resource', 'list', '--query', '[].{name:name, group:resourceGroup}'))
    $clash = @($all | Where-Object { $wanted -contains $_.name -and $_.group -ne $cfg.resourceGroup })
    if ($clash.Count) { Add-Row 'WARN' 'Same names in other groups' (@($clash | ForEach-Object { "$($_.name) in $($_.group)" }) -join '; ') }
    else { Add-Row 'PASS' 'Same names in other groups' 'none' }

    [void](Write-L07Evidence 'preflight' $rows)
    $rows | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Out-Host
    if (@($rows | Where-Object Result -eq 'FAIL').Count) { throw 'Preflight FAILED. Nothing was validated or deployed.' }
    return $rows
}

function Get-L07KeyVaultToken {
    # A data-plane token for Key Vault, used in memory for one call and never printed.
    return (Invoke-L07Az @('account', 'get-access-token', '--resource', 'https://vault.azure.net')).accessToken
}

function Get-L07InspectionCaCertificate {
    <# Returns the inspection CA's Key Vault certificate record (public data), or $null. #>
    param([Parameter(Mandatory)][string]$VaultUri)
    $name = $script:L07Config.names.inspectionCaCertificate
    $headers = @{ Authorization = 'Bearer ' + (Get-L07KeyVaultToken) }
    try { return Invoke-RestMethod -Method Get -Uri "${VaultUri}certificates/${name}?api-version=7.4" -Headers $headers -TimeoutSec 30 }
    catch {
        if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { return $null }
        throw
    }
    finally { $headers = $null }
}

function Import-L07InspectionCa {
    <#
    .SYNOPSIS Imports the intermediate CA into Key Vault as a certificate. Key Vault creates the
             matching secret, which is what Azure Firewall reads. Retries while the operator's
             new data-plane role reaches the vault.
    #>
    param([Parameter(Mandatory)][string]$VaultUri, [Parameter(Mandatory)][string]$PfxBase64)
    $name = $script:L07Config.names.inspectionCaCertificate
    $body = @{
        value  = $PfxBase64
        policy = @{
            key_props    = @{ exportable = $true; kty = 'RSA'; key_size = 4096; reuse_key = $false }
            secret_props = @{ contentType = 'application/x-pkcs12' }
        }
        tags   = @{ lesson = '7'; purpose = 'Azure Firewall Premium TLS inspection (lab)' }
    } | ConvertTo-Json -Depth 5 -Compress
    try {
        for ($i = 1; $i -le 12; $i++) {
            $headers = @{ Authorization = 'Bearer ' + (Get-L07KeyVaultToken) }
            try {
                $r = Invoke-RestMethod -Method Post -Uri "${VaultUri}certificates/${name}/import?api-version=7.4" -Headers $headers -Body $body -ContentType 'application/json' -TimeoutSec 60
                return [pscustomobject]@{ Id = $r.id; SecretId = $r.sid; Thumbprint = $r.x5t; Expires = $r.attributes.exp }
            }
            catch {
                $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
                if ($code -ne 403 -or $i -eq 12) { throw "Key Vault import failed (HTTP $code). The response was not printed because the request carried key material." }
                Write-Host "Waiting for the Key Vault data role to apply ($i of 12)."
                Start-Sleep -Seconds 20
            }
            finally { $headers = $null }
        }
    }
    finally { $body = $null }
}

function Invoke-L07LogQuery {
    <#
    .SYNOPSIS Runs KQL against the lesson workspace and returns rows as objects.
    .DESCRIPTION Resource-specific firewall tables usually take a few minutes to receive rows
             after traffic. Timespan is ISO 8601, for example PT1H.
    #>
    param([Parameter(Mandatory)][string]$Query, [string]$Timespan = 'PT2H')
    $lab = Get-L07DeploymentOutput
    $body = @{ query = $Query; timespan = $Timespan } | ConvertTo-Json -Compress
    $r = Invoke-L07Az -NoSubscription @('rest', '--method', 'post', '--url', "https://api.loganalytics.io/v1/workspaces/$($lab.workspaceCustomerId)/query",
        '--resource', 'https://api.loganalytics.io', '--headers', 'Content-Type=application/json', '--body', $body)
    $rows = @()
    foreach ($t in @($r.tables)) {
        $cols = @($t.columns | ForEach-Object name)
        foreach ($row in @($t.rows)) {
            $o = [ordered]@{}
            for ($c = 0; $c -lt $cols.Count; $c++) { $o[$cols[$c]] = $row[$c] }
            $rows += [pscustomobject]$o
        }
    }
    return $rows
}

function Get-L07Status {
    <#
    .SYNOPSIS Reads production's /status page through the firewall's DNAT rule.
    .DESCRIPTION This is how the lab reports without Run Command: the production VM records
             its own probe results, and the workstation reads them through the published port.
             The DNAT rule allows only the operator's current public IP.
    #>
    param([string]$UserAgent = 'ContosoOperator/1.0', [int]$TimeoutSec = 15)
    $lab = Get-L07DeploymentOutput
    $uri = "http://$($lab.firewallPublicIpAddress):$($script:L07Config.ports.app)/status"
    return Invoke-RestMethod -Uri $uri -UserAgent $UserAgent -TimeoutSec $TimeoutSec
}
