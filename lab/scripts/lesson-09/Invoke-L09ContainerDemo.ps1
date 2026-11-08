<#
.SYNOPSIS
    Demo 9.1 for SC-500 Lesson 9: container security controls, and what Defender for Containers
    reports about misconfigurations and vulnerable images.

.DESCRIPTION
    Modes (Workloads and Privileged change the cluster; the rest read):
      Cluster     AKS security settings: Entra ID with Azure RBAC, local accounts off, API server
                  allow list, Defender sensor, Azure Policy add-on, workload identity, power state.
      Registry    The registry: SKU, admin user, anonymous pull, repositories, and who can pull.
      Workloads   Apply the ServiceHub deployments (images from the lab registry, pulled by the
                  kubelet identity) and list the pods. Runs kubectl through the AKS runCommand API.
      Privileged  Try to create a privileged pod from the same trusted image. Azure Policy for
                  Kubernetes should refuse it at admission.
      Sensor      The Defender sensor and Gatekeeper pods running in the cluster.
      Findings    Image vulnerabilities by image (one Update <package> recommendation per
                  package), the worst packages in the legacy image, and other unhealthy
                  recommendations for the cluster and registry, from Azure Resource Graph.
      App         The container app's ingress restriction and managed-identity pull, and a probe.
      Block       Swap the container app's allow list to a documentation range (203.0.113.0/24),
                  probe (expect 403), then put the operator's address back and probe again.
      Instance    The Container Instances worker (edge part): private IP, subnet, identity pull.
      All         Cluster, Registry, Sensor, Findings, App (read-only modes).

.PARAMETER Mode
    One of the modes above.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Invoke-L09ContainerDemo.ps1 -Mode Privileged
#>
[CmdletBinding()]
param([ValidateSet('Cluster', 'Registry', 'Workloads', 'Privileged', 'Sensor', 'Findings', 'App', 'Block', 'Instance', 'All')][string]$Mode = 'All')
. (Join-Path $PSScriptRoot 'L09.Common.ps1')
[void](Assert-L09Context)
$cfg = $script:L09Config
$rg = $cfg.resourceGroup
$n = $cfg.names
$lab = Get-L09Outputs -Lab Retained
$k8sDir = Join-Path $script:L09Lab 'infra/lesson-09/k8s'

function Get-Manifest([string]$Name) {
    # Fill in the registry, write to the lesson state folder, and return the file name, because
    # The runCommand API sends the file with the command, and kubectl refers to it by name.
    $text = (Get-Content -LiteralPath (Join-Path $k8sDir $Name) -Raw).Replace('__REGISTRY__', $lab.registryServer)
    $out = Join-Path $script:L09State $Name
    Set-Content -LiteralPath $out -Value $text -Encoding utf8
    return $out
}

function Assert-Running {
    $state = Invoke-L09Az @('aks', 'show', '--resource-group', $rg, '--name', $n.aks, '--query', 'powerState.code')
    if ($state -ne 'Running') { throw "$($n.aks) is $state. Run Start-L09Lab.ps1 first." }
}

if ($Mode -in 'Cluster', 'All') {
    Write-Host "== $($n.aks) security settings"
    $a = Invoke-L09Az @('aks', 'show', '--resource-group', $rg, '--name', $n.aks)
    $ranges = @(Get-L09Value $a 'apiServerAccessProfile.authorizedIpRanges')
    $row = [ordered]@{
        'Local accounts disabled'     = [bool](Get-L09Value $a 'disableLocalAccounts')
        'Microsoft Entra ID'          = [bool](Get-L09Value $a 'aadProfile.managed')
        'Azure RBAC for Kubernetes'   = [bool](Get-L09Value $a 'aadProfile.enableAzureRbac')
        'API server allow list'       = $(if ($ranges.Count) { "$($ranges.Count) range (your IP)" } else { 'open' })
        'Defender sensor'             = [bool](Get-L09Value $a 'securityProfile.defender.securityMonitoring.enabled')
        'Azure Policy add-on'         = [bool](Get-L09Value $a 'addonProfiles.azurepolicy.enabled')
        'Workload identity'           = [bool](Get-L09Value $a 'securityProfile.workloadIdentity.enabled')
        'Image cleaner'               = [bool](Get-L09Value $a 'securityProfile.imageCleaner.enabled')
        'Power state'                 = $a.powerState.code
        'Kubernetes version'          = $a.currentKubernetesVersion
    }
    [void](Write-L09Evidence 'container-cluster' $row)
    [pscustomobject]$row | Format-List | Out-String -Width 160 | Out-Host
}

