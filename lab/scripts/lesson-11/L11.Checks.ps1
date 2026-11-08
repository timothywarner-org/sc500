<#
.SYNOPSIS
    Pure Lesson 11 contract checks, shared by live readiness and offline regression cases.
.DESCRIPTION
    These functions inspect supplied service responses. They never authenticate or change Azure.
    Keeping assertions separate lets a disabled log or incorrect threshold fail before recording.
#>
function ConvertTo-L11UtcTime {
    param([Parameter(Mandatory)]$Value)
    # ConvertFrom-Json may already produce DateTime. Stringifying it discards Z and milliseconds.
    if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
    if ($Value -is [datetimeoffset]) { return $Value.UtcDateTime }
    return [DateTimeOffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal).UtcDateTime
}

function Test-L11HarmFilters {
    param([object[]]$Filters)
    foreach ($risk in @('Hate','Sexual','Selfharm','Violence')) {
        foreach ($direction in @('Prompt','Completion')) {
            if (-not @($Filters | Where-Object { $_.name -eq $risk -and $_.source -eq $direction -and
                $_.enabled -eq $true -and $_.blocking -eq $true -and $_.severityThreshold -eq 'Medium' }).Count) {
                return $false
            }
        }
    }
    return $true
}

function Test-L11LogDestination {
    param([object[]]$Settings, [string]$WorkspaceId, [string[]]$Categories)
    foreach ($category in $Categories) {
        $found = $false
        foreach ($setting in $Settings) {
            if ($setting.properties.workspaceId -ne $WorkspaceId) { continue }
            foreach ($log in $setting.properties.logs) {
                # allLogs legitimately includes the named category; an empty destination does not.
                $cat = if ($log.PSObject.Properties['category']) { $log.category } else { $null }
                $group = if ($log.PSObject.Properties['categoryGroup']) { $log.categoryGroup } else { $null }
                if ($log.enabled -eq $true -and ($cat -eq $category -or $group -eq 'allLogs')) { $found = $true }
            }
        }
        if (-not $found) { return $false }
    }
    return $true
}

function Test-L11GatewayPolicy {
    param([string]$PolicyXml, [int]$TokensPerMinute, [string]$RemainingHeader)
    if ([string]::IsNullOrWhiteSpace($PolicyXml)) { return $false }
    try {
        # Refuse DTDs because policy inspection does not need external XML resources.
        $settings = [Xml.XmlReaderSettings]::new()
        $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
        $reader = [Xml.XmlReader]::Create([IO.StringReader]::new($PolicyXml), $settings)
        $doc = [Xml.XmlDocument]::new()
        try { $doc.Load($reader) } finally { $reader.Dispose() }
        $mi = $doc.SelectSingleNode('/policies/inbound/authentication-managed-identity')
        $limit = $doc.SelectSingleNode('/policies/inbound/llm-token-limit')
        $drop = $doc.SelectSingleNode('/policies/inbound/set-header[@name="api-key"]')
        $backend = $doc.SelectSingleNode('/policies/inbound/set-backend-service')
        if (-not $mi -or -not $limit -or -not $drop -or -not $backend) { return $false }
        # Both success and policy-error responses must carry the gateway ID used in the logs.
        foreach ($stage in @('outbound','on-error')) {
            $header = $doc.SelectSingleNode("/policies/$stage/set-header[@name='x-ctso-gateway-request-id']")
            if (-not $header -or $header.GetAttribute('exists-action') -ne 'override' -or
                $header.InnerText.Trim() -ne '@(context.RequestId.ToString())') { return $false }
        }
        return ($mi.GetAttribute('resource') -eq 'https://cognitiveservices.azure.com' -and
            $mi.GetAttribute('ignore-error') -ne 'true' -and
            $limit.GetAttribute('tokens-per-minute') -eq [string]$TokensPerMinute -and
            $limit.GetAttribute('counter-key') -eq '@(context.Subscription.Id)' -and
            $limit.GetAttribute('estimate-prompt-tokens') -eq 'true' -and
            $limit.GetAttribute('remaining-tokens-header-name') -eq $RemainingHeader -and
            $drop.GetAttribute('exists-action') -eq 'delete' -and
            $backend.GetAttribute('backend-id') -eq 'foundry-openai')
    } catch { return $false }
}

function Test-L11GatewayApi {
    param($Api, [string]$ExpectedPath)
    if ($null -eq $Api) { return $false }
    return ($Api.properties.path -eq $ExpectedPath -and $Api.properties.subscriptionRequired -eq $true -and
        @($Api.properties.protocols) -contains 'https' -and
        $Api.properties.subscriptionKeyParameterNames.header -eq 'api-key')
}

function Get-L11GatewayAbsenceState {
    param([ValidateSet('Baseline','Recording')][string]$Scope)
    # A deliberately reset baseline is healthy, but cannot pass a recording gate.
    if ($Scope -eq 'Recording') { return 'FAIL' }
    return 'WARN'
}

function Get-L11OutputBlockOutcome {
    param([string]$FinishReason, [string]$Reply, [string]$BlocklistAnnotation)
    # A normal completion containing the configured pattern is a miss even when setup passed.
    if ($FinishReason -eq 'content_filter' -and $BlocklistAnnotation -match 'ctso-customer-ids.*filtered=True') { return 'BLOCK OBSERVED' }
    if ($Reply -match 'CTSO-CUST-[0-9]{6}') { return 'ENFORCEMENT GAP: matching ID returned' }
    return 'BLOCK NOT ESTABLISHED: inspect the response'
}
