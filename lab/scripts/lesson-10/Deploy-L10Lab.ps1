<#
.SYNOPSIS
    Deploys the SC-500 Lesson 10 lab: ServiceHub's agent identities in Microsoft Entra Agent ID,
    two report-only Conditional Access policies for agents, and the assistant's knowledge store.
.DESCRIPTION
    Directory half, through Microsoft Graph with the operator's Azure CLI sign-in (idempotent;
    every object is found by name and checked for the lab marker before it's reused):
      - agent identity blueprint "SC500-L10 ServiceHub Agents Blueprint" and its principal,
        sponsored by Garth Fort, the ServiceHub application engineer, with no credentials;
      - agent identities "SC500-L10 ServiceHub Assistant" and "SC500-L10 ServiceHub Triage Agent",
        both from that blueprint and sponsored by Garth;
      - Conditional Access "CTSO-L10-Agents-HighRisk-Block-ReportOnly" (all agent identities, agent
        risk High, block) and "CTSO-L10-Agents-Unapproved-Block-ReportOnly" (every agent identity
        except the approved assistant, all resources, block). Both stay in
        report-only mode: they log what they would do and never block a sign-in.
    Azure half, through Bicep: rg-sc500-l10-agents with an identities-only storage account, its
    containers, the role assignments (the assistant deliberately too broad), and the fixtures.
    Without -Deploy it previews: the Graph objects it would create, then an ARM what-if.
.PARAMETER Deploy Create or update. Without it, the script previews and changes nothing.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-10\Deploy-L10Lab.ps1
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-10\Deploy-L10Lab.ps1 -Deploy
#>
[CmdletBinding()]
param([switch]$Deploy)
. (Join-Path $PSScriptRoot 'L10.Common.ps1')
$cfg = $script:L10Config; $dir = $cfg.directory; $ca = $cfg.conditionalAccess
$started = Get-Date
[void](Assert-L10Context)
$me = Get-L10User $cfg.operatorUpn
$sponsor = Get-L10User $dir.sponsorUpn
$sponsorRef = "$script:L10Graph/v1.0/users/$($sponsor.id)"
Write-Host "Sponsor for every lab agent: $($sponsor.displayName) ($($sponsor.userPrincipalName))."
$plan = [System.Collections.Generic.List[string]]::new()

