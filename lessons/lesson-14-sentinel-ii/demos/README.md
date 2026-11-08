# Lesson 14 lab files

The scripts for this lesson are in [`lab/scripts/lesson-14`](../../../lab/scripts/lesson-14/) and its Bicep templates and `config.json` are in [`lab/infra/lesson-14`](../../../lab/infra/lesson-14/).
Do the [one-time setup](../../../lab/README.md) before you run anything here.

> **Cost warning:** these scripts create real Azure resources. Run this lesson's `Remove-` script when you finish.

## Scripts by stage

Build first, check, run the demos, then reset or clean up. Within a stage, follow the demo order in the lesson.

| Stage | Script | What it does (from the script's own help) |
| --- | --- | --- |
| Build | [`Deploy-L14Lab.ps1`](../../../lab/scripts/lesson-14/Deploy-L14Lab.ps1) | Deploys the SC-500 Lesson 14 lab: detection and response on Lesson 13's Microsoft Sentinel workspace, with no VMs and no standing compute. |
| Build | [`Enable-L14Audit.ps1`](../../../lab/scripts/lesson-14/Enable-L14Audit.ps1) | Enable unified auditing after you explicitly approves this tenant-wide prerequisite. |
| Check | [`Test-L14Contracts.ps1`](../../../lab/scripts/lesson-14/Test-L14Contracts.ps1) | Offline regression tests for L14 case selection and evidence rejection, with no Azure calls. |
| Check | [`Test-L14Lab.ps1`](../../../lab/scripts/lesson-14/Test-L14Lab.ps1) | Read-only readiness check for the SC-500 Lesson 14 lab. Exits 1 on any FAIL. |
| Demo | [`Invoke-L14AuditDemo.ps1`](../../../lab/scripts/lesson-14/Invoke-L14AuditDemo.ps1) | Demo 14.4: stage one genuine Microsoft 365 action for Microsoft Purview Audit, check for it where a script is allowed to look, and assemble the case timeline. Modes: `Stage`, `Office`, `Timeline`. |
| Demo | [`Invoke-L14DetectionDemo.ps1`](../../../lab/scripts/lesson-14/Invoke-L14DetectionDemo.ps1) | Demo 14.1: the ServiceHub export rule, a labeled fixture, tuning, and the alert and incident Microsoft Sentinel actually created. Modes: `Rule`, `Send`, `Fixture`, `Tune`, `Alert`, `History`. |
| Demo | [`Invoke-L14HuntDemo.ps1`](../../../lab/scripts/lesson-14/Invoke-L14HuntDemo.ps1) | Demo 14.3: one hypothesis carried through saved hunting queries, the investigation workbook, and a notebook that ends in a short report. Modes: `Queries`, `Workbook`, `Notebook`. |
| Demo | [`Invoke-L14ResponseDemo.ps1`](../../../lab/scripts/lesson-14/Invoke-L14ResponseDemo.ps1) | Demo 14.2: the automation rule, the playbook, the identities that let them run, and the proof that the playbook actually ran on the incident. Modes: `Automation`, `Playbook`, `Trace`. |
| Reset | [`Reset-L14Lab.ps1`](../../../lab/scripts/lesson-14/Reset-L14Lab.ps1) | Routine cleanup between Lesson 14 rehearsals: closes rehearsal incidents from the export rule. |
| Clean up | [`Remove-L14Lab.ps1`](../../../lab/scripts/lesson-14/Remove-L14Lab.ps1) | Your step after Lesson 15: removes everything Lesson 14 added and leaves Lesson 13 intact. |
| Helper | [`L14.Common.ps1`](../../../lab/scripts/lesson-14/L14.Common.ps1) | Shared helpers for the SC-500 Lesson 14 lab: pin the subscription and tenant, call Azure CLI safely, save private evidence, call ARM, query the Lesson 13 Sentinel workspace, and read both lessons' deployment outputs. |
| Helper | [`L14.ReviewChecks.ps1`](../../../lab/scripts/lesson-14/L14.ReviewChecks.ps1) | Evidence contracts for the selected L14 case and its handoff to L15. |

## Commands

Each command uses the full path from the one-time setup. Read a script's help first with `Get-Help <path> -Full`.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Deploy-L14Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Enable-L14Audit.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Test-L14Contracts.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Test-L14Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Invoke-L14AuditDemo.ps1 -Mode Stage
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Invoke-L14DetectionDemo.ps1 -Mode Rule
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Invoke-L14HuntDemo.ps1 -Mode Queries
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Invoke-L14ResponseDemo.ps1 -Mode Automation
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Reset-L14Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Remove-L14Lab.ps1
```

[Lesson README](../README.md) | [Lab setup](../../../lab/README.md) | [Course README](../../../README.md)
