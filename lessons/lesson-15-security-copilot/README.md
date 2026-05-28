# Lesson 15: Microsoft Security Copilot for Cloud and AI Defenders

**Maps to:** FG4.3
**Estimated runtime:** ~40 minutes (video) + ~30-60 minutes (hands-on)

---

## Learning objectives

By the end of this lesson you can:

- Configure workspaces for Microsoft Security Copilot
- Manage permissions and roles in Security Copilot
- Enable plugins for Microsoft Defender XDR, Sentinel, Intune, Entra, and selected third-party security products
- Enable Microsoft agents and Security Store agents for triage, KQL generation, incident summarization, and AI-assisted response

---

## Why this lesson matters on the exam

The SC-500 exam tests these objectives in scenario-based items. Expect questions that give you a business requirement and ask you to pick the right Microsoft service, the right configuration, or the right remediation. The demos in this folder are designed to make those decisions feel obvious.

---

## Demo runbook

The `demos/` subfolder will contain hands-on scripts as the video course is recorded. Planned demos:

- [ ] **15.1** — Configure workspaces for Microsoft Security Copilot
- [ ] **15.2** — Manage permissions and roles in Security Copilot
- [ ] **15.3** — Enable plugins for Microsoft Defender XDR, Sentinel, Intune, Entra, and selected third-party security products
- [ ] **15.4** — Enable Microsoft agents and Security Store agents for triage, KQL generation, incident summarization, and AI-assisted response

Each demo lands as an idempotent script (PowerShell + Azure CLI equivalents) with cleanup at the end. Watch this repo's [CHANGELOG](../../CHANGELOG.md) for the publication schedule.

---

## Prerequisites for the demos

- Azure subscription with Owner or Contributor at the subscription scope
- A resource group dedicated to this lesson (the demos will create one named `rg-sc500-l15`)
- Tools: Azure CLI 2.60+, Azure PowerShell Az 11+, the active subscription set to your sandbox

---

## Further reading

See [docs/resources.md](../../docs/resources.md) for the curated Microsoft Learn links that back this lesson.

---

[← Course README](../../README.md) · [Full objective map →](../../docs/exam-objectives.md)
