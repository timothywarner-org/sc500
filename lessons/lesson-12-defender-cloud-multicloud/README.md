# Lesson 12: Manage Posture with Microsoft Defender for Cloud and Multicloud

**Maps to:** FG4.1
**Estimated runtime:** ~40 minutes (video) + ~30-60 minutes (hands-on)

---

## Learning objectives

By the end of this lesson you can:

- Identify security risks using Defender CSPM and evaluate compliance against frameworks (MCSB, NIST, PCI, ISO)
- Enable and configure Defender for Cloud workload protection plans
- Connect hybrid cloud and multicloud (AWS, GCP) environments
- Discover unprotected assets and external vulnerabilities with Microsoft Defender EASM

---

## Why this lesson matters on the exam

The SC-500 exam tests these objectives in scenario-based items. Expect questions that give you a business requirement and ask you to pick the right Microsoft service, the right configuration, or the right remediation. The demos in this folder are designed to make those decisions feel obvious.

---

## Demo runbook

The `demos/` subfolder will contain hands-on scripts as the video course is recorded. Planned demos:

- [ ] **12.1** — Identify security risks using Defender CSPM and evaluate compliance against frameworks (MCSB, NIST, PCI, ISO)
- [ ] **12.2** — Enable and configure Defender for Cloud workload protection plans
- [ ] **12.3** — Connect hybrid cloud and multicloud (AWS, GCP) environments
- [ ] **12.4** — Discover unprotected assets and external vulnerabilities with Microsoft Defender EASM

Each demo lands as an idempotent script (PowerShell + Azure CLI equivalents) with cleanup at the end. Watch this repo's [CHANGELOG](../../CHANGELOG.md) for the publication schedule.

---

## Prerequisites for the demos

- Azure subscription with Owner or Contributor at the subscription scope
- A resource group dedicated to this lesson (the demos will create one named `rg-sc500-l12`)
- Tools: Azure CLI 2.60+, Azure PowerShell Az 11+, the active subscription set to your sandbox

---

## Further reading

See [docs/resources.md](../../docs/resources.md) for the curated Microsoft Learn links that back this lesson.

---

[← Course README](../../README.md) · [Full objective map →](../../docs/exam-objectives.md)
