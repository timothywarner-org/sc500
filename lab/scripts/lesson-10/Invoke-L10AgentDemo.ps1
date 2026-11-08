<#
.SYNOPSIS
    Demos 10.3 and 10.4: ServiceHub's agent identities in Microsoft Entra Agent ID, the
    Conditional Access policies that apply to them, what each agent can reach, and the lifecycle
    controls that stop it.
.DESCRIPTION
    Modes, in teaching order:
      Inventory   Every agent identity in the tenant: where it came from, its blueprint, its
                  sponsor, and whether it's enabled. The lab's two agents are marked.
      Policies    The Conditional Access policies that target agent identities, with their state.
      Token       Runs the autonomous agent flow for both lab agents (blueprint secret -> exchange
                  token -> agent token for Azure Storage) and reads each fixture container. The
                  blueprint secret lives for this one run, in memory, and is removed in finally.
      SignIns     The lab agents' sign-ins from the last two hours, with each report-only policy's
                  verdict. Sign-ins take a few minutes to arrive after Token.
      Reach       The blast radius of the blueprint's credential: every lab agent it can become,
                  and every role those agents hold, at which scope.
      Scope       Fixes the overexposure: moves the assistant's role from the whole storage account
                  to the knowledge container, then proves finance is refused.
      Disable     Disables the assistant, shows its token request refused, and enables it again.
      All         Inventory, Policies, Token, Reach.
    Reset-L10Lab.ps1 puts the too-broad role back for the next run.
.PARAMETER Mode Which step to run.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-10\Invoke-L10AgentDemo.ps1 -Mode Token
#>
[CmdletBinding()]
param([ValidateSet('Inventory', 'Policies', 'Token', 'SignIns', 'Reach', 'Scope', 'Disable', 'All')][string]$Mode = 'All')
. (Join-Path $PSScriptRoot 'L10.Common.ps1')
$cfg = $script:L10Config
[void](Assert-L10Context)
$bp = Get-L10Blueprint
if (-not $bp) { throw 'The lab blueprint is missing. Run Deploy-L10Lab.ps1 -Deploy.' }
$assistant = Get-L10Agent assistant; $triage = Get-L10Agent triage
$lab = Get-L10Outputs
$blobBase = $lab.blobEndpoint.TrimEnd('/')
$storageScope = 'https://storage.azure.com/.default'

function Get-SponsorText($Agent) {
    # Sponsors come back through $expand, so the whole inventory is one Graph call.
    $names = @(@(Get-L10Value $Agent 'sponsors') | Where-Object { $_ } | ForEach-Object { if (Get-L10Value $_ 'userPrincipalName') { $_.userPrincipalName } else { $_.displayName } })
    if ($names.Count) { return ($names -join ', ') } else { return '(none)' }
}

function Read-Fixtures([string]$Token) {
    # One read per container. The file names come from config, so the demo reads what was deployed.
    $rows = foreach ($f in $cfg.fixtures) {
        $r = Invoke-L10Blob -Uri "$blobBase/$($f.container)/$($f.blob)" -Token $Token
        [pscustomobject]@{ Blob = "$($f.container)/$($f.blob)"; Status = $r.Status; Result = if ($r.Status -eq 200) { $r.FirstLine } else { $r.Code } }
    }
    return @($rows)
}

