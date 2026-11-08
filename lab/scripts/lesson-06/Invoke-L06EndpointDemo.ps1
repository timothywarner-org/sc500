<#
.SYNOPSIS
    Demo 6.1: put the ServiceHub records account behind a private endpoint, then turn off its
    public network access.

.DESCRIPTION
    Each -Mode is one demo step and saves its result under lab/.azure/lesson-06/evidence.
      Settings        The records account's network and authentication settings, its private
                      endpoint connections, and the private DNS zone's VNet links.
      Resolve         How the account name resolves from the workstation (public DNS) and from
                      the ServiceHub app VM (Azure DNS with the linked private zone).
      PublicRead      Reads the synthetic record from the workstation with your Entra sign-in.
      VmRead          Reads the same record from inside the ServiceHub app VM with its managed
                      identity.
      CreateEndpoint  Creates pep-servicehubrecords-blob-001 (blob subresource, 10.60.0.68) in the hub's
                      snet-private-endpoints, with a DNS zone group that writes the A record.
      DisablePublic   Sets public network access to Disabled. Traffic can then arrive only
                      through an approved private endpoint.
    Reset-L06Lab.ps1 deletes the endpoint and turns public network access back on.

.PARAMETER Mode
    Settings, Resolve, PublicRead, VmRead, CreateEndpoint, or DisablePublic.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Invoke-L06EndpointDemo.ps1 -Mode Settings
#>
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Settings', 'Resolve', 'PublicRead', 'VmRead', 'CreateEndpoint', 'DisablePublic')][string]$Mode)
. (Join-Path $PSScriptRoot 'L06.Common.ps1')
[void](Assert-L06Context)
$cfg = $script:L06Config
$lab = Get-L06Outputs -Lab Private
$rg = $cfg.resourceGroup
$peName = $script:L06Names.recordsEndpoint

