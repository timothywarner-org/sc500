# Lesson 06: Private Connectivity: Private Link, Private Endpoints, and Microsoft Entra Private Access

**Exam SC-500 domain:** Secure storage, databases, and networking (25-30%)  
**Study guide sections:** Implement security for Azure network services

## Learning objectives

- 6.1 Configure Azure private endpoints to secure access to Azure PaaS resources, and disable public network access where required
- 6.2 Configure Azure Private Link services to secure access to customer-owned network services across tenants and regions
- 6.3 Implement and configure Microsoft Entra Private Access for identity-aware access to private resources using connectors and Conditional Access
- 6.4 Manage private DNS zones and name-resolution patterns for hybrid and multi-region private endpoint topologies

## Hands-on practice

Every demo in this lesson is work you can repeat in your own subscription, mostly in the Azure portal or the Microsoft admin centers. Do each one yourself after you watch it, because clicking through a configuration sticks far better than reading about it.

The step-by-step walkthrough and any lab files for this lesson land in [`demos/`](demos/) after the lesson publishes. Watch the [changelog](../../CHANGELOG.md) for updates.

## Before you start

- An Azure subscription you control, ideally a dedicated sandbox with a budget alert
- A resource group just for this lesson, so cleanup is a single delete
- Microsoft Entra Private Access needs a Microsoft Entra Private Access or Microsoft Entra Suite license, plus a server to run the private network connector.

## Go deeper

- [Exam SC-500 study guide](https://learn.microsoft.com/credentials/certifications/resources/study-guides/sc-500)
- [Curated Microsoft Learn links for this course](../../docs/resources.md)

[Course README](../../README.md) | [Exam objective map](../../docs/exam-objectives.md)
