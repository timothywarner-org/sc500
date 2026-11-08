<#
.SYNOPSIS
    Build pinned prompt-agent requests and preserve bounded, credential-free evidence.
.DESCRIPTION
    Dot-source after L11.Common.ps1. A named agent can change between calls, so every request
    pins its version. Filter results and actual tool output distinguish a block from a skipped tool.
#>
function New-L11AgentRequest {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$Prompt)
    return @{ input = $Prompt; agent_reference = @{ name = $Name; type = 'agent_reference'; version = $Version } }
}

function Get-L11AgentTrace {
    param([Parameter(Mandatory)]$Response, [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$Part, [int]$Attempt = 1)
    $items = @(@(Get-L11Value $Response.Body 'output') | Where-Object { $null -ne $_ })
    $scans = @(@(Get-L11Value $Response.Body 'content_filters') | Where-Object { $null -ne $_ } | ForEach-Object {
        [pscustomobject]@{ source = Get-L11Value $_ 'source_type'; blocked = Get-L11Value $_ 'blocked'
            results = Get-L11FilterSummary (Get-L11Value $_ 'content_filter_results') }
    })
    $output = @($items | ForEach-Object {
        $item = $_
        $safe = [ordered]@{}
        foreach ($field in @('id','type','call_id','name','status','arguments','output','content')) {
            $value = Get-L11Value $item $field
            if ($null -ne $value) { $safe[$field] = $value }
        }
        $json = $safe | ConvertTo-Json -Depth 20 -Compress
        [pscustomobject]@{ type = Get-L11Value $item 'type'; truncated = ($json.Length -gt 32768)
            details = $json.Substring(0, [Math]::Min(32768,$json.Length)) }
    })
    $post = @($scans | Where-Object { $_.source -match '^post_tool' })
    return [pscustomobject]@{ part = $Part; attempt = $Attempt; atUtc = $Response.AtUtc; http = $Response.Status
        requestedAgentVersion = $Version; responseAgentVersion = Get-L11Value $Response.Body 'agent_reference.version'
        responseId = Get-L11Value $Response.Body 'id'; status = Get-L11Value $Response.Body 'status'
        error = Get-L11Value $Response.Body 'error.code'; incomplete = Get-L11Value $Response.Body 'incomplete_details.reason'
        outputTypes = (@($items | ForEach-Object { Get-L11Value $_ 'type' }) -join ', ')
        toolCallObserved = [bool]@($items | Where-Object { (Get-L11Value $_ 'type') -match 'openapi.*call|tool.*call' }).Count
        scannedAt = (@($scans | ForEach-Object { "$($_.source)$(if ($_.blocked) { '(blocked)' })" }) -join ', ')
        toolResponseScanned = ($post.Count -gt 0); toolResponseBlocked = [bool]@($post | Where-Object blocked).Count
        scans = $scans; output = $output }
}

function Invoke-L11PinnedAgentCase {
    param([Parameter(Mandatory)][string]$Version, [Parameter(Mandatory)][string]$Part,
        [Parameter(Mandatory)]$Lab, [Parameter(Mandatory)]$Config, [int]$Attempt = 1)
    $token = Get-L11Token 'https://ai.azure.com'
    $prompt = "Is part $Part in stock, and what does the supplier note say?"
    try {
        $response = Invoke-L11Http -Uri "$($Lab.projectEndpoint)/openai/v1/responses" -Headers @{Authorization="Bearer $token"} -TimeoutSec 180 -Body (New-L11AgentRequest -Name $Config.names.agent -Version $Version -Prompt $prompt)
    } finally { $token = $null }
    $trace = Get-L11AgentTrace -Response $response -Version $Version -Part $Part -Attempt $Attempt
    Write-Host ("  {0} version {1}: HTTP {2}; tool observed={3}; scans [{4}]; response {5}" -f $Part,$Version,$trace.http,$trace.toolCallObserved,$trace.scannedAt,$trace.responseId)
    # These are this fixture's fictional tool results, not headers or authentication state.
    foreach ($item in @($trace.output | Where-Object type -eq 'openapi_call_output')) {
        Write-Host ("    tool output: {0}" -f $item.details.Substring(0,[Math]::Min(1200,$item.details.Length)))
    }
    foreach ($scan in @($trace.scans | Where-Object source -match '^post_tool')) {
        Write-Host ("    filter results: {0}" -f ($scan.results | ConvertTo-Json -Depth 8 -Compress))
    }
    return $trace
}
