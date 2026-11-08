<#
.SYNOPSIS
    Demo 4.1 helper: shows each storage control's effect on a real request, allowed and
    rejected, and saves the responses as private evidence.

.DESCRIPTION
    Every mode prints one line per request: who asked, how they authorized, what they asked
    for, and what the storage service answered. A rejection is reported with the service's
    own error code, because the code is the teaching point: AuthorizationFailure is the
    network firewall, KeyBasedAuthenticationNotPermitted is Shared Key being off, and
    AuthorizationPermissionMismatch is an Entra role that doesn't cover the request.

    Modes, in demo order:
      Settings          Read back the account's security settings (read-only).
      Firewall          Entra read from the workstation, which the firewall rejects.
      AllowWorkstation  Add the workstation's IP rule and retry until it's allowed.
      KeyRead           List keys as subscription Owner, then read a customer document with a key.
      PolicySas         Read with a service SAS bound to a stored access policy, delete the
                        policy, and show the same SAS rejected.
      DisableSharedKey  Turn Shared Key off and show the key read rejected.
      EntraRead         Entra read of a service record (allowed) and of a customer document
                        (rejected: the role is scoped to one container).

.PARAMETER Mode
    One of the modes above.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-04\Invoke-L04StorageDemo.ps1 -Mode Firewall

.NOTES
    Keys and SAS tokens stay in memory for one call and are never printed or saved.
    Reset-L04Lab.ps1 restores the starting state for another take.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Settings', 'Firewall', 'AllowWorkstation', 'KeyRead', 'PolicySas', 'DisableSharedKey', 'EntraRead')]
    [string]$Mode
)
. (Join-Path $PSScriptRoot 'L04.Common.ps1')
[void](Assert-L04Context)
$lab = Get-L04Outputs
$acct = $lab.recordsAccount
$rg = $script:L04Config.resourceGroup
$results = [System.Collections.Generic.List[object]]::new()

function Test-BlobRead {
    <#
    .SYNOPSIS Reads blob properties (a data-plane read) and reports allowed or the error code.
    .NOTES   Properties, not content, so nothing is written to disk. The request needs the
             same blobs/read permission as a download.
    #>
    param([string]$Container, [string]$Blob, [ValidateSet('login', 'key', 'sas')][string]$Auth, [string]$Secret, [string]$Label)
    if ($Auth -eq 'sas') {
        # A SAS is just a URL, so call the Blob service directly. That also returns the
        # service's own x-ms-error-code header, which the CLI would paraphrase away.
        $uri = "https://$acct.blob.core.windows.net/$Container/$Blob`?$Secret"
        $resp = Invoke-WebRequest -Method Head -Uri $uri -SkipHttpErrorCheck -TimeoutSec 30
        $code = if ($resp.Headers['x-ms-error-code']) { @($resp.Headers['x-ms-error-code'])[0] } else { "HTTP $($resp.StatusCode)" }
        $uri = $null
        $row = [pscustomobject]@{
            Time    = [DateTime]::UtcNow.ToString('HH:mm:ss') + 'Z'
            Request = $Label
            Target  = "$Container/$Blob"
            Result  = $(if ([int]$resp.StatusCode -lt 300) { 'ALLOWED' } else { "REJECTED $code (HTTP $([int]$resp.StatusCode))" })
        }
        $results.Add($row)
        return $row
    }
    # Read the actual service response through the SDK. Credentials travel on stdin, never
    # in process arguments; friendly CLI advice is not evidence of a particular error code.
    $credential = if ($Auth -eq 'login') { Invoke-L04Az @('account', 'get-access-token', '--resource', 'https://storage.azure.com/') } else { $Secret }
    $request = @{ accountUrl = "https://$acct.blob.core.windows.net"; container = $Container; blob = $Blob; auth = $Auth; credential = $credential }
    try {
        $raw = $request | ConvertTo-Json -Depth 10 -Compress | & $script:L04Python (Join-Path $PSScriptRoot 'read_blob_properties.py')
        if ($LASTEXITCODE -ne 0) { throw 'Blob request failed before an attributable service response.' }
        $r = $raw | ConvertFrom-Json
    }
    finally { $credential = $null; $request = $null }
    $row = [pscustomobject]@{
        Time    = [DateTime]::UtcNow.ToString('HH:mm:ss') + 'Z'
        Request = $Label
        Target  = "$Container/$Blob"
        Result  = $(if ($r.status -lt 300) { 'ALLOWED' } else { "REJECTED $($r.code) (HTTP $($r.status))" })
        HttpStatus = $r.status
        ServiceCode = $r.code
        RequestId = $r.requestId
    }
    $results.Add($row)
    return $row
}

