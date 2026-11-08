<#
.SYNOPSIS
    SC-500 demo 11.1: prove ServiceHub's model is reachable only through the AI gateway, and that
    the gateway enforces a token budget per caller.
.DESCRIPTION
    Modes (each saves a dated evidence file under lab/.azure/lesson-11/evidence/):
      Direct   Call the Foundry deployment directly, first with a Foundry key, then with your own
               Microsoft Entra token. Expected: the key is refused because key auth is disabled.
               The token result depends on your data roles and is recorded exactly as returned.
      Gateway  Call through API Management with no subscription key (expected 401), then with the
               servicehub-assistant key (expected 200). Records the remaining-token header.
      Burst    Send short requests back to back until the tokens-per-minute budget returns 429,
               record Retry-After, wait, and confirm the next call succeeds again.
      Logs     Query the workspace for the gateway's request log and LLM token log (ingestion
               usually lags 5 to 15 minutes, so run this after the others).
      All      Direct, Gateway, and Burst in order (not Logs).
    No key or token is printed or saved. The only prompt text is a benign ServiceHub question.
.PARAMETER Mode Direct, Gateway, Burst, Logs, or All.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-11\Invoke-L11GatewayDemo.ps1 -Mode All
#>
[CmdletBinding()]
param([ValidateSet('Direct', 'Gateway', 'Burst', 'Logs', 'All')][string]$Mode = 'All')
. (Join-Path $PSScriptRoot 'L11.Common.ps1')
$cfg = $script:L11Config
[void](Assert-L11Context)
$lab = Get-L11Outputs
$dep = $lab.deployment
$question = 'In two sentences, how should a technician prepare to replace a pump pressure valve?'
$body = @{ messages = @(@{ role = 'system'; content = 'You are the Contoso ServiceHub maintenance assistant. Answer briefly.' },
                        @{ role = 'user'; content = $question }); max_tokens = 120 }
function Short($r) {
    $err = Get-L11Value $r.Body 'error'
    $msg = if ($err) { "$(Get-L11Value $err 'code'): $(Get-L11Value $err 'message')" } elseif (Get-L11Value $r.Body 'statusCode') { "$($r.Body.statusCode): $($r.Body.message)" }
           else { $c = Get-L11Value $r.Body 'choices'; if ($c) { (@($c)[0].message.content -split "`n")[0] } else { $r.Text.Substring(0, [Math]::Min(160, $r.Text.Length)) } }
    return ($msg -replace '\s+', ' ').Trim()
}

if ($Mode -in 'Direct', 'All') {
    Write-Host '== Direct to Foundry, no gateway'
    $direct = "$($lab.openAiEndpoint)openai/deployments/$dep/chat/completions?api-version=$script:L11ChatApiVersion"
    # A Foundry key: read it the way an attacker with management rights would try to.
    $keys = Invoke-L11Az -AllowFailure @('cognitiveservices', 'account', 'keys', 'list', '--resource-group', $cfg.resourceGroup, '--name', $lab.foundry)
    $keyResult = $null
    if ($keys.ExitCode -eq 0) {
        $k = ($keys.Stdout | ConvertFrom-Json).key1
        $r = Invoke-L11Http -Uri $direct -Headers @{ 'api-key' = $k } -Body $body
        $keyResult = [ordered]@{ listKeys = 'returned keys'; status = $r.Status; result = (Short $r); atUtc = $r.AtUtc }
        $k = $null
    } else {
        $keyResult = [ordered]@{ listKeys = (($keys.Stderr -split "`n")[0]).Trim(); status = $null; result = 'no key to try'; atUtc = [DateTime]::UtcNow.ToString('o') }
    }
    Write-Host ("  key:   listKeys -> {0}; call -> {1} {2}" -f $keyResult.listKeys, $keyResult.status, $keyResult.result)
    $t = Get-L11Token 'https://cognitiveservices.azure.com'
    $r = Invoke-L11Http -Uri $direct -Headers @{ Authorization = "Bearer $t" } -Body $body
    $t = $null
    # Which data roles let this token in? Every assignment at or above the Foundry resource counts.
    $me = Invoke-L11Az -NoSubscription @('ad', 'signed-in-user', 'show', '--query', 'id', '--output', 'tsv') -Raw
    $dataRoles = @(Invoke-L11Az @('role', 'assignment', 'list', '--assignee', $me, '--all', '--query',
        "[?roleDefinitionName=='Foundry User' || roleDefinitionName=='Cognitive Services OpenAI User' || roleDefinitionName=='Cognitive Services OpenAI Contributor' || roleDefinitionName=='Cognitive Services User' || roleDefinitionName=='Foundry Owner' || roleDefinitionName=='Foundry Account Owner'].{role:roleDefinitionName,scope:scope}") |
        Where-Object { $lab.foundryId -like "$($_.scope)*" -or $_.scope -like "$($lab.foundryId)*" } | ForEach-Object { "$($_.role) at $(($_.scope -split '/')[-2..-1] -join '/')" })
    $tokenResult = [ordered]@{ caller = $cfg.operatorUpn; dataRoles = $dataRoles; status = $r.Status; result = (Short $r); atUtc = $r.AtUtc }
    Write-Host ("  data roles that apply: {0}" -f ($dataRoles -join '; '))
    Write-Host ("  token: {0} -> {1} {2}" -f $cfg.operatorUpn, $tokenResult.status, $tokenResult.result)
    [void](Write-L11Evidence 'gateway-direct' ([ordered]@{ endpoint = 'Foundry resource, Azure OpenAI surface'; deployment = $dep; key = $keyResult; token = $tokenResult }))
}

