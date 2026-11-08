<#
.SYNOPSIS
    Shared helpers for the SC-500 Lesson 9 lab: pin the subscription, call Azure CLI safely,
    save private evidence, read deployment outputs, call ARM, Microsoft Graph, and Resource Graph,
    get a token for the lab API from the operator's existing Azure CLI sign-in, send probe
    requests, and run kubectl inside the AKS cluster.
.DESCRIPTION
    Dot-source this file from the other Lesson 9 scripts. Same design as L08.Common.ps1.
    Nothing here prints a token, a subscription key, or a SAS signature: requests carry them, and
    evidence records only status codes, response bodies, and header names that matter.
    No script signs in as anyone. Tokens come from your current Azure CLI session.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:L09Lab = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:L09Config = Get-Content (Join-Path $script:L09Lab 'infra/lesson-09/config.json') -Raw | ConvertFrom-Json
# State is kept per subscription, as Lessons 7 and 8 do, so an earlier build's evidence
# (still in .azure/lesson-09) can't be mistaken for the lab subscription build's.
$script:L09State = Join-Path $script:L09Lab ".azure/lesson-09/$($script:L09Config.subscriptionId)"
$script:L09Evidence = Join-Path $script:L09State 'evidence'

# Call the CLI's own Python instead of az.cmd. az.cmd is a batch file, and cmd.exe mangles
# arguments that contain &, %, |, or quotes, which JMESPath, KQL, and policy XML are full of.
$script:L09Python = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe'
if (-not (Test-Path -LiteralPath $script:L09Python)) { throw "Azure CLI Python not found at $script:L09Python. Install Azure CLI 2.85 or later." }

function Invoke-L09Az {
    <#
    .SYNOPSIS Runs one Azure CLI command pinned to the lesson subscription.
    .PARAMETER Arguments The CLI arguments, one element per token.
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
    $start = [Diagnostics.ProcessStartInfo]::new($script:L09Python)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    # UTF-8 both ways: API Management returns policy documents with a byte-order mark, which the
    # CLI can't print through the Windows code page. -I ignores PYTHON* variables, so the UTF-8
    # mode goes on the command line as -X utf8.
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    $all = @('-X', 'utf8', '-Im', 'azure.cli') + $Arguments + @('--only-show-errors')
    if (-not $NoSubscription) { $all += @('--subscription', $script:L09Config.subscriptionId) }
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

function Assert-L09Context {
    # Refuse to run against any subscription or tenant but the course's.
    $account = Invoke-L09Az @('account', 'show')
    if ($account.id -ne $script:L09Config.subscriptionId -or $account.tenantId -ne $script:L09Config.tenantId) {
        throw 'The signed-in Azure CLI context is not the course subscription and tenant.'
    }
    Write-Host "Lesson 9: $($account.name), signed in as $($account.user.name)."
    return $account
}

function Write-L09Evidence {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)]$Value)
    [void][IO.Directory]::CreateDirectory($script:L09Evidence)
    $file = Join-Path $script:L09Evidence ('{0}-{1}.json' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'), $Name)
    $Value | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $file -Encoding utf8
    return $file
}

