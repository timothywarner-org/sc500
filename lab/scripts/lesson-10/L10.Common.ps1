<#
.SYNOPSIS
    Shared helpers for the SC-500 Lesson 10 lab: pin the subscription and tenant, call Azure CLI
    safely, save private evidence, call ARM and Microsoft Graph, find the lab's agent identity
    objects, and run the Microsoft Entra Agent ID autonomous token flow.
.DESCRIPTION
    Dot-source this file from the other Lesson 10 scripts. Same design as L09.Common.ps1.
    Nothing here prints a token or a secret. The only credential the lab ever creates is a
    short-lived blueprint client secret: New-L10BlueprintSecret returns it to the caller in
    memory, and the caller removes it with Remove-L10BlueprintSecret before it exits.
    No script signs in as anyone. Graph and ARM calls use your current Azure CLI session.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:L10Lab = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:L10Infra = Join-Path $script:L10Lab 'infra/lesson-10'
$script:L10Config = Get-Content (Join-Path $script:L10Infra 'config.json') -Raw | ConvertFrom-Json
$script:L10State = Join-Path $script:L10Lab '.azure/lesson-10'
$script:L10Evidence = Join-Path $script:L10State 'evidence'
$script:L10Graph = 'https://graph.microsoft.com'

# Call the CLI's own Python instead of az.cmd: cmd.exe mangles &, %, |, and quotes, which OData
# filters and JSON bodies are full of. -I ignores PYTHON* variables, so UTF-8 goes on as -X utf8.
$script:L10Python = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe'
if (-not (Test-Path -LiteralPath $script:L10Python)) { throw "Azure CLI Python not found at $script:L10Python. Install Azure CLI 2.85 or later." }

function Invoke-L10Az {
    <#
    .SYNOPSIS Runs one Azure CLI command pinned to the lesson subscription.
    .PARAMETER Arguments The CLI arguments, one element per token (no shell parsing happens).
    .PARAMETER Raw Return stdout as text instead of parsed JSON.
    .PARAMETER AllowFailure Return exit code, stdout, and stderr instead of throwing.
    .PARAMETER NoSubscription Omit --subscription (az rest, az ad, and token commands reject it).
    #>
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$Raw,
        [switch]$AllowFailure,
        [switch]$NoSubscription
    )
    $start = [Diagnostics.ProcessStartInfo]::new($script:L10Python)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    $all = @('-X', 'utf8', '-Im', 'azure.cli') + $Arguments + @('--only-show-errors')
    if (-not $NoSubscription) { $all += @('--subscription', $script:L10Config.subscriptionId) }
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

function Assert-L10Context {
    # Refuse to run against any subscription, tenant, or operator but the course's.
    $account = Invoke-L10Az @('account', 'show')
    if ($account.id -ne $script:L10Config.subscriptionId -or $account.tenantId -ne $script:L10Config.tenantId) {
        throw 'The signed-in Azure CLI context is not the course subscription and tenant.'
    }
    if ($account.user.name -ne $script:L10Config.operatorUpn) { throw "Sign in as $($script:L10Config.operatorUpn); this lab creates directory objects as the operator." }
    Write-Host "Lesson 10: $($account.name), signed in as $($account.user.name)."
    return $account
}

function Write-L10Evidence {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)]$Value)
    [void][IO.Directory]::CreateDirectory($script:L10Evidence)
    $file = Join-Path $script:L10Evidence ('{0}-{1}.json' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'), $Name)
    $Value | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $file -Encoding utf8
    return $file
}

