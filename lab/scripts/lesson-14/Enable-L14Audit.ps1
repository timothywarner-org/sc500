<#
.SYNOPSIS
    Enable unified auditing after you explicitly approve this tenant-wide prerequisite.
.DESCRIPTION
    Uses the existing Exchange module and your delegated sign-in, verifies the tenant,
    enables organization customization only when required, and saves before/after evidence.
    This is separate from routine deployment so tenant configuration is never a side effect.
.EXAMPLE
    ./Enable-L14Audit.ps1 -Enable
#>
[CmdletBinding()]
param([switch]$Enable)
. (Join-Path $PSScriptRoot 'L14.Common.ps1')
if (-not $Enable) { throw 'Use -Enable only after approval for tenant-wide audit collection.' }
Import-Module ExchangeOnlineManagement -ErrorAction Stop
$before = $null
$org = $null
Connect-ExchangeOnline -UserPrincipalName $script:L14Config.operatorUpn -DisableWAM -ShowBanner:$false -CommandName Get-OrganizationConfig,Enable-OrganizationCustomization,Get-AdminAuditLogConfig,Set-AdminAuditLogConfig
try {
    $connection = @(Get-ConnectionInformation | Where-Object { $_.UserPrincipalName -eq $script:L14Config.operatorUpn })
    if ($connection.Count -ne 1 -or [string]$connection[0].TenantID -ne $script:L14Config.tenantId) { throw 'Exchange tenant differs from the course tenant.' }
    $org = Get-OrganizationConfig
    $before = [bool](Get-AdminAuditLogConfig).UnifiedAuditLogIngestionEnabled
    # Exchange rejects audit changes in dehydrated organizations; avoid repeating its one-time operation.
    if ($org.IsDehydrated) { Enable-OrganizationCustomization -Confirm:$false -ErrorAction Stop }
    if (-not $before) { Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true -ErrorAction Stop }
    $after = [bool](Get-AdminAuditLogConfig).UnifiedAuditLogIngestionEnabled
    [void](Write-L14Evidence 'audit-enablement' @{readUtc=[DateTime]::UtcNow.ToString('o'); tenant=$script:L14Config.tenantId; before=$before; after=$after; wasDehydrated=[bool]$org.IsDehydrated})
    Write-Host "UnifiedAuditLogIngestionEnabled: $after. Record delivery and the portal are separate checks."
    if (-not $after) { throw 'Audit enablement has not read back as true.' }
} catch {
    # Preserve service rejection evidence without hiding the failure or claiming enablement.
    [void](Write-L14Evidence 'audit-enablement-failed' @{readUtc=[DateTime]::UtcNow.ToString('o'); tenant=$script:L14Config.tenantId; before=$before; wasDehydrated=$(if ($org) { [bool]$org.IsDehydrated } else { $null }); failure=$_.Exception.Message})
    throw
} finally { Disconnect-ExchangeOnline -Confirm:$false }