function Get-L09Value {
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

function Invoke-L09Rest {
    <#
    .SYNOPSIS Calls ARM (a path starting with /subscriptions or /providers) or Microsoft Graph
             (a full https://graph.microsoft.com URL) through az rest.
    .PARAMETER Body An object; sent as compact JSON.
    .PARAMETER AllowNotFound Return $null on 404 instead of throwing.
    #>
    param(
        [ValidateSet('get', 'put', 'post', 'delete', 'patch')][string]$Method = 'get',
        [Parameter(Mandatory)][string]$Path,
        $Body,
        [switch]$AllowNotFound
    )
    $url = if ($Path -like 'https://*') { $Path } else { "https://management.azure.com$Path" }
    $cli = @('rest', '--method', $Method, '--url', $url)
    if ($null -ne $Body) { $cli += @('--headers', 'Content-Type=application/json', '--body', ($Body | ConvertTo-Json -Depth 30 -Compress)) }
    $r = Invoke-L09Az -NoSubscription -AllowFailure $cli
    if ($r.ExitCode -ne 0) {
        if ($AllowNotFound -and $r.Stderr -match '(Not Found|NotFound|ResourceNotFound|404)') { return $null }
        throw "$Method $Path failed: $($r.Stderr.Trim())"
    }
    $text = $r.Stdout.Trim().TrimStart([char]0xFEFF)
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    # Some calls return a document rather than JSON (an API Management policy in rawxml format).
    if ($text[0] -notin '{', '[') { return $text }
    return $text | ConvertFrom-Json -Depth 100
}

function Invoke-L09Graph {
    <# .SYNOPSIS Runs an Azure Resource Graph query over the lesson subscription; returns rows. #>
    param([Parameter(Mandatory)][string]$Query)
    $body = @{ subscriptions = @($script:L09Config.subscriptionId); query = $Query; options = @{ resultFormat = 'objectArray' } }
    $r = Invoke-L09Rest -Method post -Path '/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' -Body $body
    return @($r.data)
}

function Get-L09Outputs {
    # Read names from the deployment record in ARM, not a local file, so a stale copy can't point
    # a demo at the wrong resource.
    param([ValidateSet('Retained', 'Edge')][string]$Lab = 'Retained')
    $cfg = $script:L09Config
    $d = if ($Lab -eq 'Retained') { Invoke-L09Az -AllowFailure @('deployment', 'sub', 'show', '--name', $cfg.deploymentName) }
         else { Invoke-L09Az -AllowFailure @('deployment', 'group', 'show', '--resource-group', $cfg.resourceGroup, '--name', $cfg.edgeDeploymentName) }
    if ($d.ExitCode -ne 0) { throw "No $Lab deployment found. Deploy it first." }
    $d = $d.Stdout | ConvertFrom-Json -Depth 100
    if ($d.properties.provisioningState -ne 'Succeeded') { throw "The $Lab deployment is $($d.properties.provisioningState), not Succeeded." }
    if ($Lab -eq 'Retained') { return $d.properties.outputs.lab.value }
    return $d.properties.outputs.edge.value
}

function Get-L09OperatorIp {
    # Allow lists name the operator's current public IP. Scripts print it as "Your IP".
    return (Invoke-RestMethod -Uri 'https://api.ipify.org?format=json' -TimeoutSec 15).ip
}

function Get-L09ApiApp {
    <# .SYNOPSIS Returns the lab API app registration (appId, id, scope id), or $null if absent. #>
    $name = $script:L09Config.apiAppDisplayName
    $r = Invoke-L09Rest -Path "https://graph.microsoft.com/v1.0/applications?`$filter=displayName eq '$name'&`$select=id,appId,displayName,identifierUris,api,notes"
    $apps = @($r.value)
    if ($apps.Count -gt 1) { throw "More than one app registration is named $name. Resolve that by hand first." }
    if ($apps.Count -eq 0) { return $null }
    return $apps[0]
}

function Get-L09ApiToken {
    <#
    .SYNOPSIS Gets an access token for the lab API from the operator's existing Azure CLI sign-in.
    .DESCRIPTION The API app pre-authorizes the Azure CLI, so this needs no consent prompt and no
             new sign-in. The token is returned to the caller for a request header; it's never
             printed or written to evidence.
    #>
    param([Parameter(Mandatory)][string]$AppId)
    $r = Invoke-L09Az -NoSubscription -AllowFailure @('account', 'get-access-token', '--scope', "api://$AppId/.default", '--query', 'accessToken')
    if ($r.ExitCode -ne 0) { throw "Couldn't get a token for api://$AppId from the current Azure CLI sign-in: $($r.Stderr.Trim())" }
    return ($r.Stdout | ConvertFrom-Json)
}

function Get-L09TokenClaims {
    # Decodes a JWT's payload (not its signature) so a script can print the claims that matter.
    param([Parameter(Mandatory)][string]$Token)
    $part = $Token.Split('.')[1].Replace('-', '+').Replace('_', '/')
    switch ($part.Length % 4) { 2 { $part += '==' } 3 { $part += '=' } }
    return ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($part)) | ConvertFrom-Json)
}

