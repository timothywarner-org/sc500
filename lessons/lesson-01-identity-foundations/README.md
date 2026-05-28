# Lesson 01: Identity Foundations: PIM, RBAC, Custom Roles, and Governance Scope

**Maps to:** FG1.1, FG1.3
**Estimated runtime:** ~40 minutes (video) + ~30-60 minutes (hands-on)

---

## Learning objectives

By the end of this lesson you can:

- Implement and configure Microsoft Entra Privileged Identity Management for Azure resources and Entra roles
- Manage Azure built-in role assignments at MG/subscription/RG/resource scope, and create custom Azure roles
- Manage Microsoft Entra directory roles
- Evaluate and remediate overprivileged access using Azure RBAC tooling and PIM access reviews, and apply resource locks

---

## Why this lesson matters on the exam

The SC-500 exam tests these objectives in scenario-based items. Expect questions that give you a business requirement and ask you to pick the right Microsoft service, the right configuration, or the right remediation. The demos in this folder are designed to make those decisions feel obvious.

---

## Demo runbook

The `demos/` subfolder will contain hands-on scripts as the video course is recorded. Planned demos:

- [ ] **01.1** — Implement and configure Microsoft Entra Privileged Identity Management for Azure resources and Entra roles
- [ ] **01.2** — Manage Azure built-in role assignments at MG/subscription/RG/resource scope, and create custom Azure roles
- [ ] **01.3** — Manage Microsoft Entra directory roles
- [ ] **01.4** — Evaluate and remediate overprivileged access using Azure RBAC tooling and PIM access reviews, and apply resource locks

Each demo lands as an idempotent script (PowerShell + Azure CLI equivalents) with cleanup at the end. Watch this repo's [CHANGELOG](../../CHANGELOG.md) for the publication schedule.

---

## Prerequisites for the demos

- Azure subscription with Owner or Contributor at the subscription scope
- A resource group dedicated to this lesson (the demos will create one named `rg-sc500-l01`)
- Tools: Azure CLI 2.60+, Azure PowerShell Az 11+, the active subscription set to your sandbox

---

## Further reading

See [docs/resources.md](../../docs/resources.md) for the curated Microsoft Learn links that back this lesson.

---

[← Course README](../../README.md) · [Full objective map →](../../docs/exam-objectives.md)
