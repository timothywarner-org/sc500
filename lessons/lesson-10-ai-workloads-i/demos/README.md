# Lesson 10 lab files

The scripts for this lesson are in [`lab/scripts/lesson-10`](../../../lab/scripts/lesson-10/) and its Bicep templates and `config.json` are in [`lab/infra/lesson-10`](../../../lab/infra/lesson-10/).
Do the [one-time setup](../../../lab/README.md) before you run anything here.

> **Cost warning:** these scripts create real Azure resources. Run this lesson's `Remove-` script when you finish.

## Scripts by stage

Build first, check, run the demos, then reset or clean up. Within a stage, follow the demo order in the lesson.

| Stage | Script | What it does (from the script's own help) |
| --- | --- | --- |
| Build | [`Deploy-L10Lab.ps1`](../../../lab/scripts/lesson-10/Deploy-L10Lab.ps1) | Deploys the SC-500 Lesson 10 lab: ServiceHub's agent identities in Microsoft Entra Agent ID, two report-only Conditional Access policies for agents, and the assistant's knowledge store. |
| Check | [`Test-L10Lab.ps1`](../../../lab/scripts/lesson-10/Test-L10Lab.ps1) | Read-only readiness check for the Lesson 10 lab at CTSO-L10-BASELINE. |
| Demo | [`Invoke-L10AgentDemo.ps1`](../../../lab/scripts/lesson-10/Invoke-L10AgentDemo.ps1) | Demos 10.3 and 10.4: ServiceHub's agent identities in Microsoft Entra Agent ID, the Conditional Access policies that apply to them, what each agent can reach, and the lifecycle controls that stop it. Modes: `Inventory`, `Policies`, `Token`, `SignIns`, `Reach`, `Scope`, `Disable`, `All`. |
| Demo | [`Invoke-L10DataDemo.ps1`](../../../lab/scripts/lesson-10/Invoke-L10DataDemo.ps1) | Demos 10.1 and 10.2, the scripted half: who can use Microsoft 365 Copilot in the tenant, and how every Copilot Studio agent in each Power Platform environment authenticates its users. Modes: `Copilot`, `Agents`, `All`. |
| Reset | [`Reset-L10Lab.ps1`](../../../lab/scripts/lesson-10/Reset-L10Lab.ps1) | Puts the Lesson 10 lab back at CTSO-L10-BASELINE between takes. |
| Clean up | [`Remove-L10Lab.ps1`](../../../lab/scripts/lesson-10/Remove-L10Lab.ps1) | Deletes the whole Lesson 10 lab. Your call, not a routine step. |
| Helper | [`L10.Common.ps1`](../../../lab/scripts/lesson-10/L10.Common.ps1) | Shared helpers for the SC-500 Lesson 10 lab: pin the subscription and tenant, call Azure CLI safely, save private evidence, call ARM and Microsoft Graph, find the lab's agent identity objects, and run the Microsoft Entra Agent ID autonomous token flow. |

## Commands

Each command uses the full path from the one-time setup. Read a script's help first with `Get-Help <path> -Full`.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-10\Deploy-L10Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-10\Test-L10Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-10\Invoke-L10AgentDemo.ps1 -Mode Inventory
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-10\Invoke-L10DataDemo.ps1 -Mode Copilot
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-10\Reset-L10Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-10\Remove-L10Lab.ps1
```

[Lesson README](../README.md) | [Lab setup](../../../lab/README.md) | [Course README](../../../README.md)