function Get-L09GroupResources {
    <#
    .SYNOPSIS Lists every resource in the lesson's resource group, with tags, through the ARM REST
             API, following nextLink pages.
    .NOTES   Why not az resource list: in rehearsal on September 27, 2026, Azure CLI 2.85 returned an
             empty list for the September group (rg-sc500-l09-apps) while the REST API listed all 23
             resources, and on November 1, 2026 Azure CLI 2.85.0 did the same to Lesson 8's group.
             A cleanup script that trusts an empty list deletes nothing and reports success, so the
             lesson's scripts read the group through ARM directly, and callers treat an empty
             answer as unproven, never as "nothing there".
    .PARAMETER ResourceGroup Another group to list (the AKS node resource group); default is the lab's.
    #>
    param([string]$ResourceGroup = $script:L09Config.resourceGroup)
    $cfg = $script:L09Config
    $path = "/subscriptions/$($cfg.subscriptionId)/resourceGroups/$ResourceGroup/resources?api-version=2021-04-01"
    $items = @()
    while ($path) {
        $page = Invoke-L09Rest -Path $path
        $items += @($page.value)
        $path = Get-L09Value $page 'nextLink'
    }
    return $items
}

function Test-L09Bounded {
    <#
    .SYNOPSIS True when a resource carries this lesson's managedby tag and a bounded lifecycle.
    .DESCRIPTION Tag keys are case-insensitive in Azure and in PowerShell property lookup, but values
             aren't, so this compares the lowercase CAF values config.json sets. The September build
             tagged bounded resources managedBy plus bounded=true; this build uses managedby plus
             lifecycle "bounded: remove after the rehearsal or take".
    #>
    param([Parameter(Mandatory)]$Resource)
    return ("$(Get-L09Value $Resource 'tags.managedby')" -eq $script:L09Config.managedBy) -and ("$(Get-L09Value $Resource 'tags.lifecycle')" -like 'bounded*')
}

function Get-L09TagSet {
    <#
    .SYNOPSIS Returns the common tags from config.json plus a workload and env, as an ordered hashtable.
    .DESCRIPTION CAF's functional tags (workload, env, region) sit beside the course's own (managedby,
             lesson, scenario, lifecycle). Keys are lowercase, as CAF recommends.
    #>
    param([Parameter(Mandatory)][string]$Workload, [Parameter(Mandatory)][string]$Env, [hashtable]$Extra = @{})
    $t = [ordered]@{}
    foreach ($p in $script:L09Config.tags.PSObject.Properties) { $t[$p.Name] = "$($p.Value)" }
    $t['workload'] = $Workload; $t['env'] = $Env
    foreach ($k in $Extra.Keys) { $t[$k] = "$($Extra[$k])" }
    return $t
}

