# Lesson 13 lab files

The scripts for this lesson are in [`lab/scripts/lesson-13`](../../../lab/scripts/lesson-13/) and its Bicep templates and `config.json` are in [`lab/infra/lesson-13`](../../../lab/infra/lesson-13/).
Do the [one-time setup](../../../lab/README.md) before you run anything here.

> **Cost warning:** these scripts create real Azure resources. Run this lesson's `Remove-` script when you finish.

## Scripts by stage

Build first, check, run the demos, then reset or clean up. Within a stage, follow the demo order in the lesson.

| Stage | Script | What it does (from the script's own help) |
| --- | --- | --- |
| Build | [`Deploy-L13Lab.ps1`](../../../lab/scripts/lesson-13/Deploy-L13Lab.ps1) | Deploys the SC-500 Lesson 13 lab: a Microsoft Sentinel workspace for ServiceHub, every ingestion route the lesson demonstrates, and two private collector VMs. |
| Build | [`Start-L13Lab.ps1`](../../../lab/scripts/lesson-13/Start-L13Lab.ps1) | Starts the Lesson 13 collectors for a session: recreates the temporary NAT gateway, attaches it to the collectors' subnet, and starts both VMs. |
| Check | [`Test-L13Contracts.ps1`](../../../lab/scripts/lesson-13/Test-L13Contracts.ps1) | Offline regression tests for cumulative RBAC grants and the demo evidence boundary. |
| Check | [`Test-L13Lab.ps1`](../../../lab/scripts/lesson-13/Test-L13Lab.ps1) | Read-only readiness check for the Lesson 13 lab. Exits 1 on any FAIL. |
| Demo | [`Invoke-L13ConnectorDemo.ps1`](../../../lab/scripts/lesson-13/Invoke-L13ConnectorDemo.ps1) | Demo 13.2: which sources reach the ServiceHub workspace, by which route, into which table. Modes: `Sources`, `Routes`, `Probe`, `Trace`. |
| Demo | [`Invoke-L13HostDemo.ps1`](../../../lab/scripts/lesson-13/Invoke-L13HostDemo.ps1) | Demo 13.3: Syslog and CEF through the Linux forwarder, and Windows Security events directly and through Windows Event Forwarding (WEF). Modes: `Routes`, `Send`, `Failure`, `Wef`, `Trace`. |
| Demo | [`Invoke-L13TableDemo.ps1`](../../../lab/scripts/lesson-13/Invoke-L13TableDemo.ps1) | Demo 13.4: ServiceHub's own audit events in a custom table, and how long each table keeps data. Modes: `Schema`, `Send`, `Trace`, `Retention`, `SetTotal`. |
| Demo | [`Invoke-L13WorkspaceDemo.ps1`](../../../lab/scripts/lesson-13/Invoke-L13WorkspaceDemo.ps1) | Demo 13.1: the ServiceHub Sentinel workspace and who may do what in it. Modes: `Workspace`, `Roles`, `Assign`, `Access`. |
| Reset | [`Reset-L13Lab.ps1`](../../../lab/scripts/lesson-13/Reset-L13Lab.ps1) | Routine cleanup after a Lesson 13 take: removes the demo role assignments and puts the custom table's retention back, then reads both back. |
| Reset | [`Stop-L13Lab.ps1`](../../../lab/scripts/lesson-13/Stop-L13Lab.ps1) | Returns the Lesson 13 lab to its idle baseline: deallocates both collectors and deletes the temporary NAT gateway and its public IP. |
| Clean up | [`Remove-L13Lab.ps1`](../../../lab/scripts/lesson-13/Remove-L13Lab.ps1) | Your step, after you finish Lesson 14: deletes the Lesson 13 lab. |
| Helper | [`L13.Common.ps1`](../../../lab/scripts/lesson-13/L13.Common.ps1) | Shared helpers for the SC-500 Lesson 13 lab: pin the subscription and tenant, call Azure CLI safely, save private evidence, call ARM and Azure Resource Graph, query the Sentinel workspace, run commands inside the collector VMs, and read the lab's outputs. |
| Helper | [`L13.Verdict.ps1`](../../../lab/scripts/lesson-13/L13.Verdict.ps1) | Write-L13Verdict: end a Lesson 13 demo mode with a short "What this run proves" table. |
| In the lab VM | [`guest/Get-L13WefStatus.ps1`](../../../lab/scripts/lesson-13/guest/Get-L13WefStatus.ps1) | Runs inside the lab VM; see the comments at the top of the file. |
| In the lab VM | [`guest/Inspect-L13Wef.ps1`](../../../lab/scripts/lesson-13/guest/Inspect-L13Wef.ps1) | Reads both sides of WEF, including the source plugin channel that reports delivery failures. |
| In the lab VM | [`guest/Refresh-L13Wef.ps1`](../../../lab/scripts/lesson-13/guest/Refresh-L13Wef.ps1) | Refreshes the lab source after WEC startup and reads the actual subscription query. |
| In the lab VM | [`guest/Send-L13Failure.ps1`](../../../lab/scripts/lesson-13/guest/Send-L13Failure.ps1) | Runs inside the lab VM; see the comments at the top of the file. |
| In the lab VM | [`guest/Set-L13Wef.ps1`](../../../lab/scripts/lesson-13/guest/Set-L13Wef.ps1) | Runs inside the lab VM; see the comments at the top of the file. |
| In the lab VM | [`guest/Start-L13Wec.ps1`](../../../lab/scripts/lesson-13/guest/Start-L13Wec.ps1) | Starts the collector after VM boot and returns its actual readiness. |

## Commands

Each command uses the full path from the one-time setup. Read a script's help first with `Get-Help <path> -Full`.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Deploy-L13Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Start-L13Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Test-L13Contracts.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Test-L13Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Invoke-L13ConnectorDemo.ps1 -Mode Sources
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Invoke-L13HostDemo.ps1 -Mode Routes
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Invoke-L13TableDemo.ps1 -Mode Schema
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Invoke-L13WorkspaceDemo.ps1 -Mode Workspace
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Reset-L13Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Stop-L13Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Remove-L13Lab.ps1
```

[Lesson README](../README.md) | [Lab setup](../../../lab/README.md) | [Course README](../../../README.md)
