<#
.SYNOPSIS
Authenticates Azure CLI using the current ARM deployment operation's MFA challenge.
.DESCRIPTION
Requires the compiled template and generated parameter file from the deployment script.
Probes the read-only validate endpoint and passes only the returned claims challenge to Azure CLI.
Never weakens MFA, fabricates claims, logs tokens, or writes credentials into the course folder.
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'Sc500.Common.ps1')
$null=Assert-Sc500Context
$template=Get-Content -Raw -LiteralPath (Join-Path $script:Sc500Root '.azure/main.json') | ConvertFrom-Json -Depth 100
$parameters=Get-Content -Raw -LiteralPath (Join-Path $script:Sc500Root '.azure/lesson01.parameters.json') | ConvertFrom-Json -Depth 20
$token=Invoke-Sc500Az -Arguments @('account','get-access-token','--resource','https://management.azure.com/','--subscription',$script:Sc500Config.subscriptionId)
$body=@{location=$script:Sc500Config.location;properties=@{mode='Incremental';template=$template;parameters=$parameters.parameters}} | ConvertTo-Json -Depth 100 -Compress
$uri='https://management.azure.com/subscriptions/'+$script:Sc500Config.subscriptionId+'/providers/Microsoft.Resources/deployments/sc500-lesson01/validate?api-version=2022-09-01'
try { $response=Invoke-WebRequest -Method Post -Uri $uri -Headers @{Authorization=('Bearer '+$token.accessToken)} -ContentType 'application/json' -Body $body -SkipHttpErrorCheck }
finally { $token=$null }
if ($response.StatusCode -in @(200,201,202)) { Write-Host 'ARM accepted this session. No additional sign-in is needed.'; return }
$challenge=[regex]::Match([string]$response.Headers['WWW-Authenticate'],'claims="([^"]+)"')
if (-not $challenge.Success) { throw "ARM returned HTTP $($response.StatusCode) without a claims challenge: $($response.Content)" }
$cliPython=Join-Path $env:ProgramFiles 'Microsoft SDKs/Azure/CLI2/python.exe'
& $cliPython -Im azure.cli login --tenant $script:Sc500Config.tenantId --use-device-code --scope 'https://management.core.windows.net//.default' --claims-challenge $challenge.Groups[1].Value --output none
if ($LASTEXITCODE -ne 0) { throw 'The MFA challenge was not completed. No resource deployment was attempted.' }
Write-Host 'Challenge sign-in completed. Rerun the deployment preview to verify acceptance.'