if ($Mode -in 'Registry', 'All') {
    Write-Host "== $($lab.registry)"
    $r = Invoke-L09Az @('acr', 'show', '--name', $lab.registry)
    $repos = @(Invoke-L09Az @('acr', 'repository', 'list', '--name', $lab.registry))
    # Name the identities that can pull: the managed identity the apps use, and AKS's kubelet.
    $known = @{}
    $known[(Invoke-L09Az @('identity', 'show', '--resource-group', $rg, '--name', $n.pullIdentity, '--query', 'principalId'))] = $n.pullIdentity
    $kubelet = Invoke-L09Az @('aks', 'show', '--resource-group', $rg, '--name', $n.aks, '--query', 'identityProfile.kubeletidentity.objectId')
    if ($kubelet) { $known[$kubelet] = "$($n.aks) kubelet identity" }
    $pullers = @(Invoke-L09Az @('role', 'assignment', 'list', '--scope', $r.id, '--role', 'AcrPull') | ForEach-Object {
        if ($known.ContainsKey($_.principalId)) { $known[$_.principalId] } else { $_.principalId } })
    $row = [ordered]@{
        SKU = $r.sku.name; 'Admin user' = [bool]$r.adminUserEnabled; 'Anonymous pull' = [bool](Get-L09Value $r 'anonymousPullEnabled')
        'Public network access' = $r.publicNetworkAccess; Repositories = ($repos -join ', '); 'AcrPull holders' = ($pullers -join ', ')
    }
    [void](Write-L09Evidence 'container-registry' $row)
    [pscustomobject]$row | Format-List | Out-String -Width 200 | Out-Host
}

if ($Mode -eq 'Workloads') {
    Assert-Running
    $f = Get-Manifest 'servicehub-apps.yaml'
    Write-Host '== kubectl apply (as your Microsoft Entra identity, through the AKS runCommand API)'
    $apply = Invoke-L09Kubectl -Command 'kubectl apply -f servicehub-apps.yaml' -File $f
    $apply.Logs | Out-Host
    Start-Sleep -Seconds 20
    $pods = Invoke-L09Kubectl -Command 'kubectl get pods -n servicehub -o wide'
    [void](Write-L09Evidence 'container-workloads' ([ordered]@{ apply = $apply.Logs; pods = $pods.Logs }))
    $pods.Logs | Out-Host
}

if ($Mode -eq 'Privileged') {
    Assert-Running
    $f = Get-Manifest 'privileged-pod.yaml'
    Write-Host '== kubectl apply: a privileged pod from the lab registry'
    $r = Invoke-L09Kubectl -Command 'kubectl apply -f privileged-pod.yaml' -File $f
    [void](Write-L09Evidence 'container-privileged' ([ordered]@{ exitCode = $r.ExitCode; logs = $r.Logs }))
    $r.Logs | Out-Host
    Write-Host "(kubectl exit code $($r.ExitCode))"
}

if ($Mode -in 'Sensor', 'All') {
    Write-Host '== Defender sensor and Gatekeeper pods'
    $state = Invoke-L09Az @('aks', 'show', '--resource-group', $rg, '--name', $n.aks, '--query', 'powerState.code')
    if ($state -ne 'Running') { Write-Host "(cluster is $state)" }
    else {
        $r = Invoke-L09Kubectl -Command 'kubectl get pods -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase --no-headers'
        $lines = @($r.Logs -split "`n" | Where-Object { $_ -match 'defender|gatekeeper|azure-policy' })
        [void](Write-L09Evidence 'container-sensor' ([ordered]@{ pods = $lines }))
        $lines | Out-Host
    }
}