function Test-L09Preflight {
    <#
    .SYNOPSIS Read-only checks that stop a deployment before ARM does: the group's and the node
             group's owner, the node size's restrictions, family and regional vCPU quota, resource
             providers, the Defender plans the lesson shows, global name availability, the budget
             API, the lab API app registration, and same-named resources in other groups.
    .DESCRIPTION Same design as Test-L08Preflight (docs/CONTOSO-AZURE-DEPLOYMENT.md, step 2).
             Returns rows with Result PASS, WARN or FAIL in words; throws when any row is FAIL.
    #>
    $cfg = $script:L09Config
    $n = $cfg.names
    $sub = $cfg.subscriptionId
    $rows = [Collections.Generic.List[object]]::new()
    function Add-Row([string]$Result, [string]$Check, [string]$Detail) { $rows.Add([pscustomobject]@{ Result = $Result; Check = $Check; Detail = $Detail }) }

    # 1. The resource groups are absent, or this lesson's. AKS copies the cluster's tags to its node group.
    foreach ($g in @($cfg.resourceGroup, $n.aksNodeResourceGroup)) {
        if (Invoke-L09Az @('group', 'exists', '--name', $g)) {
            $owner = "$(Get-L09Value (Invoke-L09Az @('group', 'show', '--name', $g)) 'tags.managedby')"
            Add-Row $(if ($owner -eq $cfg.managedBy) { 'PASS' } else { 'FAIL' }) "Resource group owner: $g" "exists, tagged managedby='$owner'"
        }
        else { Add-Row 'PASS' "Resource group owner: $g" "doesn't exist yet" }
    }

    # 2. The node size is offered and not restricted for this subscription in the region. REST, not
    #    az vm list-skus: the CLI hides sizes the subscription can't use, so a restricted size looks
    #    "not offered" instead of saying why.
    $skus = Invoke-L09Rest -Path "/subscriptions/$sub/providers/Microsoft.Compute/skus?api-version=2021-07-01&`$filter=location eq '$($cfg.aksLocation)'"
    $sku = @($skus.value | Where-Object { $_.resourceType -eq 'virtualMachines' -and $_.name -eq $cfg.aksNodeSize })
    if (-not $sku.Count) { Add-Row 'FAIL' "Node size $($cfg.aksNodeSize)" "not offered in $($cfg.aksLocation)" }
    else {
        $blocked = @($sku[0].restrictions | Where-Object type -eq 'Location')
        Add-Row $(if ($blocked.Count) { 'FAIL' } else { 'PASS' }) "Node size $($cfg.aksNodeSize)" $(if ($blocked.Count) { "restricted: $(@($blocked | ForEach-Object reasonCode) -join ', ')" } else { "available in $($cfg.aksLocation) (family $($sku[0].family))" })
    }

    # 3. The node's vCPUs fit the family and regional quota, unless the cluster already exists (then
    #    its node is already counted, running or stopped).
    $clusterExists = (Invoke-L09Az -AllowFailure @('aks', 'show', '--resource-group', $cfg.resourceGroup, '--name', $n.aks, '--query', 'id')).ExitCode -eq 0
    $usage = @(Invoke-L09Az @('vm', 'list-usage', '--location', $cfg.aksLocation))
    foreach ($q in @($cfg.vmFamily, 'cores')) {
        $u = @($usage | Where-Object { $_.name.value -eq $q })
        if (-not $u) { Add-Row 'WARN' "Quota $q" 'not reported'; continue }
        $free = [int]$u[0].limit - [int]$u[0].currentValue
        $result = if ($clusterExists -or $free -ge $cfg.vcpusNeeded) { 'PASS' } else { 'FAIL' }
        Add-Row $result "Quota $q ($($cfg.aksLocation))" "$($u[0].currentValue) of $($u[0].limit) used, $($cfg.vcpusNeeded) needed$(if ($clusterExists) { '; the cluster exists, so its node is already counted' })"
    }

    # 4. Resource providers. Deploy-L09Lab.ps1 -Deploy registers the retained part's (a one-time,
    #    no-cost subscription step it reports); Deploy-L09Edge.ps1 -Deploy registers Microsoft.Cdn.
    foreach ($ns in 'Microsoft.ContainerService', 'Microsoft.Logic', 'Microsoft.App', 'Microsoft.ContainerRegistry', 'Microsoft.Web', 'Microsoft.ApiManagement', 'Microsoft.OperationalInsights', 'Microsoft.ManagedIdentity', 'Microsoft.Network', 'Microsoft.Storage', 'Microsoft.ContainerInstance', 'Microsoft.Cdn') {
        $s = Invoke-L09Az @('provider', 'show', '--namespace', $ns, '--query', 'registrationState')
        Add-Row $(if ($s -eq 'Registered') { 'PASS' } else { 'WARN' }) "Provider $ns" $(if ($s -eq 'Registered') { 'Registered' } else { "$s; the deploy script registers it with -Deploy" })
    }

    # 5. The plans the lesson shows. Set-L09DefenderWindow.ps1 -State Open turns them on 24 hours ahead.
    foreach ($plan in 'Containers', 'AppServices') {
        $p = Invoke-L09Rest -Path "/subscriptions/$sub/providers/Microsoft.Security/pricings/$plan`?api-version=2024-01-01"
        $tier = "$(Get-L09Value $p 'properties.pricingTier')"
        Add-Row $(if ($tier -eq 'Standard') { 'PASS' } else { 'WARN' }) "Defender plan $plan" $(if ($tier -eq 'Standard') { 'Standard' } else { "$tier; run Set-L09DefenderWindow.ps1 -State Open at least 24 hours before the take" })
    }

    # 6. Globally unique names: ours already, or free.
    $mine = @(Invoke-L09Graph -Query "resources | where resourceGroup =~ '$($cfg.resourceGroup)' | project name")
    $global = [ordered]@{
        $n.registry    = { (Invoke-L09Az @('acr', 'check-name', '--name', $n.registry)).nameAvailable }
        $n.storage     = { (Invoke-L09Az @('storage', 'account', 'check-name', '--name', $n.storage)).nameAvailable }
        $n.functionApp = { (Invoke-L09Rest -Method post -Path "/subscriptions/$sub/providers/Microsoft.Web/checknameavailability?api-version=2023-12-01" -Body @{ name = $n.functionApp; type = 'Microsoft.Web/sites' }).nameAvailable }
        $n.webApp      = { (Invoke-L09Rest -Method post -Path "/subscriptions/$sub/providers/Microsoft.Web/checknameavailability?api-version=2023-12-01" -Body @{ name = $n.webApp; type = 'Microsoft.Web/sites' }).nameAvailable }
        $n.apim        = { (Invoke-L09Az @('apim', 'check-name', '--name', $n.apim)).nameAvailable }
    }
    foreach ($name in $global.Keys) {
        if (@($mine | Where-Object { $_.name -eq $name }).Count) { Add-Row 'PASS' "Global name $name" "already this lab's"; continue }
        $free = & $global[$name]
        Add-Row $(if ($free) { 'PASS' } else { 'FAIL' }) "Global name $name" $(if ($free) { 'available' } else { 'taken: take the next instance number in config.json' })
    }

    # 7. Budgets are supported for this subscription's offer (a list call fails when they aren't).
    if ($cfg.budget.enabled) {
        $b = Invoke-L09Az -AllowFailure @('consumption', 'budget', 'list')
        Add-Row $(if ($b.ExitCode -eq 0) { 'PASS' } else { 'FAIL' }) 'Cost budgets' $(if ($b.ExitCode -eq 0) { 'the Consumption API answers' } else { 'the Consumption API refused; set budget.enabled to false and say why in the README' })
    }

    # 8. The lab API registration: -Deploy creates or repairs it.
    $app = Get-L09ApiApp
    Add-Row $(if ($app) { 'PASS' } else { 'WARN' }) "App registration $($cfg.apiAppDisplayName)" $(if ($app) { "present, appId $($app.appId)" } else { 'absent; -Deploy creates it' })

    # 9. Another lesson's lab may hold same-named resources in its own group. Azure allows that, but
    #    a portal picker would show both, so the runbook opens resources by full resource ID.
    $wanted = @($n.PSObject.Properties | ForEach-Object { "$($_.Value)" })
    $clash = @(Invoke-L09Graph -Query 'resources | project name, group = resourceGroup' | Where-Object { $wanted -contains $_.name -and $_.group -notin @($cfg.resourceGroup, $n.aksNodeResourceGroup) })
    Add-Row $(if ($clash.Count) { 'WARN' } else { 'PASS' }) 'Same names in other groups' $(if ($clash.Count) { @($clash | ForEach-Object { "$($_.name) in $($_.group)" }) -join '; ' } else { 'none' })

    [void](Write-L09Evidence 'preflight' $rows)
    $rows | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Out-Host
    if (@($rows | Where-Object Result -eq 'FAIL').Count) { throw 'Preflight FAILED. Nothing was validated or deployed.' }
    return $rows
}