if ($Mode -in 'Inventory', 'All') {
    $all = @((Invoke-L10Rest -Path '/beta/servicePrincipals/microsoft.graph.agentIdentity?$top=100&$expand=sponsors($select=id,displayName,userPrincipalName)').value)
    $bps = @{}
    foreach ($b in @((Invoke-L10Rest -Path '/beta/applications/microsoft.graph.agentIdentityBlueprint?$top=100&$select=appId,displayName').value)) { $bps[$b.appId] = $b.displayName }
    $rows = foreach ($a in $all | Sort-Object displayName) {
        $isLab = $a.id -in @($assistant.id, $triage.id)
        # Copilot Studio names its agents "<name> (Microsoft Copilot Studio)"; Foundry names its
        # blueprints "<project>-<agent>-...-AgentIdentityBlueprint". Anything else was built by hand.
        $src = if ($isLab) { 'this lab' } elseif ($a.displayName -match '\(Microsoft Copilot Studio\)|\(Power Virtual Agents\)') { 'Copilot Studio' } elseif ($bps[$a.agentIdentityBlueprintId] -match 'AgentIdentityBlueprint$') { 'Microsoft Foundry' } else { 'custom (Graph)' }
        [pscustomobject]@{ Agent = $a.displayName; Source = $src; Enabled = $a.accountEnabled
                           Blueprint = $(if ($bps[$a.agentIdentityBlueprintId]) { $bps[$a.agentIdentityBlueprintId] } else { '(Microsoft-managed)' }); Sponsor = Get-SponsorText $a }
    }
    Write-Host '== Agent identities in the tenant, by where they came from'
    $rows | Group-Object Source | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{ Source = $_.Name; Agents = $_.Count; Enabled = @($_.Group | Where-Object Enabled).Count; 'No sponsor' = @($_.Group | Where-Object Sponsor -eq '(none)').Count }
    } | Format-Table -AutoSize | Out-String -Width 160 | Out-Host
    Write-Host "== This lab's agents"
    $rows | Where-Object Source -eq 'this lab' | Format-Table Agent, Enabled, Blueprint, Sponsor -AutoSize | Out-String -Width 200 | Out-Host
    [void](Write-L10Evidence 'agent-inventory' ([ordered]@{ count = $rows.Count; bySource = ($rows | Group-Object Source | ForEach-Object { "$($_.Name): $($_.Count)" }); rows = $rows }))
}

if ($Mode -in 'Policies', 'All') {
    $pols = @((Invoke-L10Rest -Path '/beta/identity/conditionalAccess/policies').value) | Where-Object { Get-L10Value $_ 'conditions.clientApplications.includeAgentIdServicePrincipals' }
    $names = @{ $assistant.id = 'the assistant'; $triage.id = 'the triage agent' }
    $rows = foreach ($p in $pols) {
        $inc = @(Get-L10Value $p 'conditions.clientApplications.includeAgentIdServicePrincipals')
        $exc = @(Get-L10Value $p 'conditions.clientApplications.excludeAgentIdServicePrincipals') | Where-Object { $_ }
        [pscustomobject]@{ Policy = $p.displayName; State = $p.state
                           Agents = (($inc | ForEach-Object { if ($_ -eq 'All') { 'all agent identities' } elseif ($names[$_]) { $names[$_] } else { $_ } }) -join ', ') + $(if ($exc) { ' except ' + (($exc | ForEach-Object { if ($names[$_]) { $names[$_] } else { $_ } }) -join ', ') } else { '' })
                           Resources = (@(Get-L10Value $p 'conditions.applications.includeApplications') -join ', ')
                           Risk = $(if (Get-L10Value $p 'conditions.agentIdRiskLevels') { $p.conditions.agentIdRiskLevels } else { 'any' })
                           Grant = (@(Get-L10Value $p 'grantControls.builtInControls') -join ', ') }
    }
    Write-Host '== Conditional Access policies that target agent identities'
    $rows | Format-Table -AutoSize -Wrap | Out-String -Width 240 | Out-Host
    [void](Write-L10Evidence 'agent-policies' $rows)
}

# ---- helpers the later modes share ----------------------------------------------------------
$script:roleNames = @{}
function Get-RoleName([string]$DefinitionId) {
    $guid = ($DefinitionId -split '/')[-1]
    if (-not $script:roleNames.ContainsKey($guid)) {
        $d = Invoke-L10Rest -Path "/subscriptions/$($cfg.subscriptionId)/providers/Microsoft.Authorization/roleDefinitions/${guid}?api-version=2022-04-01"
        $script:roleNames[$guid] = $d.properties.roleName
    }
    return $script:roleNames[$guid]
}
function Get-ScopeName([string]$Scope) {
    # Say the scope the way a person would, so the table reads without a decoder ring.
    if ($Scope -match '/containers/([^/]+)$') { return "container $($Matches[1])" }
    if ($Scope -match '/storageAccounts/([^/]+)$') { return "storage account $($Matches[1])" }
    if ($Scope -match '/resourceGroups/([^/]+)$') { return "resource group $($Matches[1])" }
    if ($Scope -match '^/subscriptions/[^/]+$') { return 'subscription' }
    if ($Scope -eq '/') { return 'root' }
    return $Scope
}
function Get-Reach([string]$Scope, [string]$Role) {
    # Which fixture containers a storage data role at this scope can read.
    if ($Role -notmatch '^Storage Blob Data') { return '' }
    if ($Scope -match '/containers/([^/]+)$') { return $Matches[1] }
    if ($lab.storageId -like "$Scope*") { return (@($cfg.names.containers) -join ', ') }
    return ''
}
function Get-AgentRoles($Agent) {
    $f = [uri]::EscapeDataString("principalId eq '$($Agent.id)'")
    return @((Invoke-L10Rest -Path "/subscriptions/$($cfg.subscriptionId)/providers/Microsoft.Authorization/roleAssignments?`$filter=$f&api-version=2022-04-01").value)
}
function Read-AsAgent($Agent, [string]$Secret) {
    # The agent identity's client ID is its object ID; the blueprint names it in fmi_path.
    $t = Get-L10AgentToken -BlueprintAppId $bp.appId -Secret $Secret -AgentAppId $Agent.id -Scope $storageScope
    if (-not $t.Ok) { return [pscustomobject]@{ Token = $t; Reads = @() } }
    return [pscustomobject]@{ Token = $t; Reads = (Read-Fixtures $t.Token) }
}
function Set-AgentEnabled($Agent, [bool]$Enabled) {
    [void](Invoke-L10Rest -Method patch -OData -Path "/beta/servicePrincipals/$($Agent.id)/microsoft.graph.agentIdentity" -Body @{ accountEnabled = $Enabled })
}
$agentName = @{ $assistant.id = 'assistant'; $triage.id = 'triage' }

