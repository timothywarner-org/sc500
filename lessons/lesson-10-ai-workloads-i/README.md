# Lesson 10: Secure AI Workloads I: Data Overexposure, Copilot, and Microsoft Entra Agent ID

**Maps to:** FG3.1
**Estimated runtime:** ~40 minutes (video) + ~30-60 minutes (hands-on)

---

## Learning objectives

By the end of this lesson you can:

- Identify SharePoint data overexposure and Microsoft Copilot risks using Microsoft Purview DSPM
- Enable real-time protection for Microsoft Copilot Studio agents and manage AI agents in the Microsoft 365 admin center
- Implement Conditional Access for Microsoft Entra Agent ID and manage agent access lifecycle
- Analyze blast radius for Entra Agent ID risks using Microsoft Defender XDR incident and entity correlation

---

## Why this lesson matters on the exam

The SC-500 exam tests these objectives in scenario-based items. Expect questions that give you a business requirement and ask you to pick the right Microsoft service, the right configuration, or the right remediation. The demos in this folder are designed to make those decisions feel obvious.

---

## Demo runbook

The `demos/` subfolder will contain hands-on scripts as the video course is recorded. Planned demos:

- [ ] **10.1** — Identify SharePoint data overexposure and Microsoft Copilot risks using Microsoft Purview DSPM
- [ ] **10.2** — Enable real-time protection for Microsoft Copilot Studio agents and manage AI agents in the Microsoft 365 admin center
- [ ] **10.3** — Implement Conditional Access for Microsoft Entra Agent ID and manage agent access lifecycle
- [ ] **10.4** — Analyze blast radius for Entra Agent ID risks using Microsoft Defender XDR incident and entity correlation

Each demo lands as an idempotent script (PowerShell + Azure CLI equivalents) with cleanup at the end. Watch this repo's [CHANGELOG](../../CHANGELOG.md) for the publication schedule.

---

## Prerequisites for the demos

- Azure subscription with Owner or Contributor at the subscription scope
- A resource group dedicated to this lesson (the demos will create one named `rg-sc500-l10`)
- Tools: Azure CLI 2.60+, Azure PowerShell Az 11+, the active subscription set to your sandbox

---

## Further reading

See [docs/resources.md](../../docs/resources.md) for the curated Microsoft Learn links that back this lesson.

---

[← Course README](../../README.md) · [Full objective map →](../../docs/exam-objectives.md)