function Get-L10Value {
    <# .SYNOPSIS Reads a dotted property path, returning $null when any part is missing (StrictMode-safe). #>
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

function Invoke-L10Rest {
    <#
    .SYNOPSIS Calls ARM (a path starting with /subscriptions or /providers) or Microsoft Graph (a
             path starting with /v1.0 or /beta, or a full https URL) through az rest.
    .PARAMETER Body An object; sent as compact JSON.
    .PARAMETER OData Add OData-Version: 4.0, which the agent identity APIs require with @odata.type.
    .PARAMETER AllowNotFound Return $null on 404 instead of throwing.
    .PARAMETER Resource The token audience for a URL az rest doesn't recognize (Power Platform, Dataverse).
    #>
    param(
        [ValidateSet('get', 'put', 'post', 'delete', 'patch')][string]$Method = 'get',
        [Parameter(Mandatory)][string]$Path,
        $Body,
        [switch]$OData,
        [switch]$AllowNotFound,
        [string]$Resource
    )
    $url = if ($Path -like 'https://*') { $Path } elseif ($Path -match '^/(v1\.0|beta)/') { "$script:L10Graph$Path" } else { "https://management.azure.com$Path" }
    $cli = @('rest', '--method', $Method, '--url', $url)
    if ($Resource) { $cli += @('--resource', $Resource) }
    $headers = @()
    if ($null -ne $Body) { $headers += 'Content-Type=application/json'; $cli += @('--body', ($Body | ConvertTo-Json -Depth 30 -Compress)) }
    if ($OData) { $headers += 'OData-Version=4.0' }
    if ($headers.Count) { $cli += @('--headers') + $headers }
    $r = Invoke-L10Az -NoSubscription -AllowFailure $cli
    if ($r.ExitCode -ne 0) {
        if ($AllowNotFound -and $r.Stderr -match '(Not Found|NotFound|ResourceNotFound|Request_ResourceNotFound|404)') { return $null }
        throw "$Method $Path failed: $($r.Stderr.Trim())"
    }
    $text = $r.Stdout.Trim().TrimStart([char]0xFEFF)
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text | ConvertFrom-Json -Depth 100
}

function Get-L10Outputs {
    # Read names from the deployment record in ARM, not a local file.
    $d = Invoke-L10Az -AllowFailure @('deployment', 'sub', 'show', '--name', $script:L10Config.deploymentName)
    if ($d.ExitCode -ne 0) { throw 'No Lesson 10 deployment found. Run Deploy-L10Lab.ps1 -Deploy first.' }
    $d = $d.Stdout | ConvertFrom-Json -Depth 100
    if ($d.properties.provisioningState -ne 'Succeeded') { throw "The Lesson 10 deployment is $($d.properties.provisioningState), not Succeeded." }
    return $d.properties.outputs.lab.value
}

function Get-L10User {
    param([Parameter(Mandatory)][string]$Upn)
    return Invoke-L10Rest -Path "/v1.0/users/$([uri]::EscapeDataString($Upn))?`$select=id,displayName,userPrincipalName"
}

function Get-L10One {
    <# .SYNOPSIS Returns the single object a filtered list names, $null for none, and throws for duplicates. #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$What)
    $items = @((Invoke-L10Rest -Path $Path).value)
    if ($items.Count -gt 1) { throw "More than one $What matches. Resolve that by hand first." }
    if ($items.Count -eq 0) { return $null }
    return $items[0]
}

function Get-L10Blueprint {
    $n = $script:L10Config.directory.blueprint
    return Get-L10One -What "agent identity blueprint named $n" -Path "/v1.0/applications/microsoft.graph.agentIdentityBlueprint?`$filter=displayName eq '$n'&`$select=id,appId,displayName,description,tags,passwordCredentials"
}

function Get-L10BlueprintPrincipal {
    param([Parameter(Mandatory)][string]$AppId)
    return Get-L10One -What 'blueprint principal' -Path "/v1.0/servicePrincipals?`$filter=appId eq '$AppId'&`$select=id,appId,displayName,servicePrincipalType"
}

function Get-L10Agent {
    <# .SYNOPSIS Returns one of the lab's agent identities by its config key: 'assistant' or 'triage'. #>
    param([Parameter(Mandatory)][ValidateSet('assistant', 'triage')][string]$Which)
    $n = $script:L10Config.directory.$Which
    return Get-L10One -What "agent identity named $n" -Path "/beta/servicePrincipals/microsoft.graph.agentIdentity?`$filter=displayName eq '$n'"
}

function Get-L10Policy {
    param([Parameter(Mandatory)][string]$Name)
    return Get-L10One -What "Conditional Access policy named $Name" -Path "/beta/identity/conditionalAccess/policies?`$filter=displayName eq '$Name'"
}

function Get-L10TokenClaims {
    # Decodes a JWT's payload (not its signature) so a script can print the claims that matter.
    param([Parameter(Mandatory)][string]$Token)
    $part = $Token.Split('.')[1].Replace('-', '+').Replace('_', '/')
    switch ($part.Length % 4) { 2 { $part += '==' } 3 { $part += '=' } }
    return ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($part)) | ConvertFrom-Json)
}

function New-L10BlueprintSecret {
    <#
    .SYNOPSIS Adds a short-lived client secret to the lab blueprint and returns it, in memory only.
    .DESCRIPTION Microsoft's guidance is a federated credential or a certificate for a real agent;
             a secret is for local development. The lab uses one because nothing here runs in
             Azure to supply a managed identity, and it keeps the secret's life to the one run
             that needs it: the caller must pass the result to Remove-L10BlueprintSecret in a
             finally block. The value is never printed and never written to disk.
    #>
    param([Parameter(Mandatory)][string]$BlueprintObjectId)
    $hours = [int]$script:L10Config.directory.secretLifetimeHours
    $body = @{ passwordCredential = @{ displayName = 'sc500-l10-demo (removed by the same run)'; endDateTime = [DateTime]::UtcNow.AddHours($hours).ToString('o') } }
    $r = Invoke-L10Rest -Method post -Path "/v1.0/applications/$BlueprintObjectId/addPassword" -Body $body
    return [pscustomobject]@{ KeyId = $r.keyId; Secret = $r.secretText }
}