switch ($Mode) {
    'Settings' {
        $sa = Invoke-L06Az @('storage', 'account', 'show', '--resource-group', $rg, '--name', $lab.recordsAccountName)
        $pes = @(Get-L06Value $sa 'privateEndpointConnections')
        $links = @(Invoke-L06Az @('network', 'private-dns', 'link', 'vnet', 'list', '--resource-group', $rg, '--zone-name', $cfg.privateDnsZone))
        $view = [ordered]@{
            Account             = $sa.name
            PublicNetworkAccess = $sa.publicNetworkAccess
            FirewallDefault     = $sa.networkRuleSet.defaultAction
            SharedKeyAccess     = $sa.allowSharedKeyAccess
            AnonymousBlobAccess = $sa.allowBlobPublicAccess
            MinimumTls          = $sa.minimumTlsVersion
            PrivateEndpoints    = if ($pes.Count) { @($pes | ForEach-Object { "$(($_.privateEndpoint.id -split '/')[-1]): $($_.privateLinkServiceConnectionState.status)" }) } else { 'none' }
            ZoneLinks           = @($links | ForEach-Object { "$($_.name) ($($_.virtualNetworkLinkState))" })
        }
        [void](Write-L06Evidence 'endpoint-settings' $view)
        $view.GetEnumerator() | ForEach-Object { '{0,-20} {1}' -f $_.Key, ($_.Value -join '; ') }
    }
    'Resolve' {
        $public = Resolve-L06Name -Name $lab.recordsBlobHost
        $guest = Invoke-L06Guest -ResourceGroup $rg -VmName $lab.appVm -Script "getent ahostsv4 $($lab.recordsBlobHost) | awk '{print `$1}' | sort -u | head -n 3"
        $rows = @(
            [pscustomobject]@{ From = 'Workstation (public DNS)'; Chain = ($public.Chain -join ' > '); Address = ($public.Address -join ', ') }
            [pscustomobject]@{ From = "$($lab.appVm) (Azure DNS)"; Chain = ''; Address = (($guest -split "`n") -join ', ') }
        )
        [void](Write-L06Evidence 'endpoint-resolve' $rows)
        $rows | Format-List | Out-String -Width 200
    }
    'PublicRead' {
        # Call the Blob service directly with your Entra token instead of az storage blob
        # download: the CLI replaces the service's error with generic advice, and the demo needs
        # the real status and x-ms-error-code. The token stays in memory and is never printed.
        $token = Invoke-L06Az -NoSubscription -Raw @('account', 'get-access-token', '--resource', 'https://storage.azure.com/', '--query', 'accessToken', '--output', 'tsv')
        try {
            $uri = "https://$($lab.recordsBlobHost)/$($cfg.recordsContainer)/$($cfg.seedBlob)"
            $resp = Invoke-WebRequest -Uri $uri -Headers @{ Authorization = "Bearer $token"; 'x-ms-version' = '2023-11-03' } -SkipHttpErrorCheck -TimeoutSec 20
        }
        finally { $token = $null }
        # Storage error bodies start with a byte order mark; strip it so the camera sees clean text.
        $body = ([string]$resp.Content).TrimStart([char]0xFEFF, '?')
        # On a denial, show the service's own <Message> line (first sentence only).
        $text = if ($body -match '<Message>([^<\r\n]+)') { $Matches[1] } else { $body.Substring(0, [Math]::Min(120, $body.Length)) }
        $row = [pscustomobject]@{
            From       = 'Workstation (internet)'
            HttpStatus = [int]$resp.StatusCode
            ErrorCode  = [string](@($resp.Headers['x-ms-error-code'])[0])
            Content    = $text
        }
        [void](Write-L06Evidence 'endpoint-public-read' $row)
        $row | Format-List | Out-String -Width 200
    }
    'VmRead' {
        $script = Get-L06GuestBlobScript -BlobHost $lab.recordsBlobHost -Container $cfg.recordsContainer -Blob $cfg.seedBlob
        $row = ConvertFrom-L06BlobLine -Output (Invoke-L06Guest -ResourceGroup $rg -VmName $lab.appVm -Script $script) -From $lab.appVm
        [void](Write-L06Evidence 'endpoint-vm-read' $row)
        $row | Format-List | Out-String -Width 200
    }
    'CreateEndpoint' {
        $existing = Invoke-L06Az -AllowFailure @('network', 'private-endpoint', 'show', '--resource-group', $rg, '--name', $peName)
        if ($existing.ExitCode -ne 0) {
            Write-Host "Creating $peName. This takes about a minute."
            [void](Invoke-L06Az @('network', 'private-endpoint', 'create', '--resource-group', $rg, '--name', $peName,
                    # Explicit location: this workstation's az config defaults to eastus, and a
                    # private endpoint must be in its VNet's region (eastus2).
                    '--location', $cfg.location, '--subnet', $lab.privateEndpointsSubnetId,
                    '--private-connection-resource-id', $lab.recordsAccountId, '--group-id', 'blob', '--connection-name', 'conn-records-blob',
                    '--nic-name', $script:L06Names.recordsEndpointNic,
                    '--ip-config', 'name=ipc-records-blob', 'group-id=blob', 'member-name=blob', "private-ip-address=$($cfg.addressPlan.hosts.recordsEndpoint)"))
            # The zone group ties the endpoint to the private DNS zone, so the A record is created
            # now and deleted with the endpoint later. No hand-maintained record.
            [void](Invoke-L06Az @('network', 'private-endpoint', 'dns-zone-group', 'create', '--resource-group', $rg, '--endpoint-name', $peName,
                    '--name', 'default', '--private-dns-zone', $lab.privateDnsZoneId, '--zone-name', 'blob'))
        }
        $pe = Invoke-L06Az @('network', 'private-endpoint', 'show', '--resource-group', $rg, '--name', $peName)
        $conn = @($pe.privateLinkServiceConnections)[0]
        # With a DNS zone group, customDnsConfigs is empty (the zone holds the record instead), so
        # read the address from the endpoint's network interface. StrictMode would throw on an
        # empty-array index, which is what the first rehearsal hit.
        $nic = Invoke-L06Az @('network', 'nic', 'show', '--ids', @($pe.networkInterfaces)[0].id)
        $records = @(Invoke-L06Az @('network', 'private-dns', 'record-set', 'a', 'list', '--resource-group', $rg, '--zone-name', $cfg.privateDnsZone))
        $view = [ordered]@{
            Endpoint     = $pe.name
            Subresource  = ($conn.groupIds -join ',')
            Connection   = "$($conn.name): $($conn.privateLinkServiceConnectionState.status)"
            Nic          = $nic.name
            PrivateIp    = (@($nic.ipConfigurations | ForEach-Object { $_.privateIPAddress }) -join ',')
            ZoneARecords = @($records | ForEach-Object { "$($_.fqdn.TrimEnd('.')) -> $($_.aRecords.ipv4Address -join ',')" })
        }
        [void](Write-L06Evidence 'endpoint-create' $view)
        $view.GetEnumerator() | ForEach-Object { '{0,-13} {1}' -f $_.Key, ($_.Value -join '; ') }
    }
    'DisablePublic' {
        [void](Invoke-L06Az @('storage', 'account', 'update', '--resource-group', $rg, '--name', $lab.recordsAccountName, '--public-network-access', 'Disabled'))
        $sa = Invoke-L06Az @('storage', 'account', 'show', '--resource-group', $rg, '--name', $lab.recordsAccountName, '--query', '{publicNetworkAccess:publicNetworkAccess}')
        [void](Write-L06Evidence 'endpoint-disable-public' $sa)
        "Public network access: $($sa.publicNetworkAccess). Storage firewall changes can take up to a minute to apply."
    }
}