$gw = $null; $key = $null
if ($Mode -in 'Gateway', 'Burst', 'All') {
    $gw = Get-L11GatewayOutputs
    if (-not $gw) { throw 'The gateway is not deployed. Run Deploy-L11Lab.ps1 -Gateway first (Basic v2 bills by the hour).' }
    $key = Get-L11SubscriptionKey $gw
    $viaGateway = "$($gw.gatewayUrl)/$($gw.llmApiPath)/deployments/$dep/chat/completions?api-version=$script:L11ChatApiVersion"
}

if ($Mode -in 'Gateway', 'All') {
    Write-Host '== Through the AI gateway'
    $noKey = Invoke-L11Http -Uri $viaGateway -Body $body
    Write-Host ("  no subscription key -> {0} {1}" -f $noKey.Status, (Short $noKey))
    $ok = Invoke-L11Http -Uri $viaGateway -Headers @{ 'api-key' = $key } -Body $body
    Write-Host ("  servicehub-assistant key -> {0} {1}" -f $ok.Status, (Short $ok))
    Write-Host ("  headers: {0}" -f (($ok.Headers.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '; '))
    $usage = Get-L11Value $ok.Body 'usage'
    [void](Write-L11Evidence 'gateway-call' ([ordered]@{
        gateway = $gw.apim; api = $gw.llmApiPath; deployment = $dep
        noKey = [ordered]@{ status = $noKey.Status; result = (Short $noKey); atUtc = $noKey.AtUtc }
        withKey = [ordered]@{ status = $ok.Status; result = (Short $ok); atUtc = $ok.AtUtc; headers = $ok.Headers
                              promptTokens = (Get-L11Value $usage 'prompt_tokens'); completionTokens = (Get-L11Value $usage 'completion_tokens')
                              model = (Get-L11Value $ok.Body 'model') } }))
}

if ($Mode -in 'Burst', 'All') {
    Write-Host ("== Token budget: {0} tokens per minute per subscription" -f $cfg.gateway.tokensPerMinute)
    $rows = @()
    foreach ($i in 1..12) {
        $r = Invoke-L11Http -Uri $viaGateway -Headers @{ 'api-key' = $key } -Body $body
        $rem = $r.Headers[$cfg.gateway.remainingTokensHeader]
        $row = [ordered]@{ n = $i; status = $r.Status; remaining = $rem; consumed = $r.Headers['x-ctso-tokens-consumed']; retryAfter = $r.Headers['Retry-After']; atUtc = $r.AtUtc }
        $rows += [pscustomobject]$row
        Write-Host ("  call {0,2}: {1} remaining={2} consumed={3} retry-after={4}" -f $i, $r.Status, $rem, $row.consumed, $row.retryAfter)
        if ($r.Status -eq 429) { break }
    }
    $hit = $rows | Where-Object status -eq 429 | Select-Object -First 1
    $recovery = $null
    if ($hit) {
        $wait = [int]([double]($hit.retryAfter | ForEach-Object { if ($_) { $_ } else { 60 } })) + 2
        Write-Host "  waiting $wait seconds, as Retry-After asks"
        Start-Sleep -Seconds $wait
        $r = Invoke-L11Http -Uri $viaGateway -Headers @{ 'api-key' = $key } -Body $body
        $recovery = [ordered]@{ status = $r.Status; waitedSeconds = $wait; atUtc = $r.AtUtc }
        Write-Host ("  after the wait: {0}" -f $r.Status)
    } else { Write-Warning 'No 429 in 12 calls. Lower gateway.tokensPerMinute in config.json and redeploy the gateway.' }
    [void](Write-L11Evidence 'gateway-burst' ([ordered]@{ tokensPerMinute = $cfg.gateway.tokensPerMinute; calls = $rows; first429 = $hit; recovery = $recovery }))
}
$key = $null

if ($Mode -eq 'Logs') {
    Write-Host '== Workspace: gateway requests and LLM token log, last 3 hours'
    $q1 = 'ApiManagementGatewayLogs | where TimeGenerated > ago(3h) | summarize calls=count(), lastSeen=max(TimeGenerated) by ApiId, ResponseCode | order by ApiId asc, ResponseCode asc'
    $q2 = 'ApiManagementGatewayLlmLog | where TimeGenerated > ago(3h) | where SequenceNumber == 0 or isnull(SequenceNumber) | summarize calls=count(), prompt=sum(PromptTokens), completion=sum(CompletionTokens), lastSeen=max(TimeGenerated) by DeploymentName, ModelName'
    $q3 = 'ApiManagementGatewayLlmLog | where TimeGenerated > ago(3h) | project TimeGenerated, CorrelationId, PromptTokens, CompletionTokens, TotalTokens | order by TimeGenerated desc | take 3'
    $out = [ordered]@{}
    foreach ($pair in @(@('requests', $q1), @('llmTokens', $q2), @('llmLatest', $q3))) {
        $r = Invoke-L11Az -AllowFailure @('monitor', 'log-analytics', 'query', '--workspace', $lab.workspaceCustomerId, '--analytics-query', $pair[1])
        $out[$pair[0]] = if ($r.ExitCode -eq 0) { $r.Stdout | ConvertFrom-Json } else { "query failed: $((($r.Stderr -split "`n")[0]).Trim())" }
        Write-Host "  $($pair[0]):"; $out[$pair[0]] | Format-Table -AutoSize | Out-String -Width 200 | Out-Host
    }
    [void](Write-L11Evidence 'gateway-logs' $out)
}