function Remove-L10BlueprintSecret {
    param([Parameter(Mandatory)][string]$BlueprintObjectId, [Parameter(Mandatory)][string]$KeyId)
    [void](Invoke-L10Rest -Method post -Path "/v1.0/applications/$BlueprintObjectId/removePassword" -Body @{ keyId = $KeyId })
}

function Invoke-L10TokenRequest {
    # One POST to the tenant's token endpoint. Returns the parsed body and status; never throws on
    # an OAuth error, because the AADSTS code in the error is the result the demo is looking for.
    param([Parameter(Mandatory)][hashtable]$Form)
    $uri = "https://login.microsoftonline.com/$($script:L10Config.tenantId)/oauth2/v2.0/token"
    $resp = Invoke-WebRequest -Method Post -Uri $uri -Body $Form -ContentType 'application/x-www-form-urlencoded' -SkipHttpErrorCheck -TimeoutSec 60
    $json = $null
    try { $json = $resp.Content | ConvertFrom-Json } catch { }
    return [pscustomobject]@{ Status = [int]$resp.StatusCode; Body = $json }
}

function Get-L10AgentToken {
    <#
    .SYNOPSIS Runs the autonomous agent flow: the blueprint's secret buys an exchange token (T1) for
             one agent identity (fmi_path), and the agent identity presents T1 for a resource token.
    .OUTPUTS Ok, Step (which request failed), Error (AADSTS code and message), Token (in memory only),
             and the agent token's non-secret claims.
    #>
    param(
        [Parameter(Mandatory)][string]$BlueprintAppId,
        [Parameter(Mandatory)][string]$Secret,
        [Parameter(Mandatory)][string]$AgentAppId,
        [Parameter(Mandatory)][string]$Scope
    )
    # A new secret can take a little while to reach every token-service instance; retry briefly.
    $t1 = $null
    foreach ($try in 1..12) {
        $t1 = Invoke-L10TokenRequest @{ client_id = $BlueprintAppId; client_secret = $Secret; grant_type = 'client_credentials'
                                         scope = 'api://AzureADTokenExchange/.default'; fmi_path = $AgentAppId }
        if ($t1.Status -eq 200) { break }
        if ((Get-L10Value $t1.Body 'error_description') -notmatch 'AADSTS7000215|AADSTS700016|AADSTS7000222') { break }
        Start-Sleep -Seconds 10
    }
    # Keep the AADSTS code and sentence; drop the trace and correlation IDs that follow it.
    $short = { param($b) (((Get-L10Value $b 'error_description') -split "`r?`n")[0] -replace '\s*Trace ID:.*$', '') }
    if ($t1.Status -ne 200) { return [pscustomobject]@{ Ok = $false; Step = 'blueprint exchange token (T1)'; Error = (& $short $t1.Body); Token = $null; Claims = $null } }
    $tr = Invoke-L10TokenRequest @{ client_id = $AgentAppId; grant_type = 'client_credentials'; scope = $Scope
                                     client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'; client_assertion = $t1.Body.access_token }
    if ($tr.Status -ne 200) { return [pscustomobject]@{ Ok = $false; Step = 'agent identity resource token'; Error = (& $short $tr.Body); Token = $null; Claims = $null } }
    $c = Get-L10TokenClaims $tr.Body.access_token
    $claims = [ordered]@{ aud = $c.aud; appid = (Get-L10Value $c 'appid'); oid = $c.oid; idtyp = (Get-L10Value $c 'idtyp')
                          xms_act_fct = (Get-L10Value $c 'xms_act_fct'); xms_sub_fct = (Get-L10Value $c 'xms_sub_fct'); roles = (Get-L10Value $c 'roles') }
    return [pscustomobject]@{ Ok = $true; Step = $null; Error = $null; Token = $tr.Body.access_token; Claims = [pscustomobject]$claims }
}

function Invoke-L10Blob {
    <#
    .SYNOPSIS Reads one blob with a bearer token and returns the status and the first line of the
             body (or of the error). Never throws on an HTTP error status; that status is the result.
    #>
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][string]$Token)
    $h = @{ Authorization = "Bearer $Token"; 'x-ms-version' = '2023-11-03' }
    $resp = Invoke-WebRequest -Uri $Uri -Headers $h -SkipHttpErrorCheck -TimeoutSec 60
    $text = [string]$resp.Content
    $code = if ($text -match '<Code>([^<]+)</Code>') { $Matches[1] } else { $null }
    $first = ($text -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
    return [pscustomobject]@{ Status = [int]$resp.StatusCode; Code = $code; FirstLine = $first; AtUtc = [DateTime]::UtcNow.ToString('HH:mm:ss') }
}
