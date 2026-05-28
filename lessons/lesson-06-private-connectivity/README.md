# Lesson 06: Private Connectivity: Private Link, Private Endpoints, and Microsoft Entra Private Access

**Maps to:** FG2.3
**Estimated runtime:** ~40 minutes (video) + ~30-60 minutes (hands-on)

---

## Learning objectives

By the end of this lesson you can:

- Configure Azure Private Endpoints and disable public network access where required
- Configure Azure Private Link services for cross-tenant and cross-region exposure
- Implement Microsoft Entra Private Access with Entra connectors and Conditional Access
- Manage Private DNS zones for hybrid and multi-region private endpoint topologies

---

## Why this lesson matters on the exam

The SC-500 exam tests these objectives in scenario-based items. Expect questions that give you a business requirement and ask you to pick the right Microsoft service, the right configuration, or the right remediation. The demos in this folder are designed to make those decisions feel obvious.

---

## Demo runbook

The `demos/` subfolder will contain hands-on scripts as the video course is recorded. Planned demos:

- [ ] **06.1** — Configure Azure Private Endpoints and disable public network access where required
- [ ] **06.2** — Configure Azure Private Link services for cross-tenant and cross-region exposure
- [ ] **06.3** — Implement Microsoft Entra Private Access with Entra connectors and Conditional Access
- [ ] **06.4** — Manage Private DNS zones for hybrid and multi-region private endpoint topologies

Each demo lands as an idempotent script (PowerShell + Azure CLI equivalents) with cleanup at the end. Watch this repo's [CHANGELOG](../../CHANGELOG.md) for the publication schedule.

---

## Prerequisites for the demos

- Azure subscription with Owner or Contributor at the subscription scope
- A resource group dedicated to this lesson (the demos will create one named `rg-sc500-l06`)
- Tools: Azure CLI 2.60+, Azure PowerShell Az 11+, the active subscription set to your sandbox

---

## Further reading

See [docs/resources.md](../../docs/resources.md) for the curated Microsoft Learn links that back this lesson.

---

[← Course README](../../README.md) · [Full objective map →](../../docs/exam-objectives.md)
