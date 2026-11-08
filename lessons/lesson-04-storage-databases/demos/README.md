# Lesson 04 lab files

The scripts for this lesson are in [`lab/scripts/lesson-04`](../../../lab/scripts/lesson-04/) and its Bicep templates and `config.json` are in [`lab/infra/lesson-04`](../../../lab/infra/lesson-04/).
Do the [one-time setup](../../../lab/README.md) before you run anything here.

> **Cost warning:** these scripts create real Azure resources. Run this lesson's `Remove-` script when you finish.

## Scripts by stage

Build first, check, run the demos, then reset or clean up. Within a stage, follow the demo order in the lesson.

| Stage | Script | What it does (from the script's own help) |
| --- | --- | --- |
| Build | [`Deploy-L04Lab.ps1`](../../../lab/scripts/lesson-04/Deploy-L04Lab.ps1) | Previews, or deploys and seeds, the SC-500 Lesson 4 storage and SQL lab in the course subscription. |
| Build | [`Set-L04DefenderWindow.ps1`](../../../lab/scripts/lesson-04/Set-L04DefenderWindow.ps1) | Opens or closes the Lesson 4 Defender window around a demo: plans, account settings, vulnerability assessment. |
| Build | [`Set-L04SharedKeyGuardrail.ps1`](../../../lab/scripts/lesson-04/Set-L04SharedKeyGuardrail.ps1) | Demonstrates Audit and Deny on the Lesson 4 records account only. Modes: `Audit`, `Deny`, `Probe`, `Inspect`. |
| Check | [`Test-L04Lab.ps1`](../../../lab/scripts/lesson-04/Test-L04Lab.ps1) | Read-only readiness check: is the Lesson 4 lab at CTSO-L04-BASELINE, ready to record? |
| Demo | [`Invoke-L04DefenderDemo.ps1`](../../../lab/scripts/lesson-04/Invoke-L04DefenderDemo.ps1) | Demos 4.2 and 4.4 helper: Defender for Storage and Defender for Databases coverage, configuration, and evidence for the Lesson 4 resources. Modes: `Plans`, `StorageSettings`, `OverrideIntake`, `UploadClean`, `ScanResults`, `SqlCoverage`, `VaResults`. |
| Demo | [`Invoke-L04EicarTest.ps1`](../../../lab/scripts/lesson-04/Invoke-L04EicarTest.ps1) | Uploads the official harmless EICAR fixture directly from memory to the Lesson 4 intake. |
| Demo | [`Invoke-L04SqlDemo.ps1`](../../../lab/scripts/lesson-04/Invoke-L04SqlDemo.ps1) | Demo 4.3 helper: Azure SQL platform settings, a rejected SQL-authentication login, an Entra-authenticated query, and the audit records those attempts produced. Modes: `Settings`, `SqlLogin`, `EntraQuery`, `Audit`. |
| Demo | [`Invoke-L04StorageDemo.ps1`](../../../lab/scripts/lesson-04/Invoke-L04StorageDemo.ps1) | Demo 4.1 helper: shows each storage control's effect on a real request, allowed and rejected, and saves the responses as private evidence. Modes: `Settings`, `Firewall`, `AllowWorkstation`, `KeyRead`, `PolicySas`, `DisableSharedKey`, `EntraRead`. |
| Demo | [`Show-L04DatabasePlanConfiguration.ps1`](../../../lab/scripts/lesson-04/Show-L04DatabasePlanConfiguration.ps1) | Shows the exact REST configuration request and current state for each database plan. |
| Reset | [`Reset-L04Lab.ps1`](../../../lab/scripts/lesson-04/Reset-L04Lab.ps1) | Returns the Lesson 4 lab to CTSO-L04-BASELINE so any demo can be recorded again. |
| Clean up | [`Remove-L04Lab.ps1`](../../../lab/scripts/lesson-04/Remove-L04Lab.ps1) | Decommissions the Lesson 4 lab: records what exists, confirms the Defender window is parked, then deletes rg-sc500-l04-data. |
| Helper | [`L04.Common.ps1`](../../../lab/scripts/lesson-04/L04.Common.ps1) | Shared helpers for the SC-500 Lesson 4 lab: pin the subscription, call Azure CLI safely, save private evidence, and read the deployed resource names back from ARM. |

Python helpers, called by the PowerShell scripts: [`read_blob_properties.py`](../../../lab/scripts/lesson-04/read_blob_properties.py), [`upload_eicar.py`](../../../lab/scripts/lesson-04/upload_eicar.py).

## Commands

Each command uses the full path from the one-time setup. Read a script's help first with `Get-Help <path> -Full`.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-04\Deploy-L04Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-04\Set-L04DefenderWindow.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-04\Set-L04SharedKeyGuardrail.ps1 -Mode Audit
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-04\Test-L04Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-04\Invoke-L04DefenderDemo.ps1 -Mode Plans
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-04\Invoke-L04EicarTest.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-04\Invoke-L04SqlDemo.ps1 -Mode Settings
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-04\Invoke-L04StorageDemo.ps1 -Mode Settings
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-04\Show-L04DatabasePlanConfiguration.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-04\Reset-L04Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-04\Remove-L04Lab.ps1
```

[Lesson README](../README.md) | [Lab setup](../../../lab/README.md) | [Course README](../../../README.md)
