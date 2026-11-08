<#
.SYNOPSIS
    Demo 6.4: a field-office client resolves the records account to its public address, then a
    conditional forwarder to the DNS Private Resolver makes it resolve the private endpoint.

.DESCRIPTION
    Needs the bounded Dns lab (Deploy-L06Bounded.ps1 -Lab Dns), and demo 6.1's end state: the
    records private endpoint exists and public network access is Disabled. Each -Mode is one
    on-camera step and saves its result under lab/.azure/lesson-06/evidence.
      Settings      The resolver's inbound endpoint, which VNets the private zone is linked to,
                    and the field-office DNS server's conditional forwarders.
      Resolve       The same name from both sides: the field-office DNS stand-in (not linked to
                    the zone) and the ServiceHub app VM (linked).
      Read          The field-office client reads the record with its managed identity,
                    connecting to exactly the address its own DNS returned.
      AddForwarder  Adds blob.core.windows.net -> 10.60.0.4 to the field-office DNS server. That
                    forwards the public zone name, not privatelink, as Microsoft recommends.
    Reset-L06Lab.ps1 empties the forwarder list again.

.PARAMETER Mode
    Settings, Resolve, Read, or AddForwarder.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Invoke-L06DnsDemo.ps1 -Mode Resolve
#>
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Settings', 'Resolve', 'Read', 'AddForwarder')][string]$Mode)
. (Join-Path $PSScriptRoot 'L06.Common.ps1')
[void](Assert-L06Context)
$cfg = $script:L06Config
$private = Get-L06Outputs -Lab Private
$dns = Get-L06Outputs -Lab Dns
$dnsRg = $cfg.dnsResourceGroup
$blobHost = $private.recordsBlobHost

function Invoke-FieldLookup {
    # The field-office client asks its own DNS server, which is the only answer it would ever get.
    $out = Invoke-L06Guest -ResourceGroup $dnsRg -VmName $dns.fieldOfficeVm -Script "/usr/local/bin/onprem-lookup $blobHost; echo '---'; journalctl -t onprem-dns.py -n 1 --no-pager -o cat 2>/dev/null || true"
    $parts = $out -split '---'
    $lines = @($parts[0] -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    [pscustomobject]@{
        From     = "$($dns.fieldOfficeVm) (field-office DNS)"
        Chain    = (@($lines | Where-Object { $_ -like 'CNAME *' } | ForEach-Object { $_.Substring(6) }) -join ' > ')
        Address  = (@($lines | Where-Object { $_ -like 'A *' } | ForEach-Object { $_.Substring(2) }) -join ', ')
        Forwarded = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' }
    }
}

switch ($Mode) {
    'Settings' {
        $inbound = @(Invoke-L06Az @('dns-resolver', 'inbound-endpoint', 'list', '--resource-group', $dnsRg, '--dns-resolver-name', $dns.resolverName))
        $links = @(Invoke-L06Az @('network', 'private-dns', 'link', 'vnet', 'list', '--resource-group', $cfg.resourceGroup, '--zone-name', $cfg.privateDnsZone))
        $forwarders = Invoke-L06Guest -ResourceGroup $dnsRg -VmName $dns.fieldOfficeVm -Script "grep -v '^#' /etc/contoso-onprem-dns/forwarders | sed '/^\s*$/d' || true"
        $view = [ordered]@{
            Resolver           = $dns.resolverName
            InboundEndpoint    = @($inbound | ForEach-Object { "$($_.name) $(@($_.ipConfigurations)[0].privateIpAddress)" })
            ZoneLinkedTo       = @($links | ForEach-Object { ($_.virtualNetwork.id -split '/')[-1] })
            FieldOfficeLinked  = [bool](@($links | Where-Object { $_.virtualNetwork.id -eq $dns.fieldOfficeVnetId }).Count)
            FieldOfficeForwarders = if ($forwarders) { $forwarders } else { 'none (every query goes to the default upstream)' }
        }
        [void](Write-L06Evidence 'dns-settings' $view)
        $view.GetEnumerator() | ForEach-Object { '{0,-22} {1}' -f $_.Key, ($_.Value -join '; ') }
    }
    'Resolve' {
        $field = Invoke-FieldLookup
        $azure = Invoke-L06Guest -ResourceGroup $cfg.resourceGroup -VmName $private.appVm -Script "getent ahostsv4 $blobHost | awk '{print `$1}' | sort -u | head -n 3"
        $rows = @($field, [pscustomobject]@{ From = "$($private.appVm) (Azure DNS, zone linked)"; Chain = ''; Address = (($azure -split "`n") -join ', '); Forwarded = '' })
        [void](Write-L06Evidence 'dns-resolve' $rows)
        $rows | Format-List | Out-String -Width 220
    }
    'Read' {
        $field = Invoke-FieldLookup
        $ip = ($field.Address -split ',\s*')[0]
        if (-not $ip) { throw "The field-office DNS returned no address for $blobHost." }
        $script = Get-L06GuestBlobScript -BlobHost $blobHost -Container $cfg.recordsContainer -Blob $cfg.seedBlob -ConnectIp $ip -ClientId $private.onpremIdentityClientId
        $row = ConvertFrom-L06BlobLine -Output (Invoke-L06Guest -ResourceGroup $dnsRg -VmName $dns.fieldOfficeVm -Script $script) -From "$($dns.fieldOfficeVm) via $ip"
        [void](Write-L06Evidence 'dns-read' $row)
        $row | Format-List | Out-String -Width 200
    }
    'AddForwarder' {
        $line = "blob.core.windows.net $($dns.inboundIp)"
        $out = Invoke-L06Guest -ResourceGroup $dnsRg -VmName $dns.fieldOfficeVm -Script "grep -q '^blob.core.windows.net ' /etc/contoso-onprem-dns/forwarders || echo '$line' >> /etc/contoso-onprem-dns/forwarders; grep -v '^#' /etc/contoso-onprem-dns/forwarders | sed '/^\s*$/d'"
        [void](Write-L06Evidence 'dns-add-forwarder' ([ordered]@{ forwarders = $out }))
        "Conditional forwarders on the field-office DNS server:`n$out"
    }
}
