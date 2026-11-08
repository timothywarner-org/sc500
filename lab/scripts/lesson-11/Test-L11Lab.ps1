<#
.SYNOPSIS
    Readiness check for the SC-500 Lesson 11 lab (CTSO-L11-BASELINE). Read-only.
.DESCRIPTION
    Checks what the demos depend on and prints PASS, WARN, or FAIL for each:
      - the Foundry resource refuses keys (disableLocalAuth) and the project exists
      - the blocklist holds the customer-ID pattern
      - the guardrail blocks jailbreak on input, indirect attack on input and tool response,
        the harm categories, and the blocklist in both directions
      - the model deployment carries the guardrail
      - You hold Foundry User on the project (needed to build and call the agent)
      - resource logs from the Foundry resource go to the lesson workspace
      - Defender for AI Services is on for the subscription, and on the Foundry resource itself
      - the gateway, if deployed: its identity's role on Foundry and the servicehub-ai API
    Baseline permits a removed gateway. Recording requires the actual API, policy, and enabled
    gateway diagnostics. Neither scope proves runtime enforcement or measured delivery.
.PARAMETER Scope
    Baseline checks retained resources. Recording also requires the bounded demo gateway.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-11\Test-L11Lab.ps1
#>
[CmdletBinding()]
param([ValidateSet('Baseline','Recording')][string]$Scope = 'Baseline')
. (Join-Path $PSScriptRoot 'L11.Common.ps1')
. (Join-Path $PSScriptRoot 'L11.Checks.ps1')
$cfg = $script:L11Config
[void](Assert-L11Context)
$lab = Get-L11Outputs
$results = [System.Collections.Generic.List[object]]::new()
function Check([string]$Name, [bool]$Ok, [string]$Detail, [switch]$WarnOnly) {
    $state = if ($Ok) { 'PASS' } elseif ($WarnOnly) { 'WARN' } else { 'FAIL' }
    $results.Add([pscustomobject]@{ check = $Name; result = $state; detail = $Detail })
    Write-Host ("  {0}  {1}: {2}" -f $state, $Name, $Detail)
}
$acct = Invoke-L11Rest -Path "$($lab.foundryId)?api-version=2025-06-01"
Check 'Keys refused' ([bool](Get-L11Value $acct 'properties.disableLocalAuth')) "disableLocalAuth=$(Get-L11Value $acct 'properties.disableLocalAuth')"
$proj = Invoke-L11Rest -AllowNotFound -Path "$($lab.foundryId)/projects/$($cfg.names.project)?api-version=2025-06-01"
Check 'Project' ($null -ne $proj) "$($cfg.names.project) $(Get-L11Value $proj 'properties.provisioningState')"

$items = Invoke-L11Rest -AllowNotFound -Path "$($lab.foundryId)/raiBlocklists/$($cfg.names.blocklist)/raiBlocklistItems?api-version=2026-07-01"
$patterns = @(@(Get-L11Value $items 'value') | Where-Object { $_ } | ForEach-Object { "$($_.properties.pattern) regex=$($_.properties.isRegex)" })
Check 'Blocklist' ($patterns -contains 'CTSO-CUST-[0-9]{6} regex=True') ($patterns -join '; ')

$g = Invoke-L11Rest -AllowNotFound -Path "$($lab.foundryId)/raiPolicies/$($cfg.names.guardrail)?api-version=2026-07-01"
$f = @(Get-L11Value $g 'properties.contentFilters')
function Has([string]$n, [string]$src) { [bool]($f | Where-Object { $_.name -eq $n -and $_.source -eq $src -and $_.blocking -and $_.enabled }) }
Check 'Guardrail: jailbreak on input' (Has 'Jailbreak' 'Prompt') 'Jailbreak, Prompt, blocking'
Check 'Guardrail: indirect attack on input' (Has 'Indirect Attack' 'Prompt') 'Indirect Attack, Prompt, blocking'
Check 'Guardrail: indirect attack on tool response' (Has 'Indirect Attack' 'PostToolCall') 'Indirect Attack, PostToolCall, blocking'
$harmOk = Test-L11HarmFilters -Filters $f
Check 'Guardrail: harm categories both ways' $harmOk 'Hate, Sexual, Selfharm, Violence at Medium'
$bl = @(Get-L11Value $g 'properties.customBlocklists') | Where-Object { $_.blocklistName -eq $cfg.names.blocklist -and $_.blocking }
Check 'Guardrail: blocklist both ways' ((@($bl.source) -contains 'Prompt') -and (@($bl.source) -contains 'Completion')) (@($bl.source) -join ', ')

$d = Invoke-L11Rest -AllowNotFound -Path "$($lab.foundryId)/deployments/$($cfg.names.modelDeployment)?api-version=2025-06-01"
Check 'Deployment carries the guardrail' ((Get-L11Value $d 'properties.raiPolicyName') -eq $cfg.names.guardrail) "$($cfg.names.modelDeployment): raiPolicyName=$(Get-L11Value $d 'properties.raiPolicyName')"

