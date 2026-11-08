# Lesson 08 lab files

The scripts for this lesson are in [`lab/scripts/lesson-08`](../../../lab/scripts/lesson-08/) and its Bicep templates and `config.json` are in [`lab/infra/lesson-08`](../../../lab/infra/lesson-08/).
Do the [one-time setup](../../../lab/README.md) before you run anything here.

> **Cost warning:** these scripts create real Azure resources. Run this lesson's `Remove-` script when you finish.

## Scripts by stage

Build first, check, run the demos, then reset or clean up. Within a stage, follow the demo order in the lesson.

| Stage | Script | What it does (from the script's own help) |
| --- | --- | --- |
| Build | [`Deploy-L08Bounded.ps1`](../../../lab/scripts/lesson-08/Deploy-L08Bounded.ps1) | Creates the bounded legacy VM for SC-500 Lesson 8 demos 8.1 and 8.2. |
| Build | [`Deploy-L08Lab.ps1`](../../../lab/scripts/lesson-08/Deploy-L08Lab.ps1) | Previews, or deploys, the retained SC-500 Lesson 8 servers lab. |
| Build | [`Set-L08DefenderWindow.ps1`](../../../lab/scripts/lesson-08/Set-L08DefenderWindow.ps1) | Opens or closes the Lesson 8 Defender window: Defender for Servers Plan 2 on the subscription. |
| Build | [`Start-L08Lab.ps1`](../../../lab/scripts/lesson-08/Start-L08Lab.ps1) | Starts, or with -Stop deallocates, the Lesson 8 VMs. |
| Check | [`Test-L08Lab.ps1`](../../../lab/scripts/lesson-08/Test-L08Lab.ps1) | Read-only readiness check for the Lesson 8 lab at CTSO-L08-BASELINE. |
| Check | [`Test-L08Templates.ps1`](../../../lab/scripts/lesson-08/Test-L08Templates.ps1) | Verifies the Lesson 8 templates and scripts without deploying anything. |
| Demo | [`Invoke-L08AccessDemo.ps1`](../../../lab/scripts/lesson-08/Invoke-L08AccessDemo.ps1) | Demo 8.2 for SC-500 Lesson 8: admin access without public IPs (Azure Bastion), and for the server that still has one, just-in-time access through Defender for Cloud. Modes: `Bastion`, `Probe`, `Rules`, `EnableJit`, `RemoveStanding`, `Request`, `Policy`, `Sequence`. |
| Demo | [`Invoke-L08ConfigDemo.ps1`](../../../lab/scripts/lesson-08/Invoke-L08ConfigDemo.ps1) | Demo 8.4 for SC-500 Lesson 8: machine configuration's verdict on each server, and what Defender Vulnerability Management reports and how it's set. Modes: `Assignments`, `Rules`, `Recommendations`, `Vulnerabilities`, `Settings`, `All`. |
| Demo | [`Invoke-L08HostDemo.ps1`](../../../lab/scripts/lesson-08/Invoke-L08HostDemo.ps1) | Demo 8.1 for SC-500 Lesson 8: what Trusted Launch and encryption at host look like on a server, from Azure's side and from the guest's side. Modes: `Profile`, `Guest`, `Attestation`, `Disks`, `Policy`, `Scan`, `All`. |
| Demo | [`Invoke-L08HybridDemo.ps1`](../../../lab/scripts/lesson-08/Invoke-L08HybridDemo.ps1) | Demo 8.3 for SC-500 Lesson 8: bring a non-Azure server under Azure Arc and Defender for Servers, then read what Defender does for it: EDR, vulnerability assessment, agentless scanning. Modes: `Readiness`, `Command`, `Arc`, `Coverage`, `Scanning`, `All`. |
| Reset | [`Reset-L08Access.ps1`](../../../lab/scripts/lesson-08/Reset-L08Access.ps1) | Puts the legacy app server back at the access demo's starting point WITHOUT changing its public IP. |
| Reset | [`Reset-L08Lab.ps1`](../../../lab/scripts/lesson-08/Reset-L08Lab.ps1) | Returns the Lesson 8 lab to CTSO-L08-BASELINE after you finish. |
| Clean up | [`Remove-L08Bounded.ps1`](../../../lab/scripts/lesson-08/Remove-L08Bounded.ps1) | Deletes the bounded part of SC-500 Lesson 8: the lesson's JIT policy, the legacy app server (vm-legacyapp-prod-001), its public IP, and its NSG. |
| Clean up | [`Remove-L08Lab.ps1`](../../../lab/scripts/lesson-08/Remove-L08Lab.ps1) | Deletes the whole Lesson 8 lab when the course no longer needs it. Your call, not a routine step. |
| Helper | [`L08.Common.ps1`](../../../lab/scripts/lesson-08/L08.Common.ps1) | Shared helpers for the SC-500 Lesson 8 lab: pin the subscription, call Azure CLI safely, save private evidence, read deployment outputs, call ARM and Resource Graph, read each VM's own evidence from its serial log, and probe a TCP port without signing in. |

## Commands

Each command uses the full path from the one-time setup. Read a script's help first with `Get-Help <path> -Full`.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Deploy-L08Bounded.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Deploy-L08Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Set-L08DefenderWindow.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Start-L08Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Test-L08Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Test-L08Templates.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Invoke-L08AccessDemo.ps1 -Mode Bastion
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Invoke-L08ConfigDemo.ps1 -Mode Assignments
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Invoke-L08HostDemo.ps1 -Mode Profile
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Invoke-L08HybridDemo.ps1 -Mode Readiness
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Reset-L08Access.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Reset-L08Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Remove-L08Bounded.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Remove-L08Lab.ps1
```

[Lesson README](../README.md) | [Lab setup](../../../lab/README.md) | [Course README](../../../README.md)
