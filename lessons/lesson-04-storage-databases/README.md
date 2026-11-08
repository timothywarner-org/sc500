# Lesson 04: Secure Storage and Databases

**Exam SC-500 domain:** Secure storage, databases, and networking (25-30%)  
**Study guide sections:** Implement security for storage accounts; Implement security for databases

## Learning objectives

- 4.1 Implement and configure Azure Storage account security, configure Storage firewall rules, and manage access to storage, including access policies
- 4.2 Implement Microsoft Defender for Storage threat protection configurations
- 4.3 Implement platform-level security configurations in Azure SQL, and configure database auditing for both Azure SQL Database and Azure SQL Managed Instance
- 4.4 Configure Defender for Databases protection across Azure database services, including SQL Database, SQL Managed Instance, Azure Database for PostgreSQL and MySQL, and Azure Cosmos DB

## Hands-on practice

Every demo in this lesson is work you can repeat in your own subscription, mostly in the Azure portal or the Microsoft admin centers. Do each one yourself after you watch it, because clicking through a configuration sticks far better than reading about it.

**Step by step:** the [lab guide](lab-guide.md) lists every portal step and command from this lesson's demos, in the order the video runs them.

The scripts and Bicep templates from this lesson's demos are published: [`demos/`](demos/) lists them by stage and links to their folders under `lab/`. Do the [one-time lab setup](../../lab/README.md) first.

## Before you start

- An Azure subscription you control, ideally a dedicated sandbox with a budget alert
- A resource group just for this lesson, so cleanup is a single delete
- Defender for Storage and Defender for Databases are paid plans. An Azure SQL Managed Instance can take a long time to deploy and bills while it exists, so plan around it.

## Go deeper

- [Exam SC-500 study guide](https://learn.microsoft.com/credentials/certifications/resources/study-guides/sc-500)
- [Curated Microsoft Learn links for this course](../../docs/resources.md)

[Course README](../../README.md) | [Exam objective map](../../docs/exam-objectives.md)
