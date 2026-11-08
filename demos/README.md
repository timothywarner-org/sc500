# Shared demos

This folder holds demo material that spans more than one lesson. Walkthroughs for a single lesson live in that lesson's `demos/` folder, for example [`lessons/lesson-08-servers-vms/demos/`](../lessons/lesson-08-servers-vms/demos/).

## What is here now

- [Lesson 2: prove workload identity federation](lesson-02-federation.md). An instructor demonstration that runs against the instructor's own lab. Read it to see the pattern; the page explains what your own fork would need.

## How the walkthroughs work

- **Portal first.** Most steps happen in the Azure portal or a Microsoft admin center, because that is where you build the muscle memory the exam rewards.
- **Your values, in one place.** Each walkthrough starts with a short settings block for your subscription, region, and resource names. Change it once and every later step uses it.
- **Explained, not black box.** Any Bicep template or script is explained before you run it, so you know what it creates and why.
- **Cleanup at the end.** Every walkthrough finishes with the steps that delete what it created and the paid plans to turn off.
- **Fictional data.** Names such as Contoso are made up. See [NOTICE.md](../NOTICE.md).
