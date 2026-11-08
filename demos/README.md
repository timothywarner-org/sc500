# Shared demos

This folder holds demo material that spans more than one lesson. Each lesson's own scripts are listed on that lesson's `demos/` page, for example [`lessons/lesson-08-servers-vms/demos/`](../lessons/lesson-08-servers-vms/demos/), and the files themselves live in [`lab/`](../lab/).

## What is here now

- [Lesson 2: prove workload identity federation](lesson-02-federation.md). An instructor demonstration that runs against the instructor's own lab. Read it to see the pattern; the page explains what your own fork would need.

## How the lab files work

- **Portal first.** Most steps happen in the Azure portal or a Microsoft admin center, because that is where you build the muscle memory the exam rewards. The scripts build the lab, check it, and show the evidence.
- **Your values, in one place.** Run [`lab/Set-LabConfig.ps1`](../lab/Set-LabConfig.ps1) once with your tenant, subscription, domain, and account. Every resource name comes from the lesson's `config.json`.
- **Explained, not black box.** Every script starts with help that says what it reads and what it changes. Read it with `Get-Help <path> -Full` before you run the script.
- **Cleanup at the end.** Every lesson has a `Remove-` script that deletes what its lab created.
- **Fictional data.** Names such as Contoso are made up. See [NOTICE.md](../NOTICE.md).