if ($Mode -in 'Findings', 'All') {
    # Image findings arrive as one "Update <package>" recommendation per package per image, each
    # carrying its CVEs; cluster and registry configuration findings arrive as ordinary
    # recommendations. Both come from Azure Resource Graph.
    Write-Host '== Image vulnerabilities, by image (Defender Vulnerability Management)'
    $q = @"
securityresources
| where type == 'microsoft.security/assessments'
| where tolower(tostring(properties.resourceDetails.Id)) contains '/resourcegroups/$($rg.ToLower())/'
| where properties.status.code == 'Unhealthy'
| where tostring(properties.resourceDetails.ResourceType) == '.containerimage'
| extend rad = parse_json(tostring(properties.resourceAdditionalData))
| extend image = tostring(rad.RepositoryDetails.RepositoryName), severity = tostring(properties.metadata.severity)
| extend cves = array_length(parse_json(tostring(properties.additionalData.CvesDetails)))
| summarize packages = count(), cves = sum(cves), critical = countif(severity == 'Critical'), high = countif(severity == 'High'), firstSeenUtc = min(todatetime(properties.status.firstEvaluationDate)) by image
| order by cves desc
"@
    $img = @(Invoke-L09Graph -Query $q)
    [void](Write-L09Evidence 'container-vulnerabilities' ([pscustomobject]@{ rows = $img }))
    if ($img.Count) { $img | Format-Table -AutoSize | Out-String -Width 200 | Out-Host } else { Write-Host '(no findings yet; a pushed or imported image is typically scanned within a few hours)' }

    Write-Host '== Worst packages in servicehub/web'
    $q3 = @"
securityresources
| where type == 'microsoft.security/assessments'
| where tolower(tostring(properties.resourceDetails.Id)) contains '/resourcegroups/$($rg.ToLower())/'
| where properties.status.code == 'Unhealthy' and tostring(properties.resourceDetails.ResourceType) == '.containerimage'
| extend rad = parse_json(tostring(properties.resourceAdditionalData))
| where tostring(rad.RepositoryDetails.RepositoryName) == 'servicehub/web'
| project recommendation = tostring(properties.displayName), severity = tostring(properties.metadata.severity), cves = array_length(parse_json(tostring(properties.additionalData.CvesDetails))), found = tostring(parse_json(tostring(properties.additionalData.DetectedSoftwareVersions))[0]), fixedIn = tostring(properties.additionalData.FixedVersion)
| order by cves desc
| take 6
"@
    $top = @(Invoke-L09Graph -Query $q3)
    [void](Write-L09Evidence 'container-vulnerabilities-top' ([pscustomobject]@{ rows = $top }))
    if ($top.Count) { $top | Format-Table -AutoSize | Out-String -Width 200 | Out-Host }

    Write-Host '== Other unhealthy recommendations for the cluster and the registry'
    $q2 = @"
securityresources
| where type == 'microsoft.security/assessments'
| extend rid = tolower(tostring(properties.resourceDetails.Id))
| where rid contains '/resourcegroups/$($rg.ToLower())/'
| where properties.status.code == 'Unhealthy' and tostring(properties.resourceDetails.ResourceType) != '.containerimage'
| where rid contains 'microsoft.containerservice' or rid contains 'microsoft.containerregistry'
| project resource = tostring(split(rid, '/')[8]), recommendation = tostring(properties.displayName), severity = tostring(properties.metadata.severity)
| order by resource asc, severity asc
"@
    $rows = @(Invoke-L09Graph -Query $q2)
    [void](Write-L09Evidence 'container-recommendations' ([pscustomobject]@{ rows = $rows }))
    if ($rows.Count) { $rows | Format-Table -AutoSize | Out-String -Width 220 | Out-Host } else { Write-Host '(none yet; Defender assesses new resources within hours)' }
}