# ---- Blueprint --------------------------------------------------------------------------
$bp = Get-L10Blueprint
if ($bp) {
    if ($bp.description -ne $dir.marker) { throw "Blueprint $($dir.blueprint) exists without the lab marker. Stopping." }
} elseif ($Deploy) {
    $bp = Invoke-L10Rest -Method post -OData -Path '/v1.0/applications/microsoft.graph.agentIdentityBlueprint' -Body @{
        displayName = $dir.blueprint; description = $dir.marker; tags = @($dir.tag); 'sponsors@odata.bind' = @($sponsorRef) }
    Write-Host "Created blueprint $($bp.displayName) ($($bp.appId))."
} else { $plan.Add("create blueprint $($dir.blueprint)") }
if ($bp) {
    # The blueprint's sponsor is the accountable human; keep it on Garth even if the object predates this script.
    try {
        $bpSponsors = @((Invoke-L10Rest -Path "/beta/applications/$($bp.id)/microsoft.graph.agentIdentityBlueprint/sponsors").value)
        if ($sponsor.id -notin @($bpSponsors | ForEach-Object id)) {
            if ($Deploy) { [void](Invoke-L10Rest -Method post -Path "/beta/applications/$($bp.id)/microsoft.graph.agentIdentityBlueprint/sponsors/`$ref" -Body @{ '@odata.id' = "$script:L10Graph/beta/directoryObjects/$($sponsor.id)" }) }
            else { $plan.Add('add Garth as the blueprint sponsor') }
        }
    } catch { Write-Warning "Couldn't read or set the blueprint's sponsors through Graph ($($_.Exception.Message.Split("`n")[0])). Check them in the Entra admin center." }
    $creds = Get-L10Value $bp 'passwordCredentials'
    $n = if ($creds) { @($creds).Count } else { 0 }
    if ($n) { Write-Warning "The blueprint holds $n secret(s). A demo run that didn't finish left one; Reset-L10Lab.ps1 removes it." }
}

# ---- Blueprint principal ------------------------------------------------------------------
$bpp = if ($bp) { Get-L10BlueprintPrincipal -AppId $bp.appId } else { $null }
if (-not $bpp) {
    if ($Deploy -and $bp) {
        $bpp = Invoke-L10Rest -Method post -OData -Path '/v1.0/servicePrincipals/microsoft.graph.agentIdentityBlueprintPrincipal' -Body @{ appId = $bp.appId; tags = @($dir.tag) }
        Write-Host "Created the blueprint principal ($($bpp.id))."
    } else { $plan.Add('create the blueprint principal') }
}

# ---- Agent identities ---------------------------------------------------------------------
$agents = [ordered]@{}
foreach ($which in 'assistant', 'triage') {
    $a = Get-L10Agent $which
    if ($a) {
        if ($bp -and $a.agentIdentityBlueprintId -ne $bp.appId) { throw "$($a.displayName) comes from a different blueprint. Stopping." }
    } elseif ($Deploy -and $bpp) {
        # A new blueprint principal can take a few seconds to be usable as a parent; retry briefly.
        foreach ($try in 1..6) {
            try {
                $a = Invoke-L10Rest -Method post -OData -Path '/beta/servicePrincipals/microsoft.graph.agentIdentity' -Body @{
                    displayName = $dir.$which; agentIdentityBlueprintId = $bp.appId; tags = @($dir.tag); 'sponsors@odata.bind' = @($sponsorRef) }
                break
            } catch { if ($try -eq 6) { throw }; Start-Sleep -Seconds 10 }
        }
        Write-Host "Created agent identity $($a.displayName) ($($a.id))."
    } else { $plan.Add("create agent identity $($dir.$which)") }
    $agents[$which] = $a
}

# ---- Conditional Access (report-only) --------------------------------------------------------
# Both policies target All resources: Conditional Access can't name first-party resources such as
# Microsoft Graph for agents (error 1034, UnsupportedFirstPartyApplication, in rehearsal).
function New-L10PolicyBody([string]$Name, [string[]]$Exclude, [string]$Risk) {
    $clients = @{ includeAgentIdServicePrincipals = @('All') }
    if ($Exclude) { $clients.excludeAgentIdServicePrincipals = $Exclude }
    $conditions = @{ users = @{ includeUsers = @('None') }; clientAppTypes = @('all')
                     clientApplications = $clients; applications = @{ includeApplications = @('All') } }
    if ($Risk) { $conditions.agentIdRiskLevels = $Risk }
    return @{ displayName = $Name; state = 'enabledForReportingButNotEnforced'; conditions = $conditions
              grantControls = @{ operator = 'OR'; builtInControls = @('block') } }
}
$wanted = @()
if ($agents.assistant) {
    # High agent risk blocks any agent. The approved-agents list blocks every agent identity except
    # the ones security has approved, here just the assistant.
    $wanted += , @($ca.highRisk, (New-L10PolicyBody $ca.highRisk $null 'high'))
    $wanted += , @($ca.unapproved, (New-L10PolicyBody $ca.unapproved @($agents.assistant.id) $null))
}
foreach ($w in $wanted) {
    $name, $body = $w
    $p = Get-L10Policy $name
    if ($p) {
        if ($p.state -ne 'enabledForReportingButNotEnforced') { throw "$name isn't report-only ($($p.state)). The lab never enforces; fix it by hand." }
    } elseif ($Deploy) {
        $p = Invoke-L10Rest -Method post -Path '/beta/identity/conditionalAccess/policies' -Body $body
        Write-Host "Created Conditional Access policy $name (report-only)."
    } else { $plan.Add("create Conditional Access policy $name (report-only)") }
}

if (-not $Deploy) {
    Write-Host '== Directory preview'
    if ($plan.Count) { $plan | ForEach-Object { "  would $_" } | Out-Host } else { Write-Host '  every directory object is present' }
    if (-not ($agents.assistant -and $agents.triage)) { Write-Host 'The Azure preview needs the agent identities; run with -Deploy to create them first.'; return }
}

# ---- Azure half ---------------------------------------------------------------------------------
$params = @{
    location = @{ value = $cfg.location }; resourceGroupName = @{ value = $cfg.resourceGroup }
    storageName = @{ value = $cfg.names.storageAccount }; containers = @{ value = @($cfg.names.containers) }
    assistantPrincipalId = @{ value = $agents.assistant.id }; triagePrincipalId = @{ value = $agents.triage.id }
    operatorObjectId = @{ value = $me.id }; roles = @{ value = $cfg.roles }
    managedBy = @{ value = $cfg.managedBy }; baseline = @{ value = $cfg.baseline }
}
[void][IO.Directory]::CreateDirectory($script:L10State)
$paramFile = Join-Path $script:L10State 'main.parameters.json'
@{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = $params } |
    ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $paramFile -Encoding utf8
$template = Join-Path $script:L10Infra 'main.bicep'
$common = @('deployment', 'sub', '--name', $cfg.deploymentName, '--location', $cfg.location, '--template-file', $template, '--parameters', "@$paramFile")

if (-not $Deploy) {
    $wi = Invoke-L10Az -Raw (@('deployment', 'sub', 'what-if') + $common[2..($common.Count - 1)] + @('--result-format', 'ResourceIdOnly', '--no-pretty-print'))
    Write-Host '== ARM what-if'; $wi | Out-Host
    return
}

Write-Host 'Deploying the Azure half (a minute or two).'
$d = Invoke-L10Az (@('deployment', 'sub', 'create') + $common[2..($common.Count - 1)])
if ($d.properties.provisioningState -ne 'Succeeded') { throw "Deployment ended $($d.properties.provisioningState)." }
$lab = $d.properties.outputs.lab.value

# Upload the fixtures as the operator, with a Microsoft Entra token (the account accepts no keys).
# A fresh role assignment can take a minute or two to reach the storage data plane, so retry.
foreach ($f in $cfg.fixtures) {
    $file = Join-Path $script:L10Infra $f.file
    foreach ($try in 1..12) {
        $r = Invoke-L10Az -AllowFailure @('storage', 'blob', 'upload', '--auth-mode', 'login', '--account-name', $lab.storage, '--container-name', $f.container,
                                          '--name', $f.blob, '--file', $file, '--overwrite', 'true', '--content-type', 'text/plain; charset=utf-8')
        if ($r.ExitCode -eq 0) { break }
        if ($try -eq 12) { throw "Upload of $($f.container)/$($f.blob) failed: $($r.Stderr.Trim())" }
        Start-Sleep -Seconds 15
    }
    Write-Host "Uploaded $($f.container)/$($f.blob)."
}

$row = [ordered]@{
    deployedUtc = [DateTime]::UtcNow.ToString('o'); minutes = [math]::Round(((Get-Date) - $started).TotalMinutes, 1)
    blueprint = @{ name = $bp.displayName; appId = $bp.appId }; blueprintPrincipal = $bpp.id
    # An agent identity's client ID is its object ID; that's the value the blueprint puts in fmi_path.
    agents = @{ assistant = @{ id = $agents.assistant.id; clientId = $agents.assistant.id }; triage = @{ id = $agents.triage.id; clientId = $agents.triage.id } }
    sponsor = $sponsor.userPrincipalName; storage = $lab.storage; resourceGroup = $lab.resourceGroup
}
[void](Write-L10Evidence 'deployment' $row)
Write-Host ("Lesson 10 lab deployed in {0:N0} minutes." -f $row.minutes)
