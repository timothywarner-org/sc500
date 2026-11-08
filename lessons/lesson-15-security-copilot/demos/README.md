# Lesson 15 lab files

The scripts for this lesson are in [`lab/scripts/lesson-15`](../../../lab/scripts/lesson-15/) and its Bicep templates and `config.json` are in [`lab/infra/lesson-15`](../../../lab/infra/lesson-15/).
Do the [one-time setup](../../../lab/README.md) before you run anything here.

> **Cost warning:** these scripts create real Azure resources. Run this lesson's `Remove-` script when you finish.

## Scripts by stage

Build first, check, run the demos, then reset or clean up. Within a stage, follow the demo order in the lesson.

| Stage | Script | What it does (from the script's own help) |
| --- | --- | --- |
| Build | [`Deploy-L15Lab.ps1`](../../../lab/scripts/lesson-15/Deploy-L15Lab.ps1) | Deploys the SC-500 Lesson 15 cost guardrail: the guarded resource group, a least-privilege custom role, and the Security Copilot capacity reaper. It never creates a capacity. |
| Build | [`Start-L15CopilotSession.ps1`](../../../lab/scripts/lesson-15/Start-L15CopilotSession.ps1) | Your step after you create the Security Copilot capacity: puts a deadline on it, so the reaper deletes it when the session is over. |
| Check | [`Test-L15Lab.ps1`](../../../lab/scripts/lesson-15/Test-L15Lab.ps1) | Read-only service checks for SC-500 Lesson 15; writes private evidence locally. |
| Demo | [`Invoke-L15CopilotDemo.ps1`](../../../lab/scripts/lesson-15/Invoke-L15CopilotDemo.ps1) | Lesson 15 demo readouts: the capacity and its clock, your access, the ServiceHub plugin's ground truth, and the case ledger that every Security Copilot answer is checked against. Modes: `Capacity`, `Access`, `Plugin`, `Case`. |
| Reset | [`Reset-L15Lab.ps1`](../../../lab/scripts/lesson-15/Reset-L15Lab.ps1) | Returns Lesson 15 to its starting checkpoint between runs: the pinned case open, no paid capacity. |
| Reset | [`Stop-L15CopilotSession.ps1`](../../../lab/scripts/lesson-15/Stop-L15CopilotSession.ps1) | Your step when you finish Lesson 15: deletes the Security Copilot capacity in the guarded group now and confirms it's gone, so provisioned billing stops at the end of the current hour. |
| Clean up | [`Remove-L15Lab.ps1`](../../../lab/scripts/lesson-15/Remove-L15Lab.ps1) | Your step after you finish Lesson 15: removes the reaper, its custom role, and the guarded group. |
| Helper | [`L15.Common.ps1`](../../../lab/scripts/lesson-15/L15.Common.ps1) | Shared helpers for the SC-500 Lesson 15 lab: pin the subscription and tenant, call Azure CLI safely, save private evidence, call ARM and Microsoft Graph (read-only), query the Lesson 13 Sentinel workspace, and read Lesson 14's pinned case. |
| Helper | [`L15.RecordingGates.ps1`](../../../lab/scripts/lesson-15/L15.RecordingGates.ps1) | Pure checks for Lesson 15 capacity and observed portal evidence. |

## Commands

Each command uses the full path from the one-time setup. Read a script's help first with `Get-Help <path> -Full`.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-15\Deploy-L15Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-15\Start-L15CopilotSession.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-15\Test-L15Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-15\Invoke-L15CopilotDemo.ps1 -Mode Capacity
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-15\Reset-L15Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-15\Stop-L15CopilotSession.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-15\Remove-L15Lab.ps1
```

[Lesson README](../README.md) | [Lab setup](../../../lab/README.md) | [Course README](../../../README.md)
