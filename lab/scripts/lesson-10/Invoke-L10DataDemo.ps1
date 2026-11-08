<#
.SYNOPSIS
    Demos 10.1 and 10.2, the scripted half: who can use Microsoft 365 Copilot in the tenant, and
    how every Copilot Studio agent in each Power Platform environment authenticates its users.
.DESCRIPTION
    Read only. It changes no setting and touches no agent; the Copilot Studio agents it lists are
    your own and stay exactly as they are.
      Copilot   The Microsoft 365 Copilot SKU and the accounts that hold it. Guest accounts show as
                "(guest account)" so a personal address never lands on screen.
      Agents    Every Power Platform environment, and in each one the Copilot Studio agents
                (Dataverse "bot" rows): when each was published, its authentication mode, and who
                may chat with it. A published agent with no authentication is flagged, because
                anyone who has its link can use it and everything its knowledge sources can reach.
      All       Both.
    The rest of 10.1 and 10.2 is portal work with no public API, and it's your step:
    DSPM data risk assessments, Defender's Copilot Studio real-time protection toggle, Power
    Platform threat detection, and the Microsoft 365 admin center's Agents pages.
.PARAMETER Mode Which step to run.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-10\Invoke-L10DataDemo.ps1 -Mode Agents
#>
[CmdletBinding()]
param([ValidateSet('Copilot', 'Agents', 'All')][string]$Mode = 'All')
. (Join-Path $PSScriptRoot 'L10.Common.ps1')
[void](Assert-L10Context)

if ($Mode -in 'Copilot', 'All') {
    $sku = @((Invoke-L10Rest -Path '/v1.0/subscribedSkus?$select=skuId,skuPartNumber,consumedUnits,prepaidUnits').value) | Where-Object skuPartNumber -eq 'Microsoft_365_Copilot'
    if (-not $sku) { Write-Host 'No Microsoft 365 Copilot SKU in this tenant.' }
    else {
        $users = @((Invoke-L10Rest -Path "/v1.0/users?`$filter=assignedLicenses/any(x:x/skuId eq $($sku.skuId))&`$select=displayName,userPrincipalName,userType").value)
        # Copilot answers from whatever each of these accounts can already open. That's why
        # oversharing is the Copilot risk: it doesn't create access, it makes existing access fast.
        $rows = foreach ($u in $users | Sort-Object displayName) {
            [pscustomobject]@{ Account = $u.displayName; SignIn = $(if ($u.userType -eq 'Guest') { '(guest account)' } else { $u.userPrincipalName }); Type = $u.userType }
        }
        Write-Host ("== Microsoft 365 Copilot: {0} of {1} licenses assigned" -f $sku.consumedUnits, $sku.prepaidUnits.enabled)
        $rows | Format-Table -AutoSize | Out-String -Width 160 | Out-Host
        [void](Write-L10Evidence 'copilot-licenses' ([ordered]@{ sku = $sku.skuPartNumber; assigned = $sku.consumedUnits; available = $sku.prepaidUnits.enabled; rows = $rows }))
    }
}

if ($Mode -in 'Agents', 'All') {
    $authLabel = @{ 0 = 'unspecified'; 1 = 'none'; 2 = 'Microsoft Entra ID (integrated)'; 3 = 'custom Entra ID'; 4 = 'generic OAuth 2' }
    $whoLabel = @{ 0 = 'anyone signed in'; 1 = 'agent readers'; 2 = 'group members'; 3 = 'anyone (multitenant)' }
    $envs = @((Invoke-L10Rest -Resource 'https://service.powerapps.com/' -Path 'https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=2020-10-01').value)
    $rows = [Collections.Generic.List[object]]::new(); $skipped = [Collections.Generic.List[string]]::new()
    foreach ($e in $envs) {
        $url = "$(Get-L10Value $e 'properties.linkedEnvironmentMetadata.instanceUrl')".TrimEnd('/')
        if (-not $url) { $skipped.Add("$($e.properties.displayName) (no Dataverse)"); continue }
        try { $bots = @((Invoke-L10Rest -Resource $url -Path "$url/api/data/v9.2/bots?`$select=name,publishedon,authenticationmode,accesscontrolpolicy,statecode").value) }
        catch { $skipped.Add("$($e.properties.displayName) (no read access for this account)"); continue }
        foreach ($b in $bots) {
            $published = [bool](Get-L10Value $b 'publishedon')
            $rows.Add([pscustomobject]@{
                Environment = $e.properties.displayName; Agent = $b.name
                Published = $(if ($published) { ([DateTime]$b.publishedon).ToString('yyyy-MM-dd') } else { 'never' })
                Authentication = $authLabel[[int]$b.authenticationmode]; 'Who can chat' = $whoLabel[[int]$b.accesscontrolpolicy]
                Flag = $(if ($published -and [int]$b.authenticationmode -eq 1) { 'PUBLIC: anyone with the link' } else { '' }) })
        }
    }
    Write-Host '== Copilot Studio agents by environment (read only)'
    $rows | Sort-Object Environment, Agent | Format-Table -AutoSize | Out-String -Width 220 | Out-Host
    $public = @($rows | Where-Object Flag)
    Write-Host ("  Published with no authentication: {0}. Environments not read: {1}." -f $public.Count, $(if ($skipped.Count) { $skipped -join '; ' } else { 'none' }))
    [void](Write-L10Evidence 'copilot-studio-agents' ([ordered]@{ environments = @($envs | ForEach-Object { $_.properties.displayName }); skipped = $skipped; publicAgents = @($public | ForEach-Object Agent); rows = $rows }))
}
