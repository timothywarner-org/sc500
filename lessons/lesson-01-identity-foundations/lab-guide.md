# Lesson 1 lab guide

**Identity Foundations: PIM, RBAC, Custom Roles, and Governance Scope**

These are the steps from this lesson's demos, in the order the video runs them. Watch a demo, then do it yourself in your own lab. A step that starts with **Confirm** is a check: find that value on your screen and make sure it matches before you move on, the same way a performance-based exam item grades you.

## Before you start

1. Do the [one-time lab setup](../../lab/README.md) once for the whole course.
2. Deploy this lesson's lab with the **Build** scripts on the [lab files page](demos/README.md).
3. Read this lesson's [Before you start](README.md#before-you-start) list for licenses, costs, and lead times.

> **Your values will differ from the video.** Incident numbers, IDs, times, and generated name endings (shown as `<unique>`) come from the course's lab. Names Azure makes unique across all customers end in your name suffix, and values in angle brackets are yours to fill in.

> **Portals change.** If a menu or label has moved since the course was recorded, the video says so where it matters. If a step no longer matches what you see, open an issue with the *Content question or demo issue* template.

## Demo 1: Activate and test VM maintenance access

### 1.1 Azure portal, as your admin account

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal.

1. Open **vm-maint-01** > **Access control (IAM) > Roles**. Search **Contoso VM Maintenance**; select **View > JSON**.
2. Confirm the VM read, instance-view read and restart permissions, then **AssignableScopes**. The definition is already deployed.
3. Open **Check access > Check access**, select **User, group, or service principal**, and search **Debra Garcia**. Confirm the assignment scope and any inherited grants.

### 1.2 Microsoft Entra admin center, as Debra

**Sign in as:** USER, the lab user Debra. **Where:** Microsoft Entra admin center.

1. Open [PIM > My roles > Azure resources](https://entra.microsoft.com/#view/Microsoft_Azure_PIMCommon/ActivationMenuBlade/~/azurerbac) > **Eligible assignments**.
2. On **Contoso VM Maintenance** at **vm-maint-01**, select **Activate**. Set **Duration** to **1 hour**; enter **SC500-CHG-001 restart vm-maint-01 for ServiceHub maintenance** in **Reason**. Complete the existing MFA challenge if requested; select **Activate**.
3. Open **Active assignments**. Confirm the VM scope and end time.

### 1.3 Azure portal, as Debra

**Sign in as:** USER, the lab user Debra. **Where:** Azure portal.

1. Open **vm-maint-01** > **Overview > Restart > Yes**. Open the completion notification.
2. Open **vm-compare-01**. Confirm the unavailable **Restart** control, or submit **Restart > Yes** if available and show the actual authorization result.

## Demo 2: Limit an Entra role to one application

### 2.1 Microsoft Entra admin center, as your admin account

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Entra admin center.

1. Open **Entra ID > Roles & admins > Contoso Application Basic Editor > Description**. Confirm `applications/standard/read` and `applications/basic/update`.
2. Open **Entra ID > App registrations > All applications > Contoso Maintenance Lab > Roles and administrators > Contoso Application Basic Editor > Assignments > Active assignments**. Confirm Debra and the application scope.

### 2.2 Microsoft Entra admin center, as Debra

**Sign in as:** USER, the lab user Debra. **Where:** Microsoft Entra admin center.

1. Open **Entra ID > App registrations > All applications > Contoso Maintenance Lab > Branding & properties**. Set **Name** to **Contoso Maintenance Lab edited**; select **Save**.
2. Return to **All applications > Contoso Comparison Lab > Branding & properties**. Try **Contoso Comparison Lab edited** in **Name**; select **Save** if enabled. Confirm the actual read-only control or authorization error.
3. Return to **Contoso Maintenance Lab edited > Branding & properties**. Restore **Name** to **Contoso Maintenance Lab**; select **Save**.

## Demo 3: Remove excess access and protect the lab group

### 3.1 Azure portal, as your admin account

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal.

1. Open **vm-compare-01** > **Access control (IAM) > Check access > Check access**. Search **Debra Garcia**; confirm the inherited **Contributor** path through **SC500 Contoso Legacy Operators**.
2. Open **Resource groups > rg-sc500-comparison-lab > Access control (IAM) > Role assignments**. Select the **Contributor** assignment for **SC500 Contoso Legacy Operators**; select **Remove** and confirm.
3. Repeat at **rg-sc500-identity-lab > Access control (IAM) > Role assignments**, removing only that group's **Contributor** assignment.

### 3.2 Azure portal, refreshed signed-in session, as Debra

**Sign in as:** USER, the lab user Debra. **Where:** Azure portal, refreshed signed-in session.

1. Open **vm-compare-01**. Confirm the unavailable **Restart** control or the actual failed restart notification.
2. Return to **vm-maint-01** > **Restart > Yes**. Confirm the result while the narrow maintenance role remains active.

### 3.3 Microsoft Entra admin center, as your admin account

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Entra admin center.

1. Open **ID Governance > Privileged Identity Management > Azure resources**, select your lab subscription, then **Access reviews > SC500 L01 Reader review > Results**. Confirm the completed **Applied** review, Debra's **Denied** decision and **Success** apply result.

### 3.4 Azure portal, as your admin account

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal.

1. Open **rg-sc500-lock-lab** > **Overview**. Use only this empty lab group.
2. Open **Settings > Locks > Add**. Enter **sc500-demo-delete-protection** for **Lock name**; select **Delete** for **Lock type**, then **OK**. Confirm the saved **Delete** lock.
3. Return to **Overview > Delete resource group**. Enter **rg-sc500-lock-lab**; select **Delete**. Open the failure notification and read the lock error.
4. Return to **Locks**. Delete only **sc500-demo-delete-protection**; retain the resource group.

### 3.5 Microsoft Entra admin center, as Debra

**Sign in as:** USER, the lab user Debra. **Where:** Microsoft Entra admin center.

1. Open **PIM > My roles > Azure resources > Active assignments**. On **Contoso VM Maintenance**, select **Deactivate** and confirm.

---

[Lesson README](README.md) | [Lab files](demos/README.md) | [Lab setup](../../lab/README.md) | [Course README](../../README.md)
