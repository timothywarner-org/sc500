<#
.SYNOPSIS
    Read gateway diagnostics for one recorded L11 request, using its ID and bounded UTC window.
.DESCRIPTION
    A recent row is not proof of the attack being discussed. This helper uses a preserved model
    receipt, never resends the prompt, and keeps exact-ID matches separate from time-window rows.
    It saves private evidence and reports missing matches without treating an empty result as absence.
.PARAMETER RequestEvidenceFile
    A private guardrail receipt containing one Jailbreak row with apimRequestId and atUtc.
    A Mode Model receipt is accepted; other cases are excluded from the investigation query.
.PARAMETER LatestJailbreak
    Resolve the newest saved single-jailbreak receipt. The printed UTC and ID identify the case;
    this does not send another attack or claim that it belongs to a particular Defender incident.
.EXAMPLE
    ./scripts/lesson-11/Get-L11InvestigationEvidence.ps1 -RequestEvidenceFile .azure/lesson-11/evidence/20260928T154251173Z-guardrail-jailbreak.json
#>
[CmdletBinding(DefaultParameterSetName='File')]
param([Parameter(Mandatory,ParameterSetName='File')][ValidateScript({Test-Path -LiteralPath $_ -PathType Leaf})][string]$RequestEvidenceFile,
      [Parameter(Mandatory,ParameterSetName='Latest')][switch]$LatestJailbreak)
. (Join-Path $PSScriptRoot 'L11.Common.ps1')
. (Join-Path $PSScriptRoot 'L11.Checks.ps1')
[void](Assert-L11Context)
$lab = Get-L11Outputs
if ($LatestJailbreak) {
    # Resolve a saved receipt explicitly; a random recent log row is not an attack identifier.
    $latest = Get-ChildItem -LiteralPath (Join-Path $script:L11State 'evidence') -Filter '*-guardrail-jailbreak.json' |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $latest) { throw 'No saved jailbreak receipt. Run Mode Jailbreak off camera first.' }
    $RequestEvidenceFile = $latest.FullName
}
$receipt = Get-Content -LiteralPath $RequestEvidenceFile -Raw | ConvertFrom-Json -Depth 100
if ($receipt.deployment -ne $lab.deployment) { throw 'The receipt does not name the current lesson model deployment.' }
$requests = @($receipt.model.runs | Where-Object { $_.case -eq 'Jailbreak' -and $_.apimRequestId })
if ($requests.Count -ne 1) { throw 'The receipt must contain exactly one recorded Jailbreak request.' }
$request = $requests[0]
$gatewayId = Get-L11Value $request 'gatewayRequestId'
$requestId = ([guid]$(if ($gatewayId) { $gatewayId } else { $request.apimRequestId })).ToString()
$at = ConvertTo-L11UtcTime $request.atUtc
$from = $at.AddMinutes(-2).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
$to = $at.AddMinutes(2).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
$queries = [ordered]@{
    gatewayExact = "ApiManagementGatewayLogs | where TimeGenerated between (datetime($from) .. datetime($to)) | where tostring(CorrelationId) == '$requestId' | project TimeGenerated, CorrelationId, ApiId, ResponseCode, BackendResponseCode"
    llmExact = "ApiManagementGatewayLlmLog | where TimeGenerated between (datetime($from) .. datetime($to)) | where tostring(CorrelationId) == '$requestId' | project TimeGenerated, CorrelationId, SequenceNumber, DeploymentName, PromptTokens, CompletionTokens, TotalTokens"
    gatewayWindow = "ApiManagementGatewayLogs | where TimeGenerated between (datetime($from) .. datetime($to)) | where ApiId == 'servicehub-ai' | project TimeGenerated, CorrelationId, ApiId, ResponseCode, BackendResponseCode | order by TimeGenerated asc"
    llmWindow = "ApiManagementGatewayLlmLog | where TimeGenerated between (datetime($from) .. datetime($to)) | project TimeGenerated, CorrelationId, SequenceNumber, DeploymentName, PromptTokens, CompletionTokens, TotalTokens | order by TimeGenerated asc"
}
$out = [ordered]@{ capturedUtc = [DateTime]::UtcNow.ToString('o'); sourceFile = [IO.Path]::GetFullPath($RequestEvidenceFile)
    sourceSha256 = (Get-FileHash -LiteralPath $RequestEvidenceFile -Algorithm SHA256).Hash
    requestId = $requestId; requestIdKind = $(if ($gatewayId) { 'APIM gateway' } else { 'Foundry backend; legacy receipt lacks gateway ID' }); requestUtc = $request.atUtc; requestStatus = $request.status
    windowStartUtc = $from; windowEndUtc = $to; queries = $queries }
foreach ($name in $queries.Keys) {
    $result = Invoke-L11Az -AllowFailure @('monitor','log-analytics','query','--workspace',$lab.workspaceCustomerId,
        '--analytics-query',$queries[$name],'--timespan',"$from/$to")
    $out[$name] = if ($result.ExitCode -eq 0) { @($result.Stdout | ConvertFrom-Json) } else { @{error=$result.Stderr.Trim()} }
    Write-Host "$name for request $requestId at $($request.atUtc):"
    $out[$name] | Format-Table -AutoSize | Out-String -Width 180 | Out-Host
}
$out['exactGatewayMatch'] = @($out.gatewayExact | Where-Object { $_.PSObject.Properties['CorrelationId'] -and $_.CorrelationId -eq $requestId }).Count -gt 0
$out['exactLlmMatch'] = @($out.llmExact | Where-Object { $_.PSObject.Properties['CorrelationId'] -and $_.CorrelationId -eq $requestId }).Count -gt 0
$out['boundary'] = 'Exact IDs join the request and gateway logs only. Link the Defender alert by provider evidence or explicit resource/time fields; XDR and Sentinel require their own observed records.'
[void](Write-L11Evidence 'investigation-correlation' $out)
if (-not $out.exactGatewayMatch) { Write-Warning 'No exact gateway ID match. Window rows are candidates, not proven correlation.' }
