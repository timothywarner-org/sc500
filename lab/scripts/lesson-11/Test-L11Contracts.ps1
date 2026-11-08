<#
.SYNOPSIS
    Offline regression cases for L11 recording assertions and agent evidence.
.DESCRIPTION
    Mutates representative service responses to prove that the reviewed false-pass conditions
    fail. No Azure call, sign-in, deployment or model inference is performed.
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L11.Common.ps1')
. (Join-Path $PSScriptRoot 'L11.Checks.ps1')
. (Join-Path $PSScriptRoot 'L11.AgentEvidence.ps1')
$count = 0
function Assert-Contract([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "Regression failed: $Name" }
    $script:count++
    Write-Host "PASS $Name"
}
$utcText='2026-09-28T15:42:49.841Z'
$utcObject=('{"atUtc":"' + $utcText + '"}' | ConvertFrom-Json).atUtc
Assert-Contract ((ConvertTo-L11UtcTime $utcText).ToString('yyyy-MM-ddTHH:mm:ss.fffZ') -eq $utcText) 'UTC string retains offset and milliseconds'
Assert-Contract ((ConvertTo-L11UtcTime $utcObject).ToString('yyyy-MM-ddTHH:mm:ss.fffZ') -eq $utcText) 'JSON DateTime retains offset and milliseconds'
$policy = (Get-Content (Join-Path $script:L11Infra 'policies/llm-api.xml') -Raw).Replace('__TPM__','400').Replace('__REMAINING_HEADER__','x-ctso-remaining-tokens')
Assert-Contract (Test-L11GatewayPolicy $policy 400 'x-ctso-remaining-tokens') 'Valid gateway policy'
Assert-Contract (-not (Test-L11GatewayPolicy ($policy.Replace('tokens-per-minute="400"','tokens-per-minute="900"')) 400 'x-ctso-remaining-tokens')) 'Wrong token budget rejected'
Assert-Contract (-not (Test-L11GatewayPolicy ($policy.Replace('https://cognitiveservices.azure.com','https://graph.microsoft.com')) 400 'x-ctso-remaining-tokens')) 'Wrong backend token audience rejected'
Assert-Contract (-not (Test-L11GatewayPolicy '<invalid' 400 'x-ctso-remaining-tokens')) 'Malformed policy rejected'
Assert-Contract (-not (Test-L11GatewayPolicy '' 400 'x-ctso-remaining-tokens')) 'Missing policy rejected'
Assert-Contract (-not (Test-L11GatewayPolicy ($policy.Replace('x-ctso-gateway-request-id','wrong-header')) 400 'x-ctso-remaining-tokens')) 'Missing gateway correlation header rejected'
$api = [pscustomobject]@{properties=[pscustomobject]@{path='servicehub-ai'; subscriptionRequired=$true; protocols=@('https'); subscriptionKeyParameterNames=@{header='api-key'}}}
Assert-Contract (Test-L11GatewayApi $api 'servicehub-ai') 'Configured API accepted'
Assert-Contract (-not (Test-L11GatewayApi $null 'servicehub-ai')) 'Missing API rejected'
$api.properties.subscriptionRequired=$false
Assert-Contract (-not (Test-L11GatewayApi $api 'servicehub-ai')) 'Anonymous model API rejected'
$filters = @(foreach ($risk in @('Hate','Sexual','Selfharm','Violence')) {
    foreach ($direction in @('Prompt','Completion')) { [pscustomobject]@{name=$risk;source=$direction;enabled=$true;blocking=$true;severityThreshold='Medium'} }
})
Assert-Contract (Test-L11HarmFilters $filters) 'Medium filters accepted'
$filters[0].severityThreshold='High'
Assert-Contract (-not (Test-L11HarmFilters $filters)) 'Wrong harm threshold rejected'
$filters[0].severityThreshold='Medium'; $filters[1].blocking=$false
Assert-Contract (-not (Test-L11HarmFilters $filters)) 'Annotate-only harm filter rejected'
$logs = @([pscustomobject]@{properties=[pscustomobject]@{workspaceId='course-workspace';logs=@(
    [pscustomobject]@{category='GatewayLogs';enabled=$true},
    [pscustomobject]@{category='GatewayLlmLogs';enabled=$true})}})
Assert-Contract (Test-L11LogDestination $logs 'course-workspace' @('GatewayLogs','GatewayLlmLogs')) 'Both log categories accepted'
$logs[0].properties.logs[1].enabled=$false
Assert-Contract (-not (Test-L11LogDestination $logs 'course-workspace' @('GatewayLogs','GatewayLlmLogs'))) 'Disabled LLM log rejected'
$logs[0].properties.logs=@([pscustomobject]@{categoryGroup='allLogs';enabled=$true})
Assert-Contract (Test-L11LogDestination $logs 'course-workspace' @('GatewayLogs','GatewayLlmLogs')) 'Enabled allLogs accepted'
Assert-Contract (-not (Test-L11LogDestination $logs 'different-workspace' @('GatewayLogs'))) 'Wrong workspace rejected'
Assert-Contract ((Get-L11GatewayAbsenceState Recording) -eq 'FAIL') 'Missing gateway fails recording'
Assert-Contract ((Get-L11GatewayAbsenceState Baseline) -eq 'WARN') 'Removed gateway remains valid baseline warning'
$request=New-L11AgentRequest -Name 'servicehub-assistant' -Version '5' -Prompt 'Read fictional part X-900.'
Assert-Contract ($request.agent_reference.version -eq '5') 'Agent request pins its exact version'
$response=[pscustomobject]@{AtUtc='2026-09-28T15:00:00Z';Status=200;Body=[pscustomobject]@{
    id='response-fixture';status='completed';agent_reference=@{version='5'}
    output=@([pscustomobject]@{type='openapi_call';id='call-fixture';output='{"part":"X-900","note":"synthetic"}'})
    content_filters=@([pscustomobject]@{source_type='prompt';blocked=$true;content_filter_results=@{}})}}
$trace=Get-L11AgentTrace $response '5' 'X-900'
Assert-Contract (-not $trace.toolResponseBlocked) 'Prompt block does not count as a tool-response block'
Assert-Contract ($trace.responseId -eq 'response-fixture' -and $trace.requestedAgentVersion -eq '5' -and $trace.toolCallObserved -and $trace.output[0].details -match 'synthetic') 'Trace retains response, version and actual tool output'
$response.Body.content_filters=@([pscustomobject]@{source_type='post_tool';blocked=$true;content_filter_results=@{indirect_attack=@{filtered=$true;detected=$true}}})
$trace=Get-L11AgentTrace $response '5' 'X-900'
Assert-Contract ($trace.toolResponseBlocked -and $trace.toolResponseScanned) 'Post-tool block counted precisely'
$response.Body.output=@()
$trace=Get-L11AgentTrace $response '5' 'X-900'
Assert-Contract (-not $trace.toolCallObserved) 'Absent tool output stays unobserved'
Assert-Contract ((Get-L11OutputBlockOutcome 'stop' 'CTSO-CUST-123456' '') -like 'ENFORCEMENT GAP*') 'Returned matching ID cannot pass as a block'
Assert-Contract ((Get-L11OutputBlockOutcome 'content_filter' '' 'ctso-customer-ids filtered=True') -eq 'BLOCK OBSERVED') 'Named output block accepted'
Assert-Contract ((Get-L11OutputBlockOutcome 'stop' 'I cannot answer' '') -like 'BLOCK NOT ESTABLISHED*') 'Model refusal is not blocklist evidence'
Write-Host "$count offline regression cases passed. No live behavior is implied."