function Register-L09Provider {
    <#
    .SYNOPSIS Registers resource providers the lab needs, one time per subscription, at no cost.
    .DESCRIPTION Prints each one it registers, so the operator sees the one subscription-level change
             a deployment makes. Already-registered providers are left alone.
    #>
    param([Parameter(Mandatory)][string[]]$Namespace)
    foreach ($ns in $Namespace) {
        $s = Invoke-L09Az @('provider', 'show', '--namespace', $ns, '--query', 'registrationState')
        if ($s -eq 'Registered') { continue }
        Write-Host "Registering the $ns resource provider (one time, subscription level, no cost)."
        Invoke-L09Az -Raw @('provider', 'register', '--namespace', $ns, '--wait') | Out-Null
        [void](Write-L09Evidence "provider-registered-$($ns.ToLower())" ([pscustomobject]@{ namespace = $ns; before = $s; after = (Invoke-L09Az @('provider', 'show', '--namespace', $ns, '--query', 'registrationState')) }))
    }
}

function Invoke-L09Http {
    <#
    .SYNOPSIS Sends one HTTP request and returns the status, reason, a short body, and the named
             response headers. Never throws on an HTTP error status; that status is the result.
    .PARAMETER Headers Request headers. Values are sent, never returned.
    #>
    param(
        [Parameter(Mandatory)][string]$Uri,
        [string]$Method = 'GET',
        [hashtable]$Headers = @{},
        [string]$Body,
        [string[]]$ShowHeaders = @(),
        [int]$TimeoutSec = 30,
        [int]$BodyChars = 240
    )
    $handler = [Net.Http.HttpClientHandler]::new(); $handler.AllowAutoRedirect = $false
    $client = [Net.Http.HttpClient]::new($handler); $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
    try {
        $req = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Method), $Uri)
        foreach ($k in $Headers.Keys) { [void]$req.Headers.TryAddWithoutValidation($k, [string]$Headers[$k]) }
        if ($PSBoundParameters.ContainsKey('Body')) { $req.Content = [Net.Http.StringContent]::new($Body, [Text.Encoding]::UTF8, 'application/json') }
        $resp = $client.SendAsync($req).GetAwaiter().GetResult()
        $text = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $text = ($text -replace '\s+', ' ').Trim()
        if ($text.Length -gt $BodyChars) { $text = $text.Substring(0, $BodyChars) + '...' }
        $shown = [ordered]@{}
        foreach ($h in $ShowHeaders) {
            $vals = $null
            if ($resp.Headers.TryGetValues($h, [ref]$vals) -or $resp.Content.Headers.TryGetValues($h, [ref]$vals)) { $shown[$h] = ($vals -join ', ') }
        }
        return [pscustomobject]@{ Status = [int]$resp.StatusCode; Reason = $resp.ReasonPhrase; Body = $text; Headers = [pscustomobject]$shown; AtUtc = [DateTime]::UtcNow.ToString('HH:mm:ss') }
    }
    catch {
        $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }
        return [pscustomobject]@{ Status = 0; Reason = 'NoResponse'; Body = $e.Message; Headers = [pscustomobject]@{}; AtUtc = [DateTime]::UtcNow.ToString('HH:mm:ss') }
    }
    finally { $client.Dispose() }
}