if ($Mode -in 'Token', 'All') {
    Write-Host '== The autonomous agent flow: blueprint secret -> exchange token -> agent token for Azure Storage'
    $sec = New-L10BlueprintSecret -BlueprintObjectId $bp.id
    $results = [Collections.Generic.List[object]]::new()
    try {
        foreach ($a in $assistant, $triage) {
            $r = Read-AsAgent $a $sec.Secret
            if (-not $r.Token.Ok) { Write-Host "  $($a.displayName): no token. $($r.Token.Step) failed: $($r.Token.Error)"; $results.Add([ordered]@{ agent = $a.displayName; ok = $false; step = $r.Token.Step; error = $r.Token.Error }); continue }
            $c = $r.Token.Claims
            Write-Host ("  {0}: token issued. oid is the agent ({1}), idtyp={2}, xms_act_fct={3}, xms_sub_fct={4}, aud={5}" -f $a.displayName, ($c.oid -eq $a.id), $c.idtyp, $c.xms_act_fct, $c.xms_sub_fct, $c.aud)
            $r.Reads | ForEach-Object { [pscustomobject]@{ Agent = $agentName[$a.id]; Blob = $_.Blob; Status = $_.Status; Result = $_.Result } } | Format-Table -AutoSize | Out-String -Width 200 | Out-Host
            $results.Add([ordered]@{ agent = $a.displayName; ok = $true; claims = $c; reads = $r.Reads })
        }
    }
    finally {
        Remove-L10BlueprintSecret -BlueprintObjectId $bp.id -KeyId $sec.KeyId
        $left = @((Get-L10Blueprint).passwordCredentials).Count
        Write-Host "  Blueprint secret removed. Client secrets left on the blueprint: $left."
    }
    [void](Write-L10Evidence 'agent-token' ([ordered]@{ atUtc = [DateTime]::UtcNow.ToString('o'); secretLifetimeHours = $cfg.directory.secretLifetimeHours; secretRemoved = $true; results = $results }))
}

