# Lesson 05 lab files

The scripts for this lesson are in [`lab/scripts/lesson-05`](../../../lab/scripts/lesson-05/) and its Bicep templates and `config.json` are in [`lab/infra/lesson-05`](../../../lab/infra/lesson-05/).
Do the [one-time setup](../../../lab/README.md) before you run anything here.

> **Cost warning:** these scripts create real Azure resources. Run this lesson's `Remove-` script when you finish.

## Scripts by stage

Build first, check, run the demos, then reset or clean up. Within a stage, follow the demo order in the lesson.

| Stage | Script | What it does (from the script's own help) |
| --- | --- | --- |
| Build | [`Deploy-L05Bounded.ps1`](../../../lab/scripts/lesson-05/Deploy-L05Bounded.ps1) | Previews, or deploys, one of the bounded Lesson 5 labs: the secured Virtual WAN hub (demo 5.3) or the site-to-site and point-to-site VPN (demo 5.4). |
| Build | [`Deploy-L05Lab.ps1`](../../../lab/scripts/lesson-05/Deploy-L05Lab.ps1) | Previews, or deploys, the retained SC-500 Lesson 5 network lab in your subscription. |
| Build | [`Install-L05NetworkWatcherAgent.ps1`](../../../lab/scripts/lesson-05/Install-L05NetworkWatcherAgent.ps1) | Starts the retained Lesson 5 VMs and installs the Network Watcher agent on the four Connection troubleshoot sources. |
| Build | [`Start-L05Lab.ps1`](../../../lab/scripts/lesson-05/Start-L05Lab.ps1) | Starts, or with -Stop deallocates, the four retained Lesson 5 test VMs. |
| Check | [`Test-L05Lab.ps1`](../../../lab/scripts/lesson-05/Test-L05Lab.ps1) | Read-only readiness check: is the retained Lesson 5 lab at CTSO-L05-BASELINE? |
| Demo | [`Invoke-L05AvnmDemo.ps1`](../../../lab/scripts/lesson-05/Invoke-L05AvnmDemo.ps1) | Demo 5.2: enforce a platform guardrail with Azure Virtual Network Manager security admin rules that workload NSGs can't override, in either direction. Modes: `Settings`, `AddTeamRule`, `Probe`, `Deploy`, `EffectiveRules`, `FlowLogs`, `Undeploy`. |
| Demo | [`Invoke-L05SegmentDemo.ps1`](../../../lab/scripts/lesson-05/Invoke-L05SegmentDemo.ps1) | Demo 5.1: segment the ServiceHub tiers with an NSG that names application security groups, then prove and audit the result. Modes: `Settings`, `Probe`, `ApplyLeastPrivilege`, `FlowVerify`, `EffectiveRules`, `FlowLogs`, `TrafficAnalytics`. |
| Demo | [`Invoke-L05VpnDemo.ps1`](../../../lab/scripts/lesson-05/Invoke-L05VpnDemo.ps1) | Demo 5.4: secure site-to-site and point-to-site VPN connections. Modes: `Settings`, `Status`, `IkeLogs`, `FixBranch`, `Probe`, `Break`. |
| Demo | [`Invoke-L05WanDemo.ps1`](../../../lab/scripts/lesson-05/Invoke-L05WanDemo.ps1) | Demo 5.3: show that the secured Virtual WAN hub inspects spoke-to-spoke traffic. Modes: `Settings`, `Routes`, `Probe`, `FirewallLogs`. |
| Reset | [`Reset-L05Lab.ps1`](../../../lab/scripts/lesson-05/Reset-L05Lab.ps1) | Returns the retained Lesson 5 lab to CTSO-L05-BASELINE after the demo. |
| Clean up | [`Remove-L05Bounded.ps1`](../../../lab/scripts/lesson-05/Remove-L05Bounded.ps1) | Removes one bounded Lesson 5 lab after you finish, and proves it's gone. |
| Clean up | [`Remove-L05Lab.ps1`](../../../lab/scripts/lesson-05/Remove-L05Lab.ps1) | Decommissions the whole Lesson 5 lab after the demo: records what exists, then deletes the VPN lab, the network lab and the Lesson 5 flow logs, and proves they're gone. |
| Helper | [`L05.Common.ps1`](../../../lab/scripts/lesson-05/L05.Common.ps1) | Shared helpers for the SC-500 Lesson 5 lab: pin the subscription, call Azure CLI safely, save private evidence, read deployment outputs, and run connection probes inside VMs. |

## Commands

Each command uses the full path from the one-time setup. Read a script's help first with `Get-Help <path> -Full`.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-05\Deploy-L05Bounded.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-05\Deploy-L05Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-05\Install-L05NetworkWatcherAgent.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-05\Start-L05Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-05\Test-L05Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-05\Invoke-L05AvnmDemo.ps1 -Mode Settings
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-05\Invoke-L05SegmentDemo.ps1 -Mode Settings
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-05\Invoke-L05VpnDemo.ps1 -Mode Settings
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-05\Invoke-L05WanDemo.ps1 -Mode Settings
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-05\Reset-L05Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-05\Remove-L05Bounded.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-05\Remove-L05Lab.ps1
```

[Lesson README](../README.md) | [Lab setup](../../../lab/README.md) | [Course README](../../../README.md)
