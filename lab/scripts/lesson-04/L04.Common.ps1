<#
.SYNOPSIS
    Shared helpers for the SC-500 Lesson 4 lab: pin the subscription, call Azure CLI safely,
    save private evidence, and read the deployed resource names back from ARM.
.DESCRIPTION
    Dot-source this file from the other Lesson 4 scripts. It never prints keys, SAS tokens,
    or access tokens. Anything secret lives in a variable for one call and is then cleared.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:L04Lab = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:L04Config = Get-Content (Join-Path $script:L04Lab 'infra/lesson-04/config.json') -Raw | ConvertFrom-Json
$script:L04State = Join-Path $script:L04Lab '.azure/lesson-04'
$script:L04Evidence = Join-Path $script:L04State 'evidence'

# Call the CLI's own Python instead of az.cmd. az.cmd is a batch file, and cmd.exe mangles
# arguments that contain &, %, or quotes (SAS tokens and URLs are full of them).
$script:L04Python = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe'
if (-not (Test-Path -LiteralPath $script:L04Python)) { throw "Azure CLI Python not found at $script:L04Python. Install Azure CLI 2.85 or later." }

function Invoke-L04Az {
    <#
    .SYNOPSIS Runs one Azure CLI command pinned to the lesson subscription.
    .PARAMETER Arguments The CLI arguments, one element per token.
    .PARAMETER AllowFailure Return exit code, stdout, and stderr instead of throwing. Used by
               the demo modes, where a rejected request is the expected result.
    .PARAMETER NoSubscription Omit --subscription (data-plane storage commands reject it).
    #>
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$Raw,
        [switch]$AllowFailure,
        [switch]$NoSubscription
    )
    $start = [Diagnostics.ProcessStartInfo]::new($script:L04Python)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $all = @('-Im', 'azure.cli') + $Arguments + @('--only-show-errors')
    if (-not $NoSubscription) { $all += @('--subscription', $script:L04Config.subscriptionId) }
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

function Assert-L04Context {
    # Refuse to run against any subscription or tenant but the course's. A wrong default
    # subscription is the most common way a lab script damages something unrelated.
    $account = Invoke-L04Az @('account', 'show')
    if ($account.id -ne $script:L04Config.subscriptionId -or $account.tenantId -ne $script:L04Config.tenantId) {
        throw 'The signed-in Azure CLI context is not the course subscription and tenant.'
    }
    Write-Host "Lesson 4: $($account.name), signed in as $($account.user.name)."
    return $account
}

function Write-L04Evidence {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)]$Value)
    [void][IO.Directory]::CreateDirectory($script:L04Evidence)
    $file = Join-Path $script:L04Evidence ('{0}-{1}.json' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'), $Name)
    $Value | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $file -Encoding utf8
    return $file
}

function Get-L04Outputs {
    # Read names from the deployment record in ARM, not from a local file, so a stale copy
    # can never point a demo at the wrong resource.
    $d = Invoke-L04Az @('deployment', 'sub', 'show', '--name', $script:L04Config.deploymentName)
    if ($d.properties.provisioningState -ne 'Succeeded') { throw 'The Lesson 4 deployment has not succeeded yet. Run Deploy-L04Lab.ps1 -Deploy.' }
    $lab = $d.properties.outputs.lab.value
    if ($lab.resourceGroup -ne $script:L04Config.resourceGroup) { throw 'Deployment output points outside the Lesson 4 resource group.' }
    return $lab
}

function Get-L04OperatorIp {
    # Your workstation's public address, for firewall rules. Azure sees this
    # address, not the machine's private one.
    $ip = (Invoke-RestMethod -Uri 'https://api.ipify.org?format=json' -TimeoutSec 15).ip
    if ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { throw "Unexpected public IP lookup result: $ip" }
    return $ip
}

function Get-L04AccountKey {
    # The management-plane listKeys call. Subscription Owner can make it, which is exactly
    # the problem demo 4.1 shows. The key is returned to the caller and never written out.
    param([Parameter(Mandatory)][string]$AccountName)
    $keys = Invoke-L04Az @('storage', 'account', 'keys', 'list', '--account-name', $AccountName, '--resource-group', $script:L04Config.resourceGroup)
    return $keys[0].value
}

