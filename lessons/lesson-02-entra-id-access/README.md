# Lesson 02: Entra ID Access: MFA, Conditional Access, Apps, and Managed Identities

**Maps to:** FG1.1
**Estimated runtime:** ~40 minutes (video) + ~30-60 minutes (hands-on)

---

## Learning objectives

By the end of this lesson you can:

- Implement and configure authentication methods (MFA, passwordless, phishing-resistant)
- Design and implement Conditional Access policies
- Implement and configure identity for applications (OAuth grants, consent governance)
- Implement system-assigned and user-assigned managed identities, and apply Workload Identity Federation

---

## Why this lesson matters on the exam

The SC-500 exam tests these objectives in scenario-based items. Expect questions that give you a business requirement and ask you to pick the right Microsoft service, the right configuration, or the right remediation. The demos in this folder are designed to make those decisions feel obvious.

---

## Demo runbook

The `demos/` subfolder will contain hands-on scripts as the video course is recorded. Planned demos:

- [ ] **02.1** — Implement and configure authentication methods (MFA, passwordless, phishing-resistant)
- [ ] **02.2** — Design and implement Conditional Access policies
- [ ] **02.3** — Implement and configure identity for applications (OAuth grants, consent governance)
- [ ] **02.4** — Implement system-assigned and user-assigned managed identities, and apply Workload Identity Federation

Each demo lands as an idempotent script (PowerShell + Azure CLI equivalents) with cleanup at the end. Watch this repo's [CHANGELOG](../../CHANGELOG.md) for the publication schedule.

---

## Prerequisites for the demos

- Azure subscription with Owner or Contributor at the subscription scope
- A resource group dedicated to this lesson (the demos will create one named `rg-sc500-l02`)
- Tools: Azure CLI 2.60+, Azure PowerShell Az 11+, the active subscription set to your sandbox

---

## Further reading

See [docs/resources.md](../../docs/resources.md) for the curated Microsoft Learn links that back this lesson.

---

[← Course README](../../README.md) · [Full objective map →](../../docs/exam-objectives.md)