function Invoke-L09Kubectl {
    <#
    .SYNOPSIS Runs kubectl inside the AKS cluster through the runCommand API, as the operator's
             Microsoft Entra identity (Azure RBAC). Needs no local kubectl, kubelogin, or
             kubeconfig, and works even though the cluster has no local accounts.
    .PARAMETER Command The kubectl command line to run in the cluster.
    .PARAMETER File Local manifest files to send along; reference them by file name.
    #>
    param([Parameter(Mandatory)][string]$Command, [string[]]$File = @(), [int]$TimeoutSec = 240)
    # This calls the runCommand API directly. The Azure CLI 2.85 wrapper (az aks command invoke)
    # fails with "Operation returned an invalid status 'OK'" against this cluster, because the API
    # can answer 200 where the CLI's poller expects 202. Both tokens come from the operator's
    # existing Azure CLI sign-in: one for Resource Manager, and one for the AKS Microsoft Entra
    # server application, which the cluster needs to run the command as the operator.
    $cfg = $script:L09Config
    $arm = Invoke-L09Az -NoSubscription @('account', 'get-access-token', '--resource', 'https://management.azure.com/', '--query', 'accessToken')
    $cluster = Invoke-L09Az -NoSubscription @('account', 'get-access-token', '--resource', '6dae42f8-4368-4678-94ff-3960e28e3630', '--query', 'accessToken')
    $body = @{ command = $Command; clusterToken = $cluster }
    if ($File.Count) {
        # The API takes the files as a base64 zip, unpacked into the command's working directory.
        $zip = Join-Path ([IO.Path]::GetTempPath()) ("sc500-l09-{0}.zip" -f [guid]::NewGuid())
        Compress-Archive -Path $File -DestinationPath $zip -Force
        $body.context = [Convert]::ToBase64String([IO.File]::ReadAllBytes($zip))
        Remove-Item -LiteralPath $zip
    }
    $base = "https://management.azure.com/subscriptions/$($cfg.subscriptionId)/resourceGroups/$($cfg.resourceGroup)/providers/Microsoft.ContainerService/managedClusters/$($cfg.names.aks)"
    $client = [Net.Http.HttpClient]::new(); $client.Timeout = [TimeSpan]::FromSeconds(60)
    try {
        $client.DefaultRequestHeaders.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $arm)
        $content = [Net.Http.StringContent]::new(($body | ConvertTo-Json -Compress), [Text.Encoding]::UTF8, 'application/json')
        $resp = $client.PostAsync("$base/runCommand?api-version=2024-09-01", $content).GetAwaiter().GetResult()
        $text = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if ([int]$resp.StatusCode -ge 400) { throw "runCommand returned $([int]$resp.StatusCode): $text" }
        $result = if ($text) { $text | ConvertFrom-Json -Depth 20 } else { $null }
        $location = if ($resp.Headers.Location) { $resp.Headers.Location.AbsoluteUri } else { $null }
        $deadline = (Get-Date).AddSeconds($TimeoutSec)
        # Poll until the command reports a terminal state.
        while (-not $result -or (Get-L09Value $result 'properties.provisioningState') -notin 'Succeeded', 'Failed') {
            if ((Get-Date) -gt $deadline) { throw "runCommand didn't finish within $TimeoutSec seconds." }
            Start-Sleep -Seconds 3
            $url = if ($location) { $location } else { "$base/commandResults/$($result.id -split '/' | Select-Object -Last 1)?api-version=2024-09-01" }
            $poll = $client.GetAsync($url).GetAwaiter().GetResult()
            $ptext = $poll.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if ($ptext) { $result = $ptext | ConvertFrom-Json -Depth 20 }
        }
        return [pscustomobject]@{ ExitCode = (Get-L09Value $result 'properties.exitCode'); Logs = ([string](Get-L09Value $result 'properties.logs')).Trim(); Reason = (Get-L09Value $result 'properties.reason') }
    }
    finally { $client.Dispose() }
}

function Get-L09ResourceId([string]$Type, [string]$Name) {
    return "/subscriptions/$($script:L09Config.subscriptionId)/resourceGroups/$($script:L09Config.resourceGroup)/providers/$Type/$Name"
}