function Get-L04StorageError {
    # Pull the storage service's ErrorCode out of CLI stderr, so the demo reports the exact
    # reason (for example KeyBasedAuthenticationNotPermitted) instead of a generic failure.
    param([string]$Text)
    if ($Text -match 'ErrorCode:\s*(\w+)') { return $Matches[1] }
    # Friendly CLI advice is not an observed service error code. Do not manufacture one.
    if ($Text -match '"code"\s*:\s*"(\w+)"') { return $Matches[1] }
    if ($Text -match '(AuthorizationFailure|AuthorizationPermissionMismatch|KeyBasedAuthenticationNotPermitted|AuthenticationFailed|PublicAccessNotPermitted)') { return $Matches[1] }
    $first = (($Text -split "`n") | Where-Object { $_.Trim() -and $_ -notmatch '^ERROR:\s*$' } | Select-Object -First 1)
    return 'Unrecognized: ' + ($first -replace '\s+', ' ').Trim().Substring(0, [Math]::Min(90, ($first -replace '\s+', ' ').Trim().Length))
}

function Invoke-L04Arm {
    # Direct ARM REST for resources the CLI doesn't wrap (Defender for Storage settings,
    # security alerts). The token stays in memory for one call and is then cleared.
    param([Parameter(Mandatory)][string]$Path, [string]$Method = 'GET', $Body, [switch]$AsHashtable)
    $token = Invoke-L04Az @('account', 'get-access-token', '--resource', 'https://management.azure.com/')
    $uri = if ($Path.StartsWith('https://management.azure.com/')) { $Path } elseif ($Path.StartsWith('/')) { 'https://management.azure.com' + $Path } else { throw 'ARM URL is outside management.azure.com.' }
    $params = @{ Uri = $uri; Method = $Method; Headers = @{ Authorization = 'Bearer ' + $token.accessToken }; ContentType = 'application/json'; TimeoutSec = 60 }
    if ($null -ne $Body) { $params.Body = $Body | ConvertTo-Json -Depth 50 -Compress }
    try {
        # Alert extended properties can contain both source and Source. Preserve both keys.
        if ($AsHashtable) { return (Invoke-WebRequest @params).Content | ConvertFrom-Json -AsHashtable -Depth 100 }
        return Invoke-RestMethod @params
    }
    finally { $token = $null; $params.Headers.Clear() }
}

function Get-L04Value {
    <#
    .SYNOPSIS Reads a dotted property path from ARM JSON, returning $null when any part is
             missing. ARM omits optional properties, and StrictMode would otherwise throw.
    .EXAMPLE Get-L04Value $setting 'properties.malwareScanning.onUpload.capGBPerMonth'
    #>
    param($Object, [Parameter(Mandatory)][string]$Path)
    $cur = $Object
    foreach ($part in $Path -split '\.') {
        if ($null -eq $cur) { return $null }
        if ($cur -is [System.Collections.IDictionary]) {
            if (-not $cur.Contains($part)) { return $null }
            $cur = $cur[$part]
            continue
        }
        $prop = $cur.PSObject.Properties[$part]
        if ($null -eq $prop) { return $null }
        $cur = $prop.Value
    }
    return $cur
}

function Get-L04PlanTier {
    <#
    .SYNOPSIS Reads one Defender for Cloud plan's pricing tier at the lesson subscription (GET only).
    .DESCRIPTION Deploy and Reset call this before any step that needs a paid plan, so a parked lab
                 (every plan Free) skips that step with a plain message instead of failing or, worse,
                 enabling per-resource protection that bills. Only Set-L04DefenderWindow.ps1 changes plans.
    .EXAMPLE Get-L04PlanTier StorageAccounts   # returns Free or Standard
    #>
    param([Parameter(Mandatory)][ValidateSet('StorageAccounts', 'SqlServers', 'SqlServerVirtualMachines', 'OpenSourceRelationalDatabases', 'CosmosDbs')][string]$Plan)
    $p = Invoke-L04Arm -Path "/subscriptions/$($script:L04Config.subscriptionId)/providers/Microsoft.Security/pricings/$($Plan)?api-version=2024-01-01"
    return [string](Get-L04Value $p 'properties.pricingTier')
}

function Get-L04SqlToken {
    # Token for the Azure SQL audience, used by Invoke-Sqlcmd -AccessToken.
    $t = Invoke-L04Az @('account', 'get-access-token', '--resource', 'https://database.windows.net/')
    return $t.accessToken
}

