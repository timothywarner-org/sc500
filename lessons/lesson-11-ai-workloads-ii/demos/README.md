# Lesson 11 lab files

The scripts for this lesson are in [`lab/scripts/lesson-11`](../../../lab/scripts/lesson-11/) and its Bicep templates and `config.json` are in [`lab/infra/lesson-11`](../../../lab/infra/lesson-11/).
Do the [one-time setup](../../../lab/README.md) before you run anything here.

> **Cost warning:** these scripts create real Azure resources. Run this lesson's `Remove-` script when you finish.

## Scripts by stage

Build first, check, run the demos, then reset or clean up. Within a stage, follow the demo order in the lesson.

| Stage | Script | What it does (from the script's own help) |
| --- | --- | --- |
| Build | [`Deploy-L11Lab.ps1`](../../../lab/scripts/lesson-11/Deploy-L11Lab.ps1) | Deploys the SC-500 Lesson 11 lab: ServiceHub's Foundry implementation (retained) and, on request, the AI gateway (bounded, billed by the hour). |
| Check | [`Test-L11Contracts.ps1`](../../../lab/scripts/lesson-11/Test-L11Contracts.ps1) | Offline regression cases for L11 recording assertions and agent evidence. |
| Check | [`Test-L11Lab.ps1`](../../../lab/scripts/lesson-11/Test-L11Lab.ps1) | Readiness check for the SC-500 Lesson 11 lab (CTSO-L11-BASELINE). Read-only. |
| Demo | [`Get-L11InvestigationEvidence.ps1`](../../../lab/scripts/lesson-11/Get-L11InvestigationEvidence.ps1) | Read gateway diagnostics for one recorded L11 request, using its ID and bounded UTC window. |
| Demo | [`Invoke-L11DefenderDemo.ps1`](../../../lab/scripts/lesson-11/Invoke-L11DefenderDemo.ps1) | SC-500 demos 11.2 and 11.4: read Defender for AI Services coverage, the AI alerts it raised for ServiceHub's Foundry resource, and the audit evidence around them. Read-only. Modes: `Plan`, `Alerts`, `Audit`, `All`. |
| Demo | [`Invoke-L11GatewayDemo.ps1`](../../../lab/scripts/lesson-11/Invoke-L11GatewayDemo.ps1) | SC-500 demo 11.1: prove ServiceHub's model is reachable only through the AI gateway, and that the gateway enforces a token budget per caller. Modes: `Direct`, `Gateway`, `Burst`, `Logs`, `All`. |
| Demo | [`Invoke-L11GuardrailDemo.ps1`](../../../lab/scripts/lesson-11/Invoke-L11GuardrailDemo.ps1) | SC-500 demo 11.3: exercise ServiceHub's guardrail at the model and at the agent. Modes: `Benign`, `BlocklistIn`, `BlocklistOut`, `Jailbreak`, `Model`, `AgentInherited`, `AgentGuarded`, `AgentAsk`, `PrepareAgents`, `AgentCompare`, `All`. |
| Reset | [`Reset-L11Lab.ps1`](../../../lab/scripts/lesson-11/Reset-L11Lab.ps1) | Returns the SC-500 Lesson 11 lab to CTSO-L11-BASELINE after you finish: removes the bounded AI gateway (API Management Basic v2) and purges its soft-deleted copy. |
| Clean up | [`Remove-L11Lab.ps1`](../../../lab/scripts/lesson-11/Remove-L11Lab.ps1) | Deletes the whole SC-500 Lesson 11 lab. Your step, after you finish the lesson. |
| Helper | [`L11.AgentEvidence.ps1`](../../../lab/scripts/lesson-11/L11.AgentEvidence.ps1) | Build pinned prompt-agent requests and preserve bounded, credential-free evidence. |
| Helper | [`L11.Checks.ps1`](../../../lab/scripts/lesson-11/L11.Checks.ps1) | Pure Lesson 11 contract checks, shared by live readiness and offline regression cases. |
| Helper | [`L11.Common.ps1`](../../../lab/scripts/lesson-11/L11.Common.ps1) | Shared helpers for the SC-500 Lesson 11 lab: pin the subscription and tenant, call Azure CLI safely, save private evidence, call ARM, Foundry, and the gateway, and read the lab's outputs. |

## Commands

Each command uses the full path from the one-time setup. Read a script's help first with `Get-Help <path> -Full`.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-11\Deploy-L11Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-11\Test-L11Contracts.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-11\Test-L11Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-11\Get-L11InvestigationEvidence.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-11\Invoke-L11DefenderDemo.ps1 -Mode Plan
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-11\Invoke-L11GatewayDemo.ps1 -Mode Direct
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-11\Invoke-L11GuardrailDemo.ps1 -Mode Benign
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-11\Reset-L11Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-11\Remove-L11Lab.ps1
```

[Lesson README](../README.md) | [Lab setup](../../../lab/README.md) | [Course README](../../../README.md)