$me = Invoke-L11Az -NoSubscription @('ad', 'signed-in-user', 'show', '--query', 'id', '--output', 'tsv') -Raw
$ra = Invoke-L11Az @('role', 'assignment', 'list', '--assignee', $me, '--scope', "$($lab.foundryId)/projects/$($cfg.names.project)", '--query', "[?roleDefinitionName=='Foundry User'].id")
Check 'Operator role on project' (@($ra).Count -ge 1) 'Foundry User'

$diag = Invoke-L11Rest -Path "$($lab.foundryId)/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview"
Check 'Foundry logs to workspace' (Test-L11LogDestination -Settings @($diag.value) -WorkspaceId $lab.workspaceId -Categories @('Audit','RequestResponse','Trace')) "$($lab.workspace): Audit, RequestResponse, Trace enabled"

$ai = Invoke-L11Rest -Path "/subscriptions/$($cfg.subscriptionId)/providers/Microsoft.Security/pricings/AI?api-version=2024-01-01"
Check 'Defender for AI Services plan' ($ai.properties.pricingTier -eq 'Standard') "pricingTier=$($ai.properties.pricingTier)"
# The plan alone isn't enough: on 2026-09-28 this resource's own setting was created Disabled and no
# AI alert arrived while it stayed that way. foundry.bicep now sets it; this confirms it held.
$dfa = Invoke-L11Rest -AllowNotFound -Path "$($lab.foundryId)/defenderForAISettings/Default?api-version=2025-06-01"
Check 'Defender for AI on the Foundry resource' ((Get-L11Value $dfa 'properties.state') -eq 'Enabled') "Default=$(Get-L11Value $dfa 'properties.state')"

$gw = Get-L11GatewayOutputs
if ($gw) {
    $gra = Invoke-L11Az @('role', 'assignment', 'list', '--assignee', $gw.principalId, '--scope', $lab.foundryId, '--query', "[?roleDefinitionName=='Cognitive Services OpenAI User'].id")
    Check 'Gateway identity role on Foundry' (@($gra).Count -ge 1) 'Cognitive Services OpenAI User'
    Check 'Gateway deployed' $true "$($gw.apim) (billing 0.21 USD an hour until Reset-L11Lab.ps1 removes it)"
    $apiPath = "$($gw.apimId)/apis/servicehub-ai"
    $api = Invoke-L11Rest -AllowNotFound -Path "$($apiPath)?api-version=2024-05-01"
    Check 'Gateway model API' (Test-L11GatewayApi -Api $api -ExpectedPath $cfg.names.llmApiPath) 'servicehub-ai requires its subscription key over HTTPS'
    # Invoke-L11Rest explicitly requests the JSON policy envelope through its Accept header.
    $policy = Invoke-L11Rest -AllowNotFound -Path "$apiPath/policies/policy?api-version=2024-05-01"
    Check 'Gateway model policy' (Test-L11GatewayPolicy -PolicyXml (Get-L11Value $policy 'properties.value') -TokensPerMinute $cfg.gateway.tokensPerMinute -RemainingHeader $cfg.gateway.remainingTokensHeader) 'backend, managed identity, key removal and exact token budget'
    $gd = Invoke-L11Rest -Path "$($gw.apimId)/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview"
    Check 'Gateway diagnostic categories' (Test-L11LogDestination -Settings @($gd.value) -WorkspaceId $lab.workspaceId -Categories @('GatewayLogs','GatewayLlmLogs')) 'GatewayLogs and GatewayLlmLogs enabled to the lesson workspace'
    $ad = Invoke-L11Rest -AllowNotFound -Path "$apiPath/diagnostics/azuremonitor?api-version=2024-05-01"
    Check 'Gateway LLM logging' ((Get-L11Value $ad 'properties.largeLanguageModel.logs') -eq 'enabled' -and (Get-L11Value $ad 'properties.sampling.percentage') -eq 100) 'LLM logging enabled, sampling 100 percent'
} else {
    Check 'Gateway deployed' $false "Scope=$Scope; gateway absent. Deploy before a live take." -WarnOnly:((Get-L11GatewayAbsenceState $Scope) -eq 'WARN')
}

[void]($results | ForEach-Object { $_ | Add-Member -NotePropertyName scope -NotePropertyValue $Scope })
[void](Write-L11Evidence 'readiness' $results)
$fails = @($results | Where-Object result -eq 'FAIL').Count
Write-Host ("{0} checks: {1} pass, {2} warn, {3} fail." -f $results.Count, @($results | Where-Object result -eq 'PASS').Count, @($results | Where-Object result -eq 'WARN').Count, $fails)
if ($fails) { exit 1 }
