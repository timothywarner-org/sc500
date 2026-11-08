# Lesson 07 lab files

The scripts for this lesson are in [`lab/scripts/lesson-07`](../../../lab/scripts/lesson-07/) and its Bicep templates and `config.json` are in [`lab/infra/lesson-07`](../../../lab/infra/lesson-07/).
Do the [one-time setup](../../../lab/README.md) before you run anything here.

> **Cost warning:** these scripts create real Azure resources. Run this lesson's `Remove-` script when you finish.

## Scripts by stage

Build first, check, run the demos, then reset or clean up. Within a stage, follow the demo order in the lesson.

| Stage | Script | What it does (from the script's own help) |
| --- | --- | --- |
| Build | [`Deploy-L07Bounded.ps1`](../../../lab/scripts/lesson-07/Deploy-L07Bounded.ps1) | Previews, or deploys, the bounded Lesson 7 resource: Azure Firewall Premium. |
| Build | [`Deploy-L07Lab.ps1`](../../../lab/scripts/lesson-07/Deploy-L07Lab.ps1) | Previews, or deploys, the retained SC-500 Lesson 7 perimeter lab and its firewall policy. |
| Build | [`Set-L07Policy.ps1`](../../../lab/scripts/lesson-07/Set-L07Policy.ps1) | Deploys the Lesson 7 firewall policy in its baseline or enforced state. |
| Build | [`Start-L07Lab.ps1`](../../../lab/scripts/lesson-07/Start-L07Lab.ps1) | Starts, or with -Stop deallocates, the two retained Lesson 7 VMs. |
| Check | [`Test-L07GuestHealth.ps1`](../../../lab/scripts/lesson-07/Test-L07GuestHealth.ps1) | Read Defender health and service connectivity on both running Lesson 7 guests. |
| Check | [`Test-L07Lab.ps1`](../../../lab/scripts/lesson-07/Test-L07Lab.ps1) | Read-only readiness check for the Lesson 7 lab at CTSO-L07-BASELINE. |
| Check | [`Test-L07Templates.ps1`](../../../lab/scripts/lesson-07/Test-L07Templates.ps1) | Verifies the Lesson 7 templates and scripts without deploying anything. |
| Demo | [`Invoke-L07DdosDemo.ps1`](../../../lab/scripts/lesson-07/Invoke-L07DdosDemo.ps1) | Inspect, or briefly enable and restore, DDoS IP Protection on the lesson's public IP. Modes: `Inspect`, `Demonstrate`. |
| Demo | [`Invoke-L07DiagnosticsDemo.ps1`](../../../lab/scripts/lesson-07/Invoke-L07DiagnosticsDemo.ps1) | Demo 7.3 (and the DDoS check for 7.4): what Network Watcher and the NIC can tell you about a flow, and what they can't. Modes: `NextHop`, `FlowVerify`, `EffectiveRoutes`, `EffectiveRules`, `Ddos`, `All`. |
| Demo | [`Invoke-L07FirewallDemo.ps1`](../../../lab/scripts/lesson-07/Invoke-L07FirewallDemo.ps1) | Demo 7.1: read what Azure Firewall Premium did to ServiceHub's traffic, then enforce. Modes: `Status`, `Idps`, `Enforce`, `Logs`. |
| Reset | [`Reset-L07Lab.ps1`](../../../lab/scripts/lesson-07/Reset-L07Lab.ps1) | Returns the Lesson 7 lab to CTSO-L07-BASELINE after you finish. |
| Clean up | [`Remove-L07Bounded.ps1`](../../../lab/scripts/lesson-07/Remove-L07Bounded.ps1) | Deletes the Lesson 7 firewall after you finish, and proves it's gone. |
| Clean up | [`Remove-L07Lab.ps1`](../../../lab/scripts/lesson-07/Remove-L07Lab.ps1) | Deletes the whole Lesson 7 lab (retained and bounded) when the course no longer needs it. |
| Helper | [`L07.Common.ps1`](../../../lab/scripts/lesson-07/L07.Common.ps1) | Shared helpers for the SC-500 Lesson 7 lab: pin the subscription, call Azure CLI safely, save private evidence, read deployment outputs, build the TLS inspection CA in memory, and read the lab's results through the firewall instead of through Run Command. |

## Commands

Each command uses the full path from the one-time setup. Read a script's help first with `Get-Help <path> -Full`.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Deploy-L07Bounded.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Deploy-L07Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Set-L07Policy.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Start-L07Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Test-L07GuestHealth.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Test-L07Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Test-L07Templates.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Invoke-L07DdosDemo.ps1 -Mode Inspect
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Invoke-L07DiagnosticsDemo.ps1 -Mode NextHop
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Invoke-L07FirewallDemo.ps1 -Mode Status
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Reset-L07Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Remove-L07Bounded.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Remove-L07Lab.ps1
```

[Lesson README](../README.md) | [Lab setup](../../../lab/README.md) | [Course README](../../../README.md)