function Set-L04StorageInheritance {
    <#
    .SYNOPSIS Applies the existing subscription configuration to this lesson's accounts.
    .DESCRIPTION Does not change the subscription plan. Explicit account enablement avoids
                 the documented subscription propagation delay (up to 24 hours).
    #>
    param([Parameter(Mandatory)]$Lab)
    $plan = Invoke-L04Arm -Path "/subscriptions/$($script:L04Config.subscriptionId)/providers/Microsoft.Security/pricings/StorageAccounts?api-version=2024-01-01"
    if ($plan.properties.pricingTier -ne 'Standard' -or $plan.properties.subPlan -ne 'DefenderForStorageV2') { throw 'The existing subscription Storage V2 plan is not enabled.' }
    $scan = $plan.properties.extensions | Where-Object name -eq 'OnUploadMalwareScanning'
    $sdd = $plan.properties.extensions | Where-Object name -eq 'SensitiveDataDiscovery'
    if (-not $scan -or -not $sdd) { throw 'Expected subscription extensions are missing; no plan change made.' }
    $cap = [int]$scan.additionalExtensionProperties.CapGBPerMonthPerStorageAccount
    $body = @{ properties = @{
        isEnabled = $true; overrideSubscriptionLevelSettings = $false
        malwareScanning = @{ onUpload = @{ isEnabled = ($scan.isEnabled -eq 'True'); capGBPerMonth = $cap } }
        sensitiveDataDiscovery = @{ isEnabled = ($sdd.isEnabled -eq 'True') }
    } }
    foreach ($id in @($Lab.recordsId, $Lab.intakeId)) {
        if ($id -notlike "/subscriptions/$($script:L04Config.subscriptionId)/resourceGroups/$($script:L04Config.resourceGroup)/providers/Microsoft.Storage/storageAccounts/*") { throw 'Account outside Lesson 4.' }
        $path = "$id/providers/Microsoft.Security/defenderForStorageSettings/current?api-version=2025-06-01"
        [void](Invoke-L04Arm -Path $path -Method PUT -Body $body)
        $read = Invoke-L04Arm -Path $path
        [void](Write-L04Evidence 'storage-inheritance' $read)
        if (-not $read.properties.isEnabled -or $read.properties.overrideSubscriptionLevelSettings) { throw 'Account inheritance readback did not match.' }
    }
}

function Set-L04RecordsIpRule {
    <#
    .SYNOPSIS Adds or removes the workstation's IP rule on the records account firewall.
    .NOTES   Firewall changes take up to a minute to reach every storage front end, so
             callers that need the new state immediately should follow with Wait-L04Records.
    #>
    param([Parameter(Mandatory)][string]$AccountName, [Parameter(Mandatory)][string]$Ip, [Parameter(Mandatory)][ValidateSet('Add', 'Remove')][string]$Action)
    $current = Invoke-L04Az @('storage', 'account', 'show', '--name', $AccountName, '--resource-group', $script:L04Config.resourceGroup)
    $present = @($current.networkRuleSet.ipRules | Where-Object { $_.ipAddressOrRange -eq $Ip }).Count -gt 0
    if ($Action -eq 'Add' -and -not $present) {
        [void](Invoke-L04Az @('storage', 'account', 'network-rule', 'add', '--account-name', $AccountName, '--resource-group', $script:L04Config.resourceGroup, '--ip-address', $Ip))
    }
    elseif ($Action -eq 'Remove' -and $present) {
        [void](Invoke-L04Az @('storage', 'account', 'network-rule', 'remove', '--account-name', $AccountName, '--resource-group', $script:L04Config.resourceGroup, '--ip-address', $Ip))
    }
}

function Wait-L04Records {
    <#
    .SYNOPSIS Polls a key-authorized container read until the firewall lets it through.
    .NOTES   Only used during setup and reset, while Shared Key is still allowed.
    #>
    param([Parameter(Mandatory)][string]$AccountName, [Parameter(Mandatory)][string]$Key, [int]$TimeoutSeconds = 150)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $r = Invoke-L04Az -AllowFailure -NoSubscription @('storage', 'container', 'list', '--account-name', $AccountName, '--account-key', $Key)
        if ($r.ExitCode -eq 0) { return }
        Start-Sleep -Seconds 10
    } while ((Get-Date) -lt $deadline)
    throw "The records account still rejects the workstation after $TimeoutSeconds seconds: $(Get-L04StorageError $r.Stderr)"
}

