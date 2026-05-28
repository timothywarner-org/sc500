# Lesson 07: Perimeter Protection: Azure Firewall and Network Watcher Diagnostics

**Maps to:** FG2.3
**Estimated runtime:** ~40 minutes (video) + ~30-60 minutes (hands-on)

---

## Learning objectives

By the end of this lesson you can:

- Implement and configure Azure Firewall (rule collections, threat intelligence, TLS inspection)
- Design hub-and-spoke perimeter architectures combining Azure Firewall, Front Door, and Application Gateway
- Evaluate effective security rules using Azure Network Watcher
- Apply Zero Trust segmentation to isolate workloads and separate prod from non-prod

---

## Why this lesson matters on the exam

The SC-500 exam tests these objectives in scenario-based items. Expect questions that give you a business requirement and ask you to pick the right Microsoft service, the right configuration, or the right remediation. The demos in this folder are designed to make those decisions feel obvious.

---

## Demo runbook

The `demos/` subfolder will contain hands-on scripts as the video course is recorded. Planned demos:

- [ ] **07.1** — Implement and configure Azure Firewall (rule collections, threat intelligence, TLS inspection)
- [ ] **07.2** — Design hub-and-spoke perimeter architectures combining Azure Firewall, Front Door, and Application Gateway
- [ ] **07.3** — Evaluate effective security rules using Azure Network Watcher
- [ ] **07.4** — Apply Zero Trust segmentation to isolate workloads and separate prod from non-prod

Each demo lands as an idempotent script (PowerShell + Azure CLI equivalents) with cleanup at the end. Watch this repo's [CHANGELOG](../../CHANGELOG.md) for the publication schedule.

---

## Prerequisites for the demos

- Azure subscription with Owner or Contributor at the subscription scope
- A resource group dedicated to this lesson (the demos will create one named `rg-sc500-l07`)
- Tools: Azure CLI 2.60+, Azure PowerShell Az 11+, the active subscription set to your sandbox

---

## Further reading

See [docs/resources.md](../../docs/resources.md) for the curated Microsoft Learn links that back this lesson.

---

[← Course README](../../README.md) · [Full objective map →](../../docs/exam-objectives.md)