if ($Mode -eq 'SignIns') {
    $since = [DateTime]::UtcNow.AddHours(-2).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $f = [uri]::EscapeDataString("createdDateTime ge $since and signInEventTypes/any(t: t eq 'servicePrincipal') and (servicePrincipalId eq '$($assistant.id)' or servicePrincipalId eq '$($triage.id)')")
    $s = @((Invoke-L10Rest -Path "/beta/auditLogs/signIns?`$filter=$f&`$top=50").value)
    $verdict = @{ reportOnlyFailure = 'would block'; reportOnlySuccess = 'would allow'; reportOnlyNotApplied = 'not applied'; reportOnlyInterrupted = 'would interrupt'; notApplied = 'not applied'; success = 'allowed'; failure = 'blocked' }
    $rows = foreach ($x in $s | Sort-Object createdDateTime) {
        $row = [ordered]@{ TimeUtc = ([DateTime]$x.createdDateTime).ToUniversalTime().ToString('HH:mm:ss'); Agent = $agentName[$x.servicePrincipalId]; Resource = $x.resourceDisplayName
                           Result = $(if ($x.status.errorCode -eq 0) { 'success' } else { "error $($x.status.errorCode)" }); AgentType = (Get-L10Value $x 'agent.agentType') }
        foreach ($p in @($x.appliedConditionalAccessPolicies) | Where-Object { $_.displayName -like 'CTSO-L10-*' }) {
            $row[($p.displayName -replace '^CTSO-L10-Agents-|-ReportOnly$', '')] = $(if ($verdict[$p.result]) { $verdict[$p.result] } else { $p.result })
        }
        [pscustomobject]$row
    }
    # Graph hides appliedConditionalAccessPolicies from a caller that can read sign-ins but not
    # Conditional Access data. The Azure CLI's delegated token is that caller (AuditLog.Read.All,
    # no Policy.Read.All), so the verdict columns stay empty here; the portal shows them.
    $verdicts = @($s | ForEach-Object { @($_.appliedConditionalAccessPolicies) } | Where-Object { $_ }).Count
    if (-not $rows) { Write-Host 'No lab agent sign-ins in the last two hours yet. They usually land 5 to 15 minutes after -Mode Token; run this again.' }
    else {
        Write-Host '== Lab agent sign-ins (agentType tells you an agent identity signed in, not an app)'
        $rows | Format-Table -AutoSize | Out-String -Width 220 | Out-Host
        if (-not $verdicts) { Write-Host '  The report-only verdicts aren''t in this response: the Azure CLI token can read sign-ins but not Conditional Access data. Open the same sign-in in the Entra admin center, Report-only tab.' }
    }
    [void](Write-L10Evidence 'agent-signins' ([ordered]@{ sinceUtc = $since; count = @($rows).Count; policyVerdictsVisible = [bool]$verdicts; rows = $rows }))
}

if ($Mode -in 'Reach', 'All') {
    Write-Host '== Blast radius: what the blueprint credential can become, and what each identity can touch'
    $kids = @((Invoke-L10Rest -Path "/beta/servicePrincipals/microsoft.graph.agentIdentity?`$filter=agentIdentityBlueprintId eq '$($bp.appId)'").value)
    $rows = [Collections.Generic.List[object]]::new()
    foreach ($a in $kids) {
        foreach ($r in Get-AgentRoles $a) {
            $role = Get-RoleName $r.properties.roleDefinitionId
            $rows.Add([pscustomobject]@{ Identity = $a.displayName; Plane = 'Azure RBAC'; Grant = $role; Scope = Get-ScopeName $r.properties.scope; Reaches = Get-Reach $r.properties.scope $role })
        }
        foreach ($g in @((Invoke-L10Rest -Path "/beta/servicePrincipals/$($a.id)/appRoleAssignments").value)) { $rows.Add([pscustomobject]@{ Identity = $a.displayName; Plane = 'App role'; Grant = $g.appRoleId; Scope = $g.resourceDisplayName; Reaches = '' }) }
        foreach ($m in @((Invoke-L10Rest -Path "/beta/servicePrincipals/$($a.id)/memberOf").value)) { $rows.Add([pscustomobject]@{ Identity = $a.displayName; Plane = 'Directory'; Grant = "member of $($m.displayName)"; Scope = 'tenant'; Reaches = '' }) }
    }
    $rows | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Out-Host
    $union = @($rows | ForEach-Object { $_.Reaches -split ', ' } | Where-Object { $_ } | Sort-Object -Unique)
    $b = Get-L10Blueprint
    $fic = @((Invoke-L10Rest -Path "/v1.0/applications/$($b.id)/federatedIdentityCredentials").value).Count
    Write-Host ("  The blueprint can mint tokens for {0} agent identities. Credentials on it right now: {1} secrets, {2} federated." -f $kids.Count, @($b.passwordCredentials).Count, $fic)
    Write-Host ("  Whoever holds a blueprint credential reaches these containers: {0}." -f ($union -join ', '))
    [void](Write-L10Evidence 'agent-reach' ([ordered]@{ agents = @($kids | ForEach-Object { $_.displayName }); blueprintSecrets = @($b.passwordCredentials).Count; blueprintFederated = $fic; containersReached = $union; rows = $rows }))
}

