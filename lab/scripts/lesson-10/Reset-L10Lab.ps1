<#
.SYNOPSIS
    Puts the Lesson 10 lab back at CTSO-L10-BASELINE between runs.
.DESCRIPTION
    Idempotent. It:
      - removes any demo secret an interrupted run left on the blueprint (only secrets the demo
        named; any other credential is reported and left alone);
      - enables both lab agent identities;
      - gives the assistant its deliberately too-broad role back (Storage Blob Data Reader on the
        whole storage account) and removes the knowledge-container assignment that -Mode Scope made.
    It never touches the Conditional Access policies' state; they stay report-only.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-10\Reset-L10Lab.ps1
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L10.Common.ps1')
$cfg = $script:L10Config
[void](Assert-L10Context)
$bp = Get-L10Blueprint
if (-not $bp) { throw 'The lab blueprint is missing. Run Deploy-L10Lab.ps1 -Deploy.' }
$done = [Collections.Generic.List[string]]::new()

foreach ($c in @(Get-L10Value $bp 'passwordCredentials') | Where-Object { $_ }) {
    if ($c.displayName -like 'sc500-l10-demo*') { Remove-L10BlueprintSecret -BlueprintObjectId $bp.id -KeyId $c.keyId; $done.Add('removed a leftover demo secret from the blueprint') }
    else { Write-Warning "The blueprint holds a credential the demo didn't create ($($c.displayName)). Left alone; check it." }
}

foreach ($which in 'assistant', 'triage') {
    $a = Get-L10Agent $which
    if (-not $a.accountEnabled) {
        [void](Invoke-L10Rest -Method patch -OData -Path "/beta/servicePrincipals/$($a.id)/microsoft.graph.agentIdentity" -Body @{ accountEnabled = $true })
        $done.Add("enabled $($a.displayName)")
    }
}

$assistant = Get-L10Agent assistant
$lab = Get-L10Outputs
$reader = "/subscriptions/$($cfg.subscriptionId)/providers/Microsoft.Authorization/roleDefinitions/$($cfg.roles.blobDataReader)"
$broad = Invoke-L10Rest -AllowNotFound -Path "$($lab.assistantRoleAssignmentId)?api-version=2022-04-01"
if (-not $broad) {
    # Same assignment name as Bicep gave it, so a later Deploy-L10Lab.ps1 run sees no drift.
    [void](Invoke-L10Rest -Method put -Path "$($lab.assistantRoleAssignmentId)?api-version=2022-04-01" -Body @{ properties = @{ roleDefinitionId = $reader; principalId = $assistant.id; principalType = 'ServicePrincipal' } })
    $done.Add('restored the assistant''s account-scope Storage Blob Data Reader role')
}
# Any assistant assignment AT the knowledge container's scope, whatever its name: Scope mode's fixed name, or the
# generated name the portal gives demo step 3.4. atScope() returns assignments at this scope and above, so keep
# only the rows whose scope is exactly the container.
$knowledge = "$($lab.storageId)/blobServices/default/containers/knowledge"
$f = [uri]::EscapeDataString("atScope() and assignedTo('$($assistant.id)')")
$rows = @((Invoke-L10Rest -Path "${knowledge}/providers/Microsoft.Authorization/roleAssignments?`$filter=$f&api-version=2022-04-01").value)
foreach ($ra in $rows | Where-Object { $_.properties.scope -eq $knowledge }) {
    [void](Invoke-L10Rest -Method delete -Path "$($ra.id)?api-version=2022-04-01")
    $done.Add("removed the knowledge-container assignment $($ra.name)")
}

if ($done.Count) { $done | ForEach-Object { "  $_" } | Out-Host; Write-Host 'Storage can take a few minutes to see a role change. Run Test-L10Lab.ps1 before the demo.' }
else { Write-Host 'Already at the baseline; nothing changed.' }
[void](Write-L10Evidence 'reset' ([ordered]@{ atUtc = [DateTime]::UtcNow.ToString('o'); changes = $done }))
