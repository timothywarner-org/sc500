# Lesson 14: Microsoft Sentinel II: Analytics, Automation, KQL Hunting, and Purview Audit

**Maps to:** FG4.2
**Estimated runtime:** ~40 minutes (video) + ~30-60 minutes (hands-on)

---

## Learning objectives

By the end of this lesson you can:

- Create and tune analytics rules
- Implement automation rules and Azure Logic Apps playbooks
- Write KQL queries for threat hunting and deploy custom workbooks and notebooks
- Query Microsoft Purview Audit in Defender XDR and manage incidents end-to-end

---

## Why this lesson matters on the exam

The SC-500 exam tests these objectives in scenario-based items. Expect questions that give you a business requirement and ask you to pick the right Microsoft service, the right configuration, or the right remediation. The demos in this folder are designed to make those decisions feel obvious.

---

## Demo runbook

The `demos/` subfolder will contain hands-on scripts as the video course is recorded. Planned demos:

- [ ] **14.1** — Create and tune analytics rules
- [ ] **14.2** — Implement automation rules and Azure Logic Apps playbooks
- [ ] **14.3** — Write KQL queries for threat hunting and deploy custom workbooks and notebooks
- [ ] **14.4** — Query Microsoft Purview Audit in Defender XDR and manage incidents end-to-end

Each demo lands as an idempotent script (PowerShell + Azure CLI equivalents) with cleanup at the end. Watch this repo's [CHANGELOG](../../CHANGELOG.md) for the publication schedule.

---

## Prerequisites for the demos

- Azure subscription with Owner or Contributor at the subscription scope
- A resource group dedicated to this lesson (the demos will create one named `rg-sc500-l14`)
- Tools: Azure CLI 2.60+, Azure PowerShell Az 11+, the active subscription set to your sandbox

---

## Further reading

See [docs/resources.md](../../docs/resources.md) for the curated Microsoft Learn links that back this lesson.

---

[← Course README](../../README.md) · [Full objective map →](../../docs/exam-objectives.md)