function Show-Results { $results | Format-Table Time, Request, Target, Result -AutoSize -Wrap | Out-String -Width 160 | Write-Host }

switch ($Mode) {
    'Settings' {
        $a = Invoke-L04Az @('storage', 'account', 'show', '--name', $acct, '--resource-group', $rg)
        $rows = [ordered]@{
            'Secure transfer required'      = $a.enableHttpsTrafficOnly
            'Minimum TLS version'           = $a.minimumTlsVersion
            'Allow Blob anonymous access'   = $a.allowBlobPublicAccess
            'Allow cross-tenant replication'= $a.allowCrossTenantReplication
            'Allow storage account key access' = $(if ($null -eq $a.allowSharedKeyAccess) { 'True (unset)' } else { $a.allowSharedKeyAccess })
            'Infrastructure encryption'     = $a.encryption.requireInfrastructureEncryption
            'Public network access'         = $a.publicNetworkAccess
            'Firewall default action'       = $a.networkRuleSet.defaultAction
            'Firewall IP rules'             = $(if (@($a.networkRuleSet.ipRules).Count) { ($a.networkRuleSet.ipRules.ipAddressOrRange -join ', ') } else { 'none' })
            'Trusted services exception'    = $a.networkRuleSet.bypass
        }
        $rows.GetEnumerator() | ForEach-Object { [pscustomobject]@{ Setting = $_.Key; Value = $_.Value } } | Format-Table -AutoSize | Out-String | Write-Host
        [void](Write-L04Evidence 'storage-settings' $rows)
        return
    }
    'Firewall' {
        [void](Test-BlobRead -Container 'service-records' -Blob 'SR-2026-0418.json' -Auth login -Label 'Kim, Entra ID, from the workstation')
    }
    'AllowWorkstation' {
        $ip = Get-L04OperatorIp
        Set-L04RecordsIpRule -AccountName $acct -Ip $ip -Action Add
        Write-Host "Added IP rule $ip. Firewall changes take up to a minute; retrying the same read."
        $deadline = (Get-Date).AddSeconds(120)
        do {
            $row = Test-BlobRead -Container 'service-records' -Blob 'SR-2026-0418.json' -Auth login -Label 'Kim, Entra ID, from the workstation'
            if ($row.Result -eq 'ALLOWED') { break }
            Start-Sleep -Seconds 10
        } while ((Get-Date) -lt $deadline)
        # Only the final attempt is teaching evidence; the intermediate rejections were propagation.
        $last = $results[$results.Count - 1]; $results.Clear(); $results.Add($last)
    }
    'KeyRead' {
        $key = Get-L04AccountKey -AccountName $acct
        try { [void](Test-BlobRead -Container 'customer-documents' -Blob 'CTSO-CUST-1042-contract.txt' -Auth key -Secret $key -Label 'Kim, account key from listKeys') }
        finally { $key = $null }
    }
    'PolicySas' {
        $key = Get-L04AccountKey -AccountName $acct
        $sas = $null
        try {
            # A service SAS that names the stored access policy. The token carries no
            # permissions or expiry of its own; the policy on the container supplies both.
            $sas = Invoke-L04Az -Raw -NoSubscription @('storage', 'blob', 'generate-sas', '--account-name', $acct, '--account-key', $key, '--container-name', 'service-records', '--name', 'SR-2026-0418.json', '--policy-name', $script:L04Config.storedAccessPolicy, '--https-only', '--output', 'tsv')
            $sas = $sas.Trim('"')
            [void](Test-BlobRead -Container 'service-records' -Blob 'SR-2026-0418.json' -Auth sas -Secret $sas -Label "Partner, SAS bound to $($script:L04Config.storedAccessPolicy)")
            [void](Invoke-L04Az -NoSubscription @('storage', 'container', 'policy', 'delete', '--container-name', 'service-records', '--name', $script:L04Config.storedAccessPolicy, '--account-name', $acct, '--account-key', $key))
            Write-Host "Deleted stored access policy $($script:L04Config.storedAccessPolicy). Same SAS, same request:"
            # Stored policy changes can propagate. A bounded retry must observe denial,
            # not turn a delay or an unexpected allow into a successful demo.
            $before = $results[0]
            $deadline = (Get-Date).AddSeconds(60)
            do {
                $after = Test-BlobRead -Container 'service-records' -Blob 'SR-2026-0418.json' -Auth sas -Secret $sas -Label 'Partner, same SAS after the policy is deleted'
                if ($after.Result -like '*AuthenticationFailed*') { break }
                Start-Sleep -Seconds 5
            } while ((Get-Date) -lt $deadline)
            $results.Clear(); $results.Add($before); $results.Add($after)
        }
        finally { $key = $null; $sas = $null }
    }
    'DisableSharedKey' {
        $key = Get-L04AccountKey -AccountName $acct
        try {
            [void](Invoke-L04Az @('storage', 'account', 'update', '--name', $acct, '--resource-group', $rg, '--allow-shared-key-access', 'false'))
            Write-Host 'Allow storage account key access: Disabled. Retrying the key read.'
            $deadline = (Get-Date).AddSeconds(90)
            do {
                $row = Test-BlobRead -Container 'customer-documents' -Blob 'CTSO-CUST-1042-contract.txt' -Auth key -Secret $key -Label 'Kim, the same account key'
                if ($row.Result -like '*KeyBasedAuthenticationNotPermitted*') { break }
                Start-Sleep -Seconds 5
            } while ((Get-Date) -lt $deadline)
            $last = $results[$results.Count - 1]; $results.Clear(); $results.Add($last)
        }
        finally { $key = $null }
    }
    'EntraRead' {
        [void](Test-BlobRead -Container 'service-records' -Blob 'SR-2026-0418.json' -Auth login -Label 'Kim, Entra ID (Storage Blob Data Reader on service-records)')
        [void](Test-BlobRead -Container 'customer-documents' -Blob 'CTSO-CUST-1042-contract.txt' -Auth login -Label 'Kim, Entra ID, no role on customer-documents')
    }
}
Show-Results
[void](Write-L04Evidence ('storage-' + $Mode.ToLowerInvariant()) @($results))
# Unexpected results stop rehearsal. Evidence is retained even when a gate fails.
$expected = switch ($Mode) {
    'Firewall' { @('*AuthorizationFailure*') }
    'AllowWorkstation' { @('ALLOWED') }
    'KeyRead' { @('ALLOWED') }
    'PolicySas' { @('ALLOWED', '*AuthenticationFailed*') }
    'DisableSharedKey' { @('*KeyBasedAuthenticationNotPermitted*') }
    'EntraRead' { @('ALLOWED', '*AuthorizationPermissionMismatch*') }
}
for ($i = 0; $i -lt $results.Count; $i++) {
    if ($results[$i].Result -notlike @($expected)[$i]) { throw "Demo $Mode did not produce its expected result. Read the saved evidence." }
}
