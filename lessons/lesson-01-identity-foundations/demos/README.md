# Lesson 01 lab files

The scripts for this lesson are in [`lab/scripts`](../../../lab/scripts/), and its Bicep templates and `sc500.config.json` are in [`lab/infra`](../../../lab/infra/).
Do the [one-time setup](../../../lab/README.md) before you run anything here.

> **Cost warning:** these scripts create real Azure resources. Run this lesson's `Remove-` script when you finish.

## Scripts by stage

Build first, check, run the demos, then reset or clean up. Within a stage, follow the demo order in the lesson.

| Stage | Script | What it does (from the script's own help) |
| --- | --- | --- |
| Build | [`Connect-Sc500Azure.ps1`](../../../lab/scripts/Connect-Sc500Azure.ps1) | Authenticates Azure CLI using the current ARM deployment operation's MFA challenge. |
| Build | [`Copy-Sc500BootstrapPassword.ps1`](../../../lab/scripts/Copy-Sc500BootstrapPassword.ps1) | Copies Debra's Windows-protected bootstrap password to the local clipboard for first sign-in. |
| Build | [`Deploy-Sc500Lesson01.ps1`](../../../lab/scripts/Deploy-Sc500Lesson01.ps1) | Validates, previews, or deploys the retained Lesson 1 lab in your subscription. Modes: `Validate`, `WhatIf`, `Apply`. |
| Build | [`Initialize-Sc500DemoRoles.ps1`](../../../lab/scripts/Initialize-Sc500DemoRoles.ps1) | Prepares bounded Azure and Entra custom roles for Debra's Lesson 1 demonstrations. |
| Build | [`Initialize-Sc500Identity.ps1`](../../../lab/scripts/Initialize-Sc500Identity.ps1) | Creates the dedicated Debra lab user and two secretless application-registration fixtures. |
| Build | [`Initialize-Sc500Pim.ps1`](../../../lab/scripts/Initialize-Sc500Pim.ps1) | Creates or verifies VM-scoped maintenance eligibility and separate Directory Readers eligibility. |
| Build | [`Initialize-Sc500Prerequisites.ps1`](../../../lab/scripts/Initialize-Sc500Prerequisites.ps1) | Checks or registers the Azure providers and encryption-at-host feature required by Lesson 1. |
| Build | [`Set-Sc500AccessReviewFixture.ps1`](../../../lab/scripts/Set-Sc500AccessReviewFixture.ps1) | Adds or removes one temporary subscription Reader assignment for the Lesson 1 review. |
| Build | [`Set-Sc500DemoLock.ps1`](../../../lab/scripts/Set-Sc500DemoLock.ps1) | Adds, reads, or removes the named CanNotDelete lock on the empty SC500 lock-demo group. |
| Build | [`Set-Sc500Enrollment.ps1`](../../../lab/scripts/Set-Sc500Enrollment.ps1) | Bootstraps Debra and Garth with short-lived passes instead of password resets. Modes: `Prepare`, `Issue`, `Status`, `Revoke`. |
| Build | [`Set-Sc500OverprivilegeFixture.ps1`](../../../lab/scripts/Set-Sc500OverprivilegeFixture.ps1) | Adds, inspects, or removes an isolated group-based overprivilege fixture for Lesson 1.4. |
| Build | [`Set-Sc500PimPolicy.ps1`](../../../lab/scripts/Set-Sc500PimPolicy.ps1) | Aligns the maintenance VM's custom-role activation policy with Contoso's one-hour limit. |
| Build | [`Set-Sc500PowerState.ps1`](../../../lab/scripts/Set-Sc500PowerState.ps1) | Starts or deallocates only the two tagged SC-500 Lesson 1 VMs. |
| Build | [`Start-Sc500DirectoryPimSetup.ps1`](../../../lab/scripts/Start-Sc500DirectoryPimSetup.ps1) | Authenticates the Graph PowerShell client with the explicit delegated PIM permission and prepares eligibility. |
| Check | [`Test-Sc500Lesson01.ps1`](../../../lab/scripts/Test-Sc500Lesson01.ps1) | Checks the deployed Lesson 1 infrastructure and captures actual state. |
| Demo | [`Show-Sc500RoleAssignmentScopes.ps1`](../../../lab/scripts/Show-Sc500RoleAssignmentScopes.ps1) | Compares built-in role assignment commands at every Azure RBAC scope. |
| Clean up | [`Remove-Sc500Lesson01.ps1`](../../../lab/scripts/Remove-Sc500Lesson01.ps1) | Deletes only the three owned Lesson 1 resource groups after recording is complete. |
| Helper | [`Sc500.Common.ps1`](../../../lab/scripts/Sc500.Common.ps1) | Shared context, CLI, and evidence helpers for the retained SC-500 demo environment. |

## Commands

Each command uses the full path from the one-time setup. Read a script's help first with `Get-Help <path> -Full`.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\Connect-Sc500Azure.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\Copy-Sc500BootstrapPassword.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\Deploy-Sc500Lesson01.ps1 -Mode Validate
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\Initialize-Sc500DemoRoles.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\Initialize-Sc500Identity.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\Initialize-Sc500Pim.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\Initialize-Sc500Prerequisites.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\Set-Sc500AccessReviewFixture.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\Set-Sc500DemoLock.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\Set-Sc500Enrollment.ps1 -Mode Prepare
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\Set-Sc500OverprivilegeFixture.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\Set-Sc500PimPolicy.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\Set-Sc500PowerState.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\Start-Sc500DirectoryPimSetup.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\Test-Sc500Lesson01.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\Show-Sc500RoleAssignmentScopes.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\Remove-Sc500Lesson01.ps1
```

[Lesson README](../README.md) | [Lab setup](../../../lab/README.md) | [Course README](../../../README.md)
