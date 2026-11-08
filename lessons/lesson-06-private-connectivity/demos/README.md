# Lesson 06 lab files

The scripts for this lesson are in [`lab/scripts/lesson-06`](../../../lab/scripts/lesson-06/) and its Bicep templates and `config.json` are in [`lab/infra/lesson-06`](../../../lab/infra/lesson-06/).
Do the [one-time setup](../../../lab/README.md) before you run anything here.

> **Cost warning:** these scripts create real Azure resources. Run this lesson's `Remove-` script when you finish.

## Scripts by stage

Build first, check, run the demos, then reset or clean up. Within a stage, follow the demo order in the lesson.

| Stage | Script | What it does (from the script's own help) |
| --- | --- | --- |
| Build | [`Connect-L06ConnectorRegistration.ps1`](../../../lab/scripts/lesson-06/Connect-L06ConnectorRegistration.ps1) | Gets a short-lived connector registration token and protects it with Windows DPAPI. |
| Build | [`Copy-L06ConnectorPassword.ps1`](../../../lab/scripts/lesson-06/Copy-L06ConnectorPassword.ps1) | Copies the bounded connector host's admin password to the clipboard for your RDP sign-in. |
| Build | [`Deploy-L06Bounded.ps1`](../../../lab/scripts/lesson-06/Deploy-L06Bounded.ps1) | Previews, or deploys, one of the bounded Lesson 6 labs. |
| Build | [`Deploy-L06Client.ps1`](../../../lab/scripts/lesson-06/Deploy-L06Client.ps1) | Previews or deploys the isolated Windows 11 Private Access client. |
| Build | [`Deploy-L06Lab.ps1`](../../../lab/scripts/lesson-06/Deploy-L06Lab.ps1) | Previews, or deploys, the retained SC-500 Lesson 6 private connectivity lab in the subscription infra/lesson-06/config.json pins. |
| Build | [`Install-L06Client.ps1`](../../../lab/scripts/lesson-06/Install-L06Client.ps1) | Installs the signed Global Secure Access client and checks the isolated VM. |
| Build | [`Install-L06Connector.ps1`](../../../lab/scripts/lesson-06/Install-L06Connector.ps1) | Installs the signed Microsoft private network connector on the bounded Lesson 6 host. |
| Build | [`Register-L06Connector.ps1`](../../../lab/scripts/lesson-06/Register-L06Connector.ps1) | Registers the isolated Lesson 6 connector using a protected, short-lived token. |
| Build | [`Set-L06ConnectorGroup.ps1`](../../../lab/scripts/lesson-06/Set-L06ConnectorGroup.ps1) | Assigns the registered Lesson 6 host to its isolated connector group. |
| Build | [`Set-L06MaintenanceEgress.ps1`](../../../lab/scripts/lesson-06/Set-L06MaintenanceEgress.ps1) | Adds or removes explicit outbound-only NAT for Lesson 6 Linux VM maintenance. |
| Build | [`Set-L06PrivateAccessPilot.ps1`](../../../lab/scripts/lesson-06/Set-L06PrivateAccessPilot.ps1) | Configures the isolated ServiceHub Private Access application and report-only policy. |
| Build | [`Start-L06Lab.ps1`](../../../lab/scripts/lesson-06/Start-L06Lab.ps1) | Starts, or with -Stop deallocates, the retained Lesson 6 VM (vm-servicehub-prod-001). |
| Build | [`Start-L06PrivateAccessLab.ps1`](../../../lab/scripts/lesson-06/Start-L06PrivateAccessLab.ps1) | Starts or deallocates the three retained Private Access demo VMs. |
| Check | [`Test-L06Lab.ps1`](../../../lab/scripts/lesson-06/Test-L06Lab.ps1) | Read-only readiness check for the Lesson 6 lab at CTSO-L06-BASELINE. |
| Demo | [`Invoke-L06DnsDemo.ps1`](../../../lab/scripts/lesson-06/Invoke-L06DnsDemo.ps1) | Demo 6.4: a field-office client resolves the records account to its public address, then a conditional forwarder to the DNS Private Resolver makes it resolve the private endpoint. Modes: `Settings`, `Resolve`, `Read`, `AddForwarder`. |
| Demo | [`Invoke-L06EndpointDemo.ps1`](../../../lab/scripts/lesson-06/Invoke-L06EndpointDemo.ps1) | Demo 6.1: put the ServiceHub records account behind a private endpoint, then turn off its public network access. Modes: `Settings`, `Resolve`, `PublicRead`, `VmRead`, `CreateEndpoint`, `DisablePublic`. |
| Demo | [`Invoke-L06PlsDemo.ps1`](../../../lab/scripts/lesson-06/Invoke-L06PlsDemo.ps1) | Demo 6.2: a partner requests private access to Contoso's parts API through a Private Link service, Contoso approves it, and the partner connects. Modes: `Settings`, `RequestConnection`, `Connections`, `Approve`, `Probe`. |
| Demo | [`Invoke-L06PrivateAccessDemo.ps1`](../../../lab/scripts/lesson-06/Invoke-L06PrivateAccessDemo.ps1) | Demo 6.3 support: read-only checks around Microsoft Entra Private Access for the ServiceHub private API. Separate scoped setup scripts configure the pilot; the user sign-in is interactive. Modes: `Readiness`, `Target`, `Connectors`. |
| Reset | [`Reset-L06Lab.ps1`](../../../lab/scripts/lesson-06/Reset-L06Lab.ps1) | Returns the Lesson 6 lab to CTSO-L06-BASELINE after you finish. |
| Clean up | [`Remove-L06Bounded.ps1`](../../../lab/scripts/lesson-06/Remove-L06Bounded.ps1) | Removes one bounded Lesson 6 lab after you finish, and proves it's gone. |
| Clean up | [`Remove-L06Lab.ps1`](../../../lab/scripts/lesson-06/Remove-L06Lab.ps1) | Deletes the parked Lesson 6 lab, in Azure and in Microsoft Entra, when you finish Lesson 6. |
| Helper | [`L06.Common.ps1`](../../../lab/scripts/lesson-06/L06.Common.ps1) | Shared helpers for the SC-500 Lesson 6 lab: pin the subscription, call Azure CLI safely, save private evidence, read deployment outputs, and run DNS and blob tests inside VMs. |

Python helpers, called by the PowerShell scripts: [`Get-L06ConnectorRegistrationToken.py`](../../../lab/scripts/lesson-06/Get-L06ConnectorRegistrationToken.py).

## Commands

Each command uses the full path from the one-time setup. Read a script's help first with `Get-Help <path> -Full`.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Connect-L06ConnectorRegistration.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Copy-L06ConnectorPassword.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Deploy-L06Bounded.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Deploy-L06Client.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Deploy-L06Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Install-L06Client.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Install-L06Connector.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Register-L06Connector.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Set-L06ConnectorGroup.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Set-L06MaintenanceEgress.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Set-L06PrivateAccessPilot.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Start-L06Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Start-L06PrivateAccessLab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Test-L06Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Invoke-L06DnsDemo.ps1 -Mode Settings
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Invoke-L06EndpointDemo.ps1 -Mode Settings
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Invoke-L06PlsDemo.ps1 -Mode Settings
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Invoke-L06PrivateAccessDemo.ps1 -Mode Readiness
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Reset-L06Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Remove-L06Bounded.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Remove-L06Lab.ps1
```

[Lesson README](../README.md) | [Lab setup](../../../lab/README.md) | [Course README](../../../README.md)
