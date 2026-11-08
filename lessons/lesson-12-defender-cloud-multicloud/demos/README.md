# Lesson 12 lab files

The scripts for this lesson are in [`lab/scripts/lesson-12`](../../../lab/scripts/lesson-12/) and its Bicep templates and `config.json` are in [`lab/infra/lesson-12`](../../../lab/infra/lesson-12/).
Do the [one-time setup](../../../lab/README.md) before you run anything here.

> **Cost warning:** these scripts create real Azure resources. Run this lesson's `Remove-` script when you finish.

## Scripts by stage

Build first, check, run the demos, then reset or clean up. Within a stage, follow the demo order in the lesson.

| Stage | Script | What it does (from the script's own help) |
| --- | --- | --- |
| Build | [`Deploy-L12Lab.ps1`](../../../lab/scripts/lesson-12/Deploy-L12Lab.ps1) | Deploys the SC-500 Lesson 12 lab: ServiceHub's parts-export store (the posture fixture) and a Defender EASM workspace seeded with your own domain. |
| Build | [`Set-L12DefenderWindow.ps1`](../../../lab/scripts/lesson-12/Set-L12DefenderWindow.ps1) | Opens or closes the Lesson 12 Defender window: Defender CSPM and Defender for Storage on the subscription. |
| Check | [`Test-L12Contracts.ps1`](../../../lab/scripts/lesson-12/Test-L12Contracts.ps1) | Run offline regression cases for the L12 evidence and cleanup contracts. |
| Check | [`Test-L12Lab.ps1`](../../../lab/scripts/lesson-12/Test-L12Lab.ps1) | Readiness check for the SC-500 Lesson 12 lab (CTSO-L12-BASELINE). Read-only. |
| Check | [`Wait-L12Assessment.ps1`](../../../lab/scripts/lesson-12/Wait-L12Assessment.ps1) | Waits for Defender's real L12 Shared Key assessment without manufacturing a finding. |
| Demo | [`Invoke-L12CloudDemo.ps1`](../../../lab/scripts/lesson-12/Invoke-L12CloudDemo.ps1) | SC-500 demo 12.3: read what Defender for Cloud covers beyond Azure: AWS and GCP connectors and Azure Arc-enabled servers. Read-only. Modes: `Connectors`, `Hybrid`, `All`. |
| Demo | [`Invoke-L12EasmDemo.ps1`](../../../lab/scripts/lesson-12/Invoke-L12EasmDemo.ps1) | SC-500 demo 12.4: read what Defender EASM discovered from ServiceHub's seed (your own domain), what needs an ownership decision, and what it flags as a priority. Read-only. Modes: `Discovery`, `Inventory`, `Priorities`, `Billable`, `All`. |
| Demo | [`Invoke-L12PlanDemo.ps1`](../../../lab/scripts/lesson-12/Invoke-L12PlanDemo.ps1) | SC-500 demo 12.2: read Defender for Cloud's workload protection plans, then configure one plan for one resource: Defender for Storage on ServiceHub's parts-export store. Modes: `Plans`, `StorageRead`, `StorageOverride`, `Scan`, `All`. |
| Demo | [`Invoke-L12PostureDemo.ps1`](../../../lab/scripts/lesson-12/Invoke-L12PostureDemo.ps1) | SC-500 demo 12.1: read ServiceHub's security posture in Defender CSPM, fix one finding on the parts-export store, prove the fix, and trace it through compliance and governance. Modes: `Score`, `Findings`, `Remediate`, `Receipt`, `Compliance`, `Governance`, `Assign`, `Secrets`, `All`. |
| Reset | [`Reset-L12Lab.ps1`](../../../lab/scripts/lesson-12/Reset-L12Lab.ps1) | Returns the SC-500 Lesson 12 lab to its idle baseline (CTSO-L12-BASELINE) after a rehearsal or a demo run, and reads back that every change is undone. |
| Clean up | [`Remove-L12Lab.ps1`](../../../lab/scripts/lesson-12/Remove-L12Lab.ps1) | Deletes the SC-500 Lesson 12 lab. Your step. |
| Helper | [`L12.Checks.ps1`](../../../lab/scripts/lesson-12/L12.Checks.ps1) | Pure evidence checks for L12, separated so failures can be tested without changing Azure. |
| Helper | [`L12.Common.ps1`](../../../lab/scripts/lesson-12/L12.Common.ps1) | Shared helpers for the SC-500 Lesson 12 lab: pin the subscription and tenant, call Azure CLI safely, save private evidence, call ARM, Azure Resource Graph, and the Defender EASM data plane, and read the lab's outputs. |
| Helper | [`L12.Verdict.ps1`](../../../lab/scripts/lesson-12/L12.Verdict.ps1) | Write-L12Verdict: end a Lesson 12 demo mode with a short "What this run proves" table. |

## Commands

Each command uses the full path from the one-time setup. Read a script's help first with `Get-Help <path> -Full`.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Deploy-L12Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Set-L12DefenderWindow.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Test-L12Contracts.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Test-L12Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Wait-L12Assessment.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Invoke-L12CloudDemo.ps1 -Mode Connectors
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Invoke-L12EasmDemo.ps1 -Mode Discovery
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Invoke-L12PlanDemo.ps1 -Mode Plans
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Invoke-L12PostureDemo.ps1 -Mode Score
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Reset-L12Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Remove-L12Lab.ps1
```

[Lesson README](../README.md) | [Lab setup](../../../lab/README.md) | [Course README](../../../README.md)
