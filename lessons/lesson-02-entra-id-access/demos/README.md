# Lesson 02 lab files

The scripts for this lesson are in [`lab/scripts/lesson-02`](../../../lab/scripts/lesson-02/) and its Bicep templates and `config.json` are in [`lab/infra/lesson-02`](../../../lab/infra/lesson-02/).
Do the [one-time setup](../../../lab/README.md) before you run anything here.

> **Cost warning:** these scripts create real Azure resources. Run this lesson's `Remove-` script when you finish.

## Scripts by stage

Build first, check, run the demos, then reset or clean up. Within a stage, follow the demo order in the lesson.

| Stage | Script | What it does (from the script's own help) |
| --- | --- | --- |
| Build | [`Copy-L02BootstrapPassword.ps1`](../../../lab/scripts/lesson-02/Copy-L02BootstrapPassword.ps1) | Copies Garth's protected bootstrap password locally for your first-sign-in step. |
| Build | [`Deploy-L02Workload.ps1`](../../../lab/scripts/lesson-02/Deploy-L02Workload.ps1) | Validates, previews, or deploys the isolated Lesson 2 managed-identity laboratory. Modes: `Validate`, `WhatIf`, `Apply`. |
| Build | [`Initialize-L02Identity.ps1`](../../../lab/scripts/lesson-02/Initialize-L02Identity.ps1) | Creates isolated Contoso application and consent fixtures for SC-500 Lesson 2. |
| Build | [`Set-L02ConditionalAccess.ps1`](../../../lab/scripts/lesson-02/Set-L02ConditionalAccess.ps1) | Creates report-only Conditional Access policies scoped to Lesson 2 fixtures. |
| Build | [`Set-L02FederationEnvironment.ps1`](../../../lab/scripts/lesson-02/Set-L02FederationEnvironment.ps1) | Configures the exact GitHub environment trusted by the Lesson 2 managed identity. |
| Build | [`Set-L02PasskeyPilot.ps1`](../../../lab/scripts/lesson-02/Set-L02PasskeyPilot.ps1) | Enables device-bound passkeys for the isolated Garth pilot group. |
| Check | [`Test-L02Workload.ps1`](../../../lab/scripts/lesson-02/Test-L02Workload.ps1) | Checks deployed Lesson 2 configuration independently from application authorization. |
| Demo | [`Invoke-L02GarthSignIn.ps1`](../../../lab/scripts/lesson-02/Invoke-L02GarthSignIn.ps1) | Opens an interactive Garth sign-in targeting the Lesson 2 API. |
| Demo | [`Invoke-L02IdentityProbe.ps1`](../../../lab/scripts/lesson-02/Invoke-L02IdentityProbe.ps1) | Captures the live managed-identity read/denied-write results and stops compute. |
| Demo | [`Show-L02Consent.ps1`](../../../lab/scripts/lesson-02/Show-L02Consent.ps1) | Reads, revokes, or restores only Garth's delegated grant to the Lesson 2 API. |
| Reset | [`Stop-L02Workload.ps1`](../../../lab/scripts/lesson-02/Stop-L02Workload.ps1) | Stops Lesson 2 container compute while retaining the group and both identities. |
| Helper | [`L02.Cloud.Common.ps1`](../../../lab/scripts/lesson-02/L02.Cloud.Common.ps1) | Provides pinned Azure context and private evidence helpers for Lesson 2 only. |

Python helpers, called by the PowerShell scripts: [`garth_signin.py`](../../../lab/scripts/lesson-02/garth_signin.py), [`identity-probe.py`](../../../lab/scripts/lesson-02/identity-probe.py), [`test_identity_probe.py`](../../../lab/scripts/lesson-02/test_identity_probe.py).

The workload identity federation workflow template is [`lab/infra/lesson-02/sc500-lesson02-oidc.yml`](../../../lab/infra/lesson-02/sc500-lesson02-oidc.yml). [Lesson 2: prove workload identity federation](../../../demos/lesson-02-federation.md) explains what your own fork needs.

## Commands

Each command uses the full path from the one-time setup. Read a script's help first with `Get-Help <path> -Full`.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-02\Copy-L02BootstrapPassword.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-02\Deploy-L02Workload.ps1 -Mode Validate
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-02\Initialize-L02Identity.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-02\Set-L02ConditionalAccess.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-02\Set-L02FederationEnvironment.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-02\Set-L02PasskeyPilot.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-02\Test-L02Workload.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-02\Invoke-L02GarthSignIn.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-02\Invoke-L02IdentityProbe.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-02\Show-L02Consent.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-02\Stop-L02Workload.ps1
```

[Lesson README](../README.md) | [Lab setup](../../../lab/README.md) | [Course README](../../../README.md)