if ($Mode -in 'App', 'All') {
    Write-Host "== Container app $($n.containerApp)"
    $app = Invoke-L09Rest -Path "$(Get-L09ResourceId 'Microsoft.App/containerApps' $n.containerApp)?api-version=2024-03-01"
    $ing = $app.properties.configuration.ingress
    $rules = @(Get-L09Value $ing 'ipSecurityRestrictions' | ForEach-Object { '{0} {1}' -f $_.action, $(if ($_.ipAddressRange -like '203.0.113.*') { $_.ipAddressRange } else { 'Your IP' }) })
    $reg = @($app.properties.configuration.registries)[0]
    $row = [ordered]@{ External = $ing.external; 'Insecure HTTP allowed' = $ing.allowInsecure; 'IP rules' = ($rules -join '; '); 'Registry pull identity' = ($reg.identity -split '/')[-1]; 'Registry password' = $(if (Get-L09Value $reg 'passwordSecretRef') { 'yes' } else { 'none' }) }
    [pscustomobject]$row | Format-List | Out-String -Width 160 | Out-Host
    $probe = Invoke-L09Http -Uri "https://$($ing.fqdn)/" -TimeoutSec 60
    [void](Write-L09Evidence 'container-app' ([ordered]@{ settings = $row; probe = ($probe | Select-Object Status, Reason, AtUtc) }))
    '{0} {1} at {2} UTC' -f $probe.Status, $probe.Reason, $probe.AtUtc | Out-Host
}

if ($Mode -eq 'Block') {
    $id = Get-L09ResourceId 'Microsoft.App/containerApps' $n.containerApp
    $app = Invoke-L09Rest -Path "$id`?api-version=2024-03-01"
    $ing = $app.properties.configuration.ingress
    $operator = "$(Get-L09OperatorIp)/32"
    function Set-Rules([string]$Range, [string]$Name) {
        $ing.ipSecurityRestrictions = @(@{ name = $Name; description = 'Lesson 9 demo'; ipAddressRange = $Range; action = 'Allow' })
        Invoke-L09Rest -Method patch -Path "$id`?api-version=2024-03-01" -Body @{ properties = @{ configuration = @{ ingress = $ing } } } | Out-Null
    }
    Write-Host '== Allow only 203.0.113.0/24 (a documentation range), then probe'
    Set-Rules '203.0.113.0/24' 'allow-documentation-range'
    Start-Sleep -Seconds 20
    $blocked = Invoke-L09Http -Uri "https://$($ing.fqdn)/" -TimeoutSec 60
    '{0} {1}: {2}' -f $blocked.Status, $blocked.Reason, $blocked.Body | Out-Host
    Write-Host '== Put your IP back, then probe'
    Set-Rules $operator 'allow-operator'
    Start-Sleep -Seconds 20
    $allowed = Invoke-L09Http -Uri "https://$($ing.fqdn)/" -TimeoutSec 60
    '{0} {1}' -f $allowed.Status, $allowed.Reason | Out-Host
    [void](Write-L09Evidence 'container-app-block' ([ordered]@{ blocked = ($blocked | Select-Object Status, Reason, Body, AtUtc); allowed = ($allowed | Select-Object Status, Reason, AtUtc) }))
}

if ($Mode -eq 'Instance') {
    Write-Host "== Container group $($n.containerGroup) (edge part)"
    $g = Invoke-L09Rest -Path "$(Get-L09ResourceId 'Microsoft.ContainerInstance/containerGroups' $n.containerGroup)?api-version=2023-05-01" -AllowNotFound
    if (-not $g) { Write-Host '(not deployed; Deploy-L09Edge.ps1 -Deploy creates it)' }
    else {
        $cred = @(Get-L09Value $g 'properties.imageRegistryCredentials')[0]
        $row = [ordered]@{
            State = Get-L09Value $g 'properties.instanceView.state'; 'IP type' = Get-L09Value $g 'properties.ipAddress.type'; 'Private IP' = Get-L09Value $g 'properties.ipAddress.ip'
            Subnet = ((@(Get-L09Value $g 'properties.subnetIds')[0].id) -split '/')[-1]; Image = $g.properties.containers[0].properties.image
            'Pull identity' = ((Get-L09Value $cred 'identity') -split '/')[-1]; 'Registry password' = $(if (Get-L09Value $cred 'password') { 'yes' } else { 'none' })
        }
        [void](Write-L09Evidence 'container-instance' $row)
        [pscustomobject]$row | Format-List | Out-String -Width 160 | Out-Host
    }
}
