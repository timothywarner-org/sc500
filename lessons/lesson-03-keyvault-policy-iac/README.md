# Lesson 03: Key Vault, Azure Policy, Compliance, Backup, and Infrastructure as Code

**Maps to:** FG1.2, FG1.3
**Estimated runtime:** ~40 minutes (video) + ~30-60 minutes (hands-on)

---

## Learning objectives

By the end of this lesson you can:

- Deploy and configure Azure Key Vault (network access, RBAC, keys/secrets/certificates)
- Scan for exposed secrets using Microsoft Defender CSPM
- Implement security controls using Azure Policy and evaluate compliance with Microsoft Defender for Cloud security standards
- Configure Azure Backup security features and implement security controls using Infrastructure as Code with Azure Policy guardrails

---

## Why this lesson matters on the exam

The SC-500 exam tests these objectives in scenario-based items. Expect questions that give you a business requirement and ask you to pick the right Microsoft service, the right configuration, or the right remediation. The demos in this folder are designed to make those decisions feel obvious.

---

## Demo runbook

The `demos/` subfolder will contain hands-on scripts as the video course is recorded. Planned demos:

- [ ] **03.1** — Deploy and configure Azure Key Vault (network access, RBAC, keys/secrets/certificates)
- [ ] **03.2** — Scan for exposed secrets using Microsoft Defender CSPM
- [ ] **03.3** — Implement security controls using Azure Policy and evaluate compliance with Microsoft Defender for Cloud security standards
- [ ] **03.4** — Configure Azure Backup security features and implement security controls using Infrastructure as Code with Azure Policy guardrails

Each demo lands as an idempotent script (PowerShell + Azure CLI equivalents) with cleanup at the end. Watch this repo's [CHANGELOG](../../CHANGELOG.md) for the publication schedule.

---

## Prerequisites for the demos

- Azure subscription with Owner or Contributor at the subscription scope
- A resource group dedicated to this lesson (the demos will create one named `rg-sc500-l03`)
- Tools: Azure CLI 2.60+, Azure PowerShell Az 11+, the active subscription set to your sandbox

---

## Further reading

See [docs/resources.md](../../docs/resources.md) for the curated Microsoft Learn links that back this lesson.

---

[← Course README](../../README.md) · [Full objective map →](../../docs/exam-objectives.md)
