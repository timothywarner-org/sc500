# Lesson 09 lab files

The scripts for this lesson are in [`lab/scripts/lesson-09`](../../../lab/scripts/lesson-09/) and its Bicep templates and `config.json` are in [`lab/infra/lesson-09`](../../../lab/infra/lesson-09/).
Do the [one-time setup](../../../lab/README.md) before you run anything here.

> **Cost warning:** these scripts create real Azure resources. Run this lesson's `Remove-` script when you finish.

## Scripts by stage

Build first, check, run the demos, then reset or clean up. Within a stage, follow the demo order in the lesson.

| Stage | Script | What it does (from the script's own help) |
| --- | --- | --- |
| Build | [`Deploy-L09Edge.ps1`](../../../lab/scripts/lesson-09/Deploy-L09Edge.ps1) | Previews, or deploys, the bounded Lesson 9 edge: the App Service origin, Application Gateway WAF_v2, Front Door Standard with its WAF policy, and the Container Instances worker. |
| Build | [`Deploy-L09Lab.ps1`](../../../lab/scripts/lesson-09/Deploy-L09Lab.ps1) | Previews, or deploys, the retained SC-500 Lesson 9 application platform lab. |
| Build | [`Set-L09DefenderWindow.ps1`](../../../lab/scripts/lesson-09/Set-L09DefenderWindow.ps1) | Opens or closes the Lesson 9 Defender window: Defender for Containers and Defender for App Service on the subscription. |
| Build | [`Set-L09OperatorIp.ps1`](../../../lab/scripts/lesson-09/Set-L09OperatorIp.ps1) | Checks, or refreshes, every Lesson 9 allow list that names the operator's public IP. |
| Build | [`Start-L09Lab.ps1`](../../../lab/scripts/lesson-09/Start-L09Lab.ps1) | Starts, or stops, the Lesson 9 AKS cluster. Everything else in the retained lab is consumption-billed and needs no start. |
| Check | [`Test-L09Lab.ps1`](../../../lab/scripts/lesson-09/Test-L09Lab.ps1) | Read-only readiness check for the Lesson 9 lab at CTSO-L09-BASELINE. |
| Check | [`Test-L09Templates.ps1`](../../../lab/scripts/lesson-09/Test-L09Templates.ps1) | Verifies the Lesson 9 templates and scripts without deploying anything. |
| Demo | [`Invoke-L09ApiDemo.ps1`](../../../lab/scripts/lesson-09/Invoke-L09ApiDemo.ps1) | Demo 9.4 for SC-500 Lesson 9: back-end API protection with Azure API Management policies. Modes: `Policy`, `NoKey`, `NoToken`, `Call`, `Burst`, `Backend`, `All`. |
| Demo | [`Invoke-L09ContainerDemo.ps1`](../../../lab/scripts/lesson-09/Invoke-L09ContainerDemo.ps1) | Demo 9.1 for SC-500 Lesson 9: container security controls, and what Defender for Containers reports about misconfigurations and vulnerable images. Modes: `Cluster`, `Registry`, `Workloads`, `Privileged`, `Sensor`, `Findings`, `App`, `Block`, `Instance`, `All`. |
| Demo | [`Invoke-L09ServerlessDemo.ps1`](../../../lab/scripts/lesson-09/Invoke-L09ServerlessDemo.ps1) | Demo 9.2 for SC-500 Lesson 9: Azure Functions authentication and access, and Logic Apps trigger security. Modes: `Function`, `Direct`, `Logic`, `LogicCall`, `RunHistory`, `All`. |
| Demo | [`Invoke-L09WebDemo.ps1`](../../../lab/scripts/lesson-09/Invoke-L09WebDemo.ps1) | Demo 9.3 for SC-500 Lesson 9: App Service security, and Web Application Firewall on Application Gateway and Front Door. Needs the edge part (Deploy-L09Edge.ps1 -Deploy). Modes: `App`, `Direct`, `Gateway`, `FrontDoor`, `Logs`, `All`. |
| Reset | [`Reset-L09Lab.ps1`](../../../lab/scripts/lesson-09/Reset-L09Lab.ps1) | Resets the Lesson 9 demos between runs, or returns the lab to CTSO-L09-BASELINE after the recording session. |
| Clean up | [`Remove-L09Edge.ps1`](../../../lab/scripts/lesson-09/Remove-L09Edge.ps1) | Deletes the bounded Lesson 9 edge and confirms nothing bounded is left. |
| Clean up | [`Remove-L09Lab.ps1`](../../../lab/scripts/lesson-09/Remove-L09Lab.ps1) | Deletes the whole Lesson 9 lab: the resource group and the lab API app registration. your call, not a routine step. |
| Helper | [`L09.Common.ps1`](../../../lab/scripts/lesson-09/L09.Common.ps1) | Shared helpers for the SC-500 Lesson 9 lab: pin the subscription, call Azure CLI safely, save private evidence, read deployment outputs, call ARM, Microsoft Graph, and Resource Graph, get a token for the lab API from the operator's existing Azure CLI sign-in, send probe requests, and run kubectl inside the AKS cluster. |

## Commands

Each command uses the full path from the one-time setup. Read a script's help first with `Get-Help <path> -Full`.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Deploy-L09Edge.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Deploy-L09Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Set-L09DefenderWindow.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Set-L09OperatorIp.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Start-L09Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Test-L09Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Test-L09Templates.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Invoke-L09ApiDemo.ps1 -Mode Policy
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Invoke-L09ContainerDemo.ps1 -Mode Cluster
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Invoke-L09ServerlessDemo.ps1 -Mode Function
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Invoke-L09WebDemo.ps1 -Mode App
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Reset-L09Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Remove-L09Edge.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Remove-L09Lab.ps1
```

[Lesson README](../README.md) | [Lab setup](../../../lab/README.md) | [Course README](../../../README.md)