function Initialize-L04StorageBaseline {
    <#
    .SYNOPSIS Puts the records account in the documented CTSO-L04-BASELINE state.
    .DESCRIPTION
        Baseline = Shared Key allowed, synthetic blobs present, stored access policy present,
        and no firewall rule for the workstation. Getting there needs a temporary IP rule,
        because a firewall with no rule blocks the setup writes too.
    #>
    param([Parameter(Mandatory)]$Lab)
    $acct = $Lab.recordsAccount
    $rg = $script:L04Config.resourceGroup
    $ip = Get-L04OperatorIp

    # Shared Key back on, since the demo turns it off. Idempotent when already on.
    [void](Invoke-L04Az @('storage', 'account', 'update', '--name', $acct, '--resource-group', $rg, '--allow-shared-key-access', 'true'))
    Set-L04RecordsIpRule -AccountName $acct -Ip $ip -Action Add
    $key = Get-L04AccountKey -AccountName $acct
    try {
        Wait-L04Records -AccountName $acct -Key $key
        $seed = Join-Path $script:L04Lab 'infra/lesson-04/seed'
        foreach ($item in @(@('service-records', 'SR-2026-0418.json'), @('customer-documents', 'CTSO-CUST-1042-contract.txt'))) {
            [void](Invoke-L04Az -NoSubscription @('storage', 'blob', 'upload', '--account-name', $acct, '--account-key', $key, '--container-name', $item[0], '--name', $item[1], '--file', (Join-Path $seed $item[1]), '--overwrite', 'true'))
        }
        # Stored access policy: read-only, 30 days. A service SAS that names this policy
        # inherits its permissions and expiry, so deleting the policy revokes every such SAS.
        $expiry = [DateTime]::UtcNow.AddDays(30).ToString('yyyy-MM-ddTHH:mmZ')
        # The CLI returns policies as an object keyed by policy ID; enumerate its property
        # names explicitly so an empty result works under StrictMode.
        $policies = Invoke-L04Az -NoSubscription @('storage', 'container', 'policy', 'list', '--container-name', 'service-records', '--account-name', $acct, '--account-key', $key)
        $names = if ($null -eq $policies) { @() } else { @($policies.PSObject.Properties | ForEach-Object { $_.Name }) }
        $has = $names -contains $script:L04Config.storedAccessPolicy
        if (-not $has) {
            [void](Invoke-L04Az -NoSubscription @('storage', 'container', 'policy', 'create', '--container-name', 'service-records', '--name', $script:L04Config.storedAccessPolicy, '--permissions', 'r', '--expiry', $expiry, '--account-name', $acct, '--account-key', $key))
        }
    }
    finally {
        $key = $null
        # Leave the firewall with no rule for the workstation (the first beat of demo 4.1),
        # even when a seed step failed, so a half-finished reset never widens access.
        Set-L04RecordsIpRule -AccountName $acct -Ip $ip -Action Remove
    }
}

function Initialize-L04SqlBaseline {
    <#
    .SYNOPSIS Creates the synthetic ServiceRecords table in the lesson database (idempotent).
    .NOTES   Runs as the Entra admin with an access token. No SQL login exists to use instead:
             Entra-only authentication was on from creation.
    #>
    param([Parameter(Mandatory)]$Lab)
    $seedSql = @'
IF OBJECT_ID('dbo.ServiceRecords') IS NULL
    CREATE TABLE dbo.ServiceRecords (
        RequestId   varchar(20)  NOT NULL PRIMARY KEY,
        Customer    nvarchar(60) NOT NULL,
        Equipment   nvarchar(80) NOT NULL,
        Status      varchar(20)  NOT NULL,
        AssignedTo  nvarchar(60) NOT NULL);
MERGE dbo.ServiceRecords AS t
USING (VALUES
    ('SR-2026-0418', N'Fabrikam, Inc.', N'Chiller unit CH-220, site 3', 'Scheduled', N'Debra Garcia'),
    ('SR-2026-0419', N'Tailspin Toys', N'Packaging line 2 conveyor', 'Open', N'Debra Garcia'),
    ('SR-2026-0420', N'Wide World Importers', N'Forklift charger FC-7', 'Closed', N'Debra Garcia')
) AS s (RequestId, Customer, Equipment, Status, AssignedTo)
ON t.RequestId = s.RequestId
WHEN NOT MATCHED THEN INSERT VALUES (s.RequestId, s.Customer, s.Equipment, s.Status, s.AssignedTo);
SELECT COUNT(*) AS Rows FROM dbo.ServiceRecords;
'@
    $token = Get-L04SqlToken
    try {
        $rows = Invoke-Sqlcmd -ServerInstance $Lab.sqlFqdn -Database $Lab.sqlDatabase -AccessToken $token -Query $seedSql -Encrypt Mandatory -ErrorAction Stop
        return [int]$rows.Rows
    }
    finally { $token = $null }
}
