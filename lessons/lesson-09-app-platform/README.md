# Lesson 09: Secure Application Platform Services: Containers, Serverless, App Service, WAF, APIM

**Maps to:** FG3.3
**Estimated runtime:** ~40 minutes (video) + ~30-60 minutes (hands-on)

---

## Learning objectives

By the end of this lesson you can:

- Detect container misconfigurations with Defender for Containers, and secure AKS, ACR, ACI, and Container Apps
- Implement security controls for Azure Functions and Logic Apps
- Implement security controls for Azure App Service and configure Azure WAF on Front Door and Application Gateway
- Implement back-end API security using Azure API Management

---

## Why this lesson matters on the exam

The SC-500 exam tests these objectives in scenario-based items. Expect questions that give you a business requirement and ask you to pick the right Microsoft service, the right configuration, or the right remediation. The demos in this folder are designed to make those decisions feel obvious.

---

## Demo runbook

The `demos/` subfolder will contain hands-on scripts as the video course is recorded. Planned demos:

- [ ] **09.1** — Detect container misconfigurations with Defender for Containers, and secure AKS, ACR, ACI, and Container Apps
- [ ] **09.2** — Implement security controls for Azure Functions and Logic Apps
- [ ] **09.3** — Implement security controls for Azure App Service and configure Azure WAF on Front Door and Application Gateway
- [ ] **09.4** — Implement back-end API security using Azure API Management

Each demo lands as an idempotent script (PowerShell + Azure CLI equivalents) with cleanup at the end. Watch this repo's [CHANGELOG](../../CHANGELOG.md) for the publication schedule.

---

## Prerequisites for the demos

- Azure subscription with Owner or Contributor at the subscription scope
- A resource group dedicated to this lesson (the demos will create one named `rg-sc500-l09`)
- Tools: Azure CLI 2.60+, Azure PowerShell Az 11+, the active subscription set to your sandbox

---

## Further reading

See [docs/resources.md](../../docs/resources.md) for the curated Microsoft Learn links that back this lesson.

---

[← Course README](../../README.md) · [Full objective map →](../../docs/exam-objectives.md)
