# Lesson 03 lab files

The scripts for this lesson are in [`lab/scripts/lesson-03`](../../../lab/scripts/lesson-03/) and its Bicep templates and `config.json` are in [`lab/infra/lesson-03`](../../../lab/infra/lesson-03/).
Do the [one-time setup](../../../lab/README.md) before you run anything here.

> **Cost warning:** these scripts create real Azure resources. Run this lesson's `Remove-` script when you finish.

## Scripts by stage

Build first, check, run the demos, then reset or clean up. Within a stage, follow the demo order in the lesson.

| Stage | Script | What it does (from the script's own help) |
| --- | --- | --- |
| Build | [`Deploy-L03Lab.ps1`](../../../lab/scripts/lesson-03/Deploy-L03Lab.ps1) | Previews or deploys the isolated Lesson 3 lab in the course lab subscription named by infra/lesson-03/config.json. |
| Build | [`Enable-L03Backup.ps1`](../../../lab/scripts/lesson-03/Enable-L03Backup.ps1) | Protects the existing Lesson 3 VM with a bounded daily backup policy. |
| Build | [`New-L03RestoreStaging.ps1`](../../../lab/scripts/lesson-03/New-L03RestoreStaging.ps1) | Creates the small LRS staging account required by the Lesson 3 managed-disk restore. |
| Build | [`Set-L03ResourceGuard.ps1`](../../../lab/scripts/lesson-03/Set-L03ResourceGuard.ps1) | Creates the lesson-owned Resource Guard and enables MUA on the retained recovery vault. |
| Build | [`Set-L03ScanWindow.ps1`](../../../lab/scripts/lesson-03/Set-L03ScanWindow.ps1) | Opens or closes the Lesson 3 Defender scan window around a demo: plans, runner power, auto-shutdown. |
| Build | [`Start-L03Backup.ps1`](../../../lab/scripts/lesson-03/Start-L03Backup.ps1) | Starts one on-demand backup of the already-protected Lesson 3 runner and preserves its job identifier. |
| Build | [`Start-L03Lab.ps1`](../../../lab/scripts/lesson-03/Start-L03Lab.ps1) | Restores Lesson 3 outbound management connectivity, then starts its private runner. |
| Build | [`Start-L03Restore.ps1`](../../../lab/scripts/lesson-03/Start-L03Restore.ps1) | Restores the newest Lesson 3 VM recovery point to a separate managed disk. |
| Check | [`Test-L03CompletionControls.ps1`](../../../lab/scripts/lesson-03/Test-L03CompletionControls.ps1) | Reads back the retained Lesson 3 backup, recovery, access and cost controls. |
| Check | [`Test-L03Lab.ps1`](../../../lab/scripts/lesson-03/Test-L03Lab.ps1) | Reads deployed L3 controls and reports configuration separately from live request evidence. |
| Check | [`Test-L03Policy.ps1`](../../../lab/scripts/lesson-03/Test-L03Policy.ps1) | Proves a denied and allowed request in the isolated Lesson 3 policy resource group. |
| Check | [`Test-L03RestoredRecord.ps1`](../../../lab/scripts/lesson-03/Test-L03RestoredRecord.ps1) | Reads the real restored Contoso file from a temporary read-only disk attachment. |
| Demo | [`Get-L03CompletionEvidence.ps1`](../../../lab/scripts/lesson-03/Get-L03CompletionEvidence.ps1) | Reads Lesson 3 assessment details and the security-standard mapping without modifying findings. |
| Demo | [`Get-L03DetectionEvidence.ps1`](../../../lab/scripts/lesson-03/Get-L03DetectionEvidence.ps1) | Reads real Lesson 3 Defender findings and alerts without creating sample alerts. |
| Demo | [`Invoke-L03DetectionCanary.ps1`](../../../lab/scripts/lesson-03/Invoke-L03DetectionCanary.ps1) | Validates Defender for Key Vault with a separate synthetic-only canary vault. |
| Demo | [`Invoke-L03Guest.ps1`](../../../lab/scripts/lesson-03/Invoke-L03Guest.ps1) | Runs a reviewed Lesson 3 guest script and returns its structured, nonsecret result. |
| Demo | [`Invoke-L03ResourceGuardDemo.ps1`](../../../lab/scripts/lesson-03/Invoke-L03ResourceGuardDemo.ps1) | Proves Resource Guard denial, separately authorized success, and restored MUA protection. |
| Demo | [`Invoke-L03VaultDemo.ps1`](../../../lab/scripts/lesson-03/Invoke-L03VaultDemo.ps1) | Runs the synthetic object lifecycle or restricted workload request in the private L3 VM. Modes: `Objects`, `ReadBoundary`. |
| Demo | [`Show-L03Posture.ps1`](../../../lab/scripts/lesson-03/Show-L03Posture.ps1) | Reads Defender coverage, standards and Lesson 3 findings without changing paid plans. |
| Demo | [`Show-L03RecoveryEvidence.ps1`](../../../lab/scripts/lesson-03/Show-L03RecoveryEvidence.ps1) | Shows current vault state beside dated, real Resource Guard and restore results. |
| Reset | [`Stop-L03Lab.ps1`](../../../lab/scripts/lesson-03/Stop-L03Lab.ps1) | Deallocates the Lesson 3 runner and removes only its disposable egress charges. |
| Helper | [`L03.Cloud.Common.ps1`](../../../lab/scripts/lesson-03/L03.Cloud.Common.ps1) | Pins Lesson 3 operations to its course subscription and owned resources. |

Python helpers, called by the PowerShell scripts: [`prepare_recovery_fixture.py`](../../../lab/scripts/lesson-03/prepare_recovery_fixture.py), [`resource_guard_probe.py`](../../../lab/scripts/lesson-03/resource_guard_probe.py), [`validate_vault_detection.py`](../../../lab/scripts/lesson-03/validate_vault_detection.py), [`vault_probe.py`](../../../lab/scripts/lesson-03/vault_probe.py), [`verify_restored_record.py`](../../../lab/scripts/lesson-03/verify_restored_record.py).

## Commands

Each command uses the full path from the one-time setup. Read a script's help first with `Get-Help <path> -Full`.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-03\Deploy-L03Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-03\Enable-L03Backup.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-03\New-L03RestoreStaging.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-03\Set-L03ResourceGuard.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-03\Set-L03ScanWindow.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-03\Start-L03Backup.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-03\Start-L03Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-03\Start-L03Restore.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-03\Test-L03CompletionControls.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-03\Test-L03Lab.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-03\Test-L03Policy.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-03\Test-L03RestoredRecord.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-03\Get-L03CompletionEvidence.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-03\Get-L03DetectionEvidence.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-03\Invoke-L03DetectionCanary.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-03\Invoke-L03Guest.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-03\Invoke-L03ResourceGuardDemo.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-03\Invoke-L03VaultDemo.ps1 -Mode Objects
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-03\Show-L03Posture.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-03\Show-L03RecoveryEvidence.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-03\Stop-L03Lab.ps1
```

[Lesson README](../README.md) | [Lab setup](../../../lab/README.md) | [Course README](../../../README.md)
