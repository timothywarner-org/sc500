# Lesson 11: Secure AI Workloads II: Microsoft Foundry, AI Gateway, and Defender for AI

**Maps to:** FG3.1
**Estimated runtime:** ~40 minutes (video) + ~30-60 minutes (hands-on)

---

## Learning objectives

By the end of this lesson you can:

- Configure and deploy AI Gateway in Azure API Management for Microsoft Foundry
- Enable Microsoft Defender for AI Service in Defender for Cloud workload protection plans
- Configure guardrails for agent security in Microsoft Foundry
- Monitor AI security with the Data and AI security dashboard and correlate AI alerts with Microsoft Sentinel

---

## Why this lesson matters on the exam

The SC-500 exam tests these objectives in scenario-based items. Expect questions that give you a business requirement and ask you to pick the right Microsoft service, the right configuration, or the right remediation. The demos in this folder are designed to make those decisions feel obvious.

---

## Demo runbook

The `demos/` subfolder will contain hands-on scripts as the video course is recorded. Planned demos:

- [ ] **11.1** — Configure and deploy AI Gateway in Azure API Management for Microsoft Foundry
- [ ] **11.2** — Enable Microsoft Defender for AI Service in Defender for Cloud workload protection plans
- [ ] **11.3** — Configure guardrails for agent security in Microsoft Foundry
- [ ] **11.4** — Monitor AI security with the Data and AI security dashboard and correlate AI alerts with Microsoft Sentinel

Each demo lands as an idempotent script (PowerShell + Azure CLI equivalents) with cleanup at the end. Watch this repo's [CHANGELOG](../../CHANGELOG.md) for the publication schedule.

---

## Prerequisites for the demos

- Azure subscription with Owner or Contributor at the subscription scope
- A resource group dedicated to this lesson (the demos will create one named `rg-sc500-l11`)
- Tools: Azure CLI 2.60+, Azure PowerShell Az 11+, the active subscription set to your sandbox

---

## Further reading

See [docs/resources.md](../../docs/resources.md) for the curated Microsoft Learn links that back this lesson.

---

[← Course README](../../README.md) · [Full objective map →](../../docs/exam-objectives.md)