if ($Mode -eq 'Scope') {
    # Least privilege for the assistant: Storage Blob Data Reader on the knowledge container only.
    $reader = "/subscriptions/$($cfg.subscriptionId)/providers/Microsoft.Authorization/roleDefinitions/$($cfg.roles.blobDataReader)"
    $knowledge = "$($lab.storageId)/blobServices/default/containers/knowledge"
    $name = [guid]::new([Security.Cryptography.MD5]::HashData([Text.Encoding]::UTF8.GetBytes("sc500-l10-scoped-$($assistant.id)"))).ToString()
    [void](Invoke-L10Rest -Method put -Path "$knowledge/providers/Microsoft.Authorization/roleAssignments/${name}?api-version=2022-04-01" -Body @{ properties = @{ roleDefinitionId = $reader; principalId = $assistant.id; principalType = 'ServicePrincipal' } })
    [void](Invoke-L10Rest -Method delete -AllowNotFound -Path "$($lab.assistantRoleAssignmentId)?api-version=2022-04-01")
    Write-Host '== The assistant now holds Storage Blob Data Reader on the knowledge container only. Waiting for storage to see it.'
    $start = [DateTime]::UtcNow; $sec = New-L10BlueprintSecret -BlueprintObjectId $bp.id; $r = $null
    try {
        foreach ($try in 1..24) {
            $r = Read-AsAgent $assistant $sec.Secret
            $k = $r.Reads | Where-Object Blob -like 'knowledge/*' | Select-Object -First 1; $fin = $r.Reads | Where-Object Blob -like 'finance/*'
            if ($k.Status -eq 200 -and $fin.Status -eq 403) { break }
            Start-Sleep -Seconds 30
        }
    }
    finally { Remove-L10BlueprintSecret -BlueprintObjectId $bp.id -KeyId $sec.KeyId }
    $r.Reads | ForEach-Object { [pscustomobject]@{ Agent = 'assistant'; Blob = $_.Blob; Status = $_.Status; Result = $_.Result } } | Format-Table -AutoSize | Out-String -Width 200 | Out-Host
    $secs = [int]([DateTime]::UtcNow - $start).TotalSeconds
    Write-Host "  Took $secs seconds to take effect. Reset-L10Lab.ps1 puts the too-broad role back for the next run."
    [void](Write-L10Evidence 'agent-scope' ([ordered]@{ newScope = 'container knowledge'; removed = $lab.assistantRoleAssignmentId; secondsToEffect = $secs; reads = $r.Reads }))
}

if ($Mode -eq 'Disable') {
    Write-Host '== Lifecycle: disable the assistant, watch the token service refuse it, then enable it again'
    $sec = New-L10BlueprintSecret -BlueprintObjectId $bp.id; $restored = $false; $log = [Collections.Generic.List[object]]::new()
    try {
        $t = Get-L10AgentToken -BlueprintAppId $bp.appId -Secret $sec.Secret -AgentAppId $assistant.id -Scope $storageScope
        $log.Add([ordered]@{ state = 'enabled'; ok = $t.Ok; error = $t.Error }); Write-Host "  Enabled:  token issued = $($t.Ok)"
        Set-AgentEnabled $assistant $false; $off = [DateTime]::UtcNow
        foreach ($try in 1..18) { $t = Get-L10AgentToken -BlueprintAppId $bp.appId -Secret $sec.Secret -AgentAppId $assistant.id -Scope $storageScope; if (-not $t.Ok) { break }; Start-Sleep -Seconds 10 }
        $log.Add([ordered]@{ state = 'disabled'; ok = $t.Ok; step = $t.Step; error = $t.Error; seconds = [int]([DateTime]::UtcNow - $off).TotalSeconds })
        Write-Host "  Disabled: token issued = $($t.Ok). $($t.Step) refused: $($t.Error)"
        Set-AgentEnabled $assistant $true; $restored = $true; $on = [DateTime]::UtcNow
        foreach ($try in 1..18) { $t = Get-L10AgentToken -BlueprintAppId $bp.appId -Secret $sec.Secret -AgentAppId $assistant.id -Scope $storageScope; if ($t.Ok) { break }; Start-Sleep -Seconds 10 }
        $log.Add([ordered]@{ state = 're-enabled'; ok = $t.Ok; error = $t.Error; seconds = [int]([DateTime]::UtcNow - $on).TotalSeconds }); Write-Host "  Enabled again: token issued = $($t.Ok)"
    }
    finally {
        if (-not $restored) { Set-AgentEnabled $assistant $true }
        Remove-L10BlueprintSecret -BlueprintObjectId $bp.id -KeyId $sec.KeyId
    }
    [void](Write-L10Evidence 'agent-disable' $log)
}
