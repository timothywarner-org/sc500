# Lesson 2 lab guide

**Entra ID Access: MFA, Conditional Access, Apps, and Managed Identities**

These are the steps from this lesson's demos, in the order the video runs them. Watch a demo, then do it yourself in your own lab. A step that starts with **Confirm** is a check: find that value on your screen and make sure it matches before you move on, the same way a performance-based exam item grades you.

## Before you start

1. Do the [one-time lab setup](../../lab/README.md) once for the whole course.
2. Deploy this lesson's lab with the **Build** scripts on the [lab files page](demos/README.md).
3. Read this lesson's [Before you start](README.md#before-you-start) list for licenses, costs, and lead times.

> **Your values will differ from the video.** Incident numbers, IDs, times, and generated name endings (shown as `<unique>`) come from the course's lab. Names Azure makes unique across all customers end in your name suffix, and values in angle brackets are yours to fill in.

> **Portals change.** If a menu or label has moved since the course was recorded, the video says so where it matters. If a step no longer matches what you see, open an issue with the *Content question or demo issue* template.

## Demo 1: Protect ServiceHub sign-ins

### 1.1 Microsoft Entra admin center, as your admin account

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Entra admin center.

1. Open Entra ID > Authentication methods > Policies > **Passkey (FIDO2)**.
2. On **Enable and target > Include**, confirm **Enable: On** and **SC500-L02-Passkey-Pilot**.
3. Select **Configure**. Read the **Default passkey profile** row: attestation **Yes**, passkey type **Device-bound**, key restrictions **No**.
4. Open **Entra ID > Groups > All groups**. Search **SC500-L02-Passkey-Pilot**; open it, then **Members**. Confirm Garth as the only member.

### 1.2 Microsoft Entra admin center, as your admin account

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Entra admin center.

1. Open Entra ID > Users > All users.
2. Search `sc500.garth@<your-domain>` and open **SC-500 L02 Garth Fort**.
3. Select **Authentication methods**. Open his existing **Passkey (FIDO2)** entry and show the Authenticator passkey details. Leave the credential in place.
4. Open Entra ID > Conditional Access > Authentication strengths.
5. Open **Phishing-resistant MFA**.
6. Read its allowed methods: passkeys/FIDO2, Windows Hello for Business or platform credential, and multifactor certificate-based authentication.

### 1.3 Conditional Access, as your admin account

**Sign in as:** ADMIN, your admin account. **Where:** Conditional Access, Policies.

1. Open Entra ID > Conditional Access > Policies.
2. Search **SC500-L02**. Open **SC500-L02-Garth-PhishingResistant-REPORTONLY**, then **View or Edit**.
3. Open **Users, agents or workload identities**. Under **Include**, confirm Garth's selected account.
4. Open **Target resources**. Confirm **SC500-L02-Contoso-ServiceHub-API** as the selected resource.
5. Open **Grant**. Confirm **Require authentication strength > Phishing-resistant MFA**.
6. Close the Grant pane. Confirm **Enable Policy: Report-only**. Leave it selected.

### 1.4 PowerShell 7, as your admin account

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7, C:\github\sc500\lab.

1. Open the lab folder and launch the sign-in:

```powershell
Set-Location -LiteralPath 'C:\github\sc500\lab'
./scripts/lesson-02/Invoke-L02GarthSignIn.ps1
```

### 1.5 Microsoft sign-in page opened by the helper, as Garth

**Sign in as:** USER, the lab user Garth. **Where:** Microsoft sign-in page opened by the helper.

1. Choose `sc500.garth@<your-domain>`, or **Use another account** and enter that UPN.
2. Choose the existing passkey through **Sign-in options**. Follow the browser's passkey prompt and approve on Garth's registered device.

### 1.6 PowerShell 7, as your admin account

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7.

1. Return to PowerShell. Read `tokenIssued`, `requestedResource`, `checkedAt`, and `correlationId` from the printed result.

### 1.7 Microsoft Entra admin center, as your admin account

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Entra admin center.

1. Open Entra ID > Users > All users > **SC-500 L02 Garth Fort** > Sign-in logs.
2. In **User sign-ins (interactive)**, open the new **SC500-L02-Contoso-ServiceHub-Client** event.
3. On **Basic info**, match the time and correlation ID to PowerShell. Read **Resource**: it must be the ServiceHub API, not Microsoft Graph.
4. Select **Authentication Details** and read the method actually used.
5. Select **Report-only**. Read the result for **SC500-L02-Garth-PhishingResistant-REPORTONLY**.

### 1.8 Conditional Access, as your admin account

**Sign in as:** ADMIN, your admin account. **Where:** Conditional Access, Policies.

1. Open Entra ID > Conditional Access > Policies.
2. Open **SC500-L02-Workload-Risk-REPORTONLY > View or Edit**.
3. Open **Users, agents or workload identities**. Confirm the selected workload identity: **SC500-L02-Contoso-ServiceHub-Client**.
4. Open **Conditions > Service principal risk**. Confirm **High**.
5. Open **Grant**. Confirm **Block access**. Close the pane; leave the policy **Report-only**.

## Demo 2: Follow and revoke a lab grant

### 2.1 App registrations, as your admin account

**Sign in as:** ADMIN, your admin account. **Where:** App registrations.

1. Open Entra ID > App registrations > All applications.
2. Search **SC500-L02-Contoso-ServiceHub-Client**. Open **Overview**; confirm **Application (client) ID** and **Object ID**.
3. Open **API permissions**. Confirm delegated **Maintenance.Read** and application **Maintenance.Read.All** under the ServiceHub API.
4. Open **Entra ID > Enterprise apps > All applications**. Search the same client name and open **Overview**.
5. Compare **Application ID** and **Object ID** with the registration: same application ID, different object ID.

### 2.2 Microsoft Entra admin center, as your admin account

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Entra admin center.

1. Open Entra ID > App registrations > All applications > **SC500-L02-Contoso-ServiceHub-API**.
2. Select **Expose an API**. Confirm **Maintenance.Read** and its administrator-consent requirement.
3. Select **App roles**. Confirm **Maintenance.Read.All**, allowed for **Applications**.

### 2.3 PowerShell 7, as your admin account

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7, C:\github\sc500\lab.

1. Read the current grants:

```powershell
./scripts/lesson-02/Show-L02Consent.ps1 -Action Inspect
```

2. Confirm **Delegated grants for Garth: 1**, `consentType: Principal` and `scope: Maintenance.Read`. The application-role count is separate.
3. Revoke that delegated grant:

```powershell
./scripts/lesson-02/Show-L02Consent.ps1 -Action Revoke
```

4. Read the new counts: Garth's delegated grant **0**, application role assignment **1**.
5. Restore the grant and show both counts back at **1**:

```powershell
./scripts/lesson-02/Show-L02Consent.ps1 -Action Restore
```

### 2.4 Microsoft Entra admin center, as your admin account

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Entra admin center.

1. Open Entra ID > Enterprise apps > Consent and permissions.
2. Select **User consent settings**. Read the currently selected policy without changing it.
3. Select **Permission classifications**. Open the **Low** classification to show how individual delegated permissions are categorized.
4. Select **Admin consent settings**. Confirm the request setting, reviewers, notifications, reminders and request-expiry field.
5. Open the Contoso worked example (shown in the video). Walk through its proposed values. Keep these tenant-wide settings unchanged.

## Demo 3: Prove ServiceHub's job identities

### 3.1 Azure portal, as your admin account

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, aci-sc500-l02-identity.

1. Open Resource groups > **rg-sc500-l02-identity** > **aci-sc500-l02-identity** > Identity.
2. Use the prepared system-only setup (shown in the video). On **System assigned**, confirm **Status: On** and its principal ID.

### 3.2 PowerShell 7, as your admin account

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7, C:\github\sc500\lab.

1. In ADMIN PowerShell, run:

```powershell
./scripts/lesson-02/Invoke-L02IdentityProbe.ps1 -Identity SystemAssigned
```

2. Read the **system-assigned** row: `readStatus 200`, `writeStatus 403`, `writeErrorCode AuthorizationFailed`.

### 3.3 Azure portal, as your admin account

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, aci-sc500-l02-identity.

1. Between the two setups, use the user-assigned preparation (shown in the video) to restore the attachment. Refresh the resource page.
2. Open Resource groups > **rg-sc500-l02-identity** > **aci-sc500-l02-identity** > Identity.
3. On **User assigned**, confirm **id-sc500-l02-servicehub**.

### 3.4 PowerShell 7, as your admin account

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7.

1. In ADMIN PowerShell, run:

```powershell
./scripts/lesson-02/Invoke-L02IdentityProbe.ps1 -Identity UserAssigned
```

2. Read the **user-assigned** row: **200** for the read, **403 AuthorizationFailed** for the tag write.

### 3.5 Azure portal, as your admin account

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, id-sc500-l02-servicehub.

1. Open Resource groups > **rg-sc500-l02-identity** > **id-sc500-l02-servicehub** > Federated credentials.
2. Open **github-sc500-lesson02**. Read the three trust values:

### 3.6 Edge, as your admin account

**Sign in as:** ADMIN, your admin account. **Where:** Edge, GitHub as your account, Settings, Environments.

1. Open GitHub , `<your-github-owner>/sc500` > Settings > Environments.
2. Open **sc500-lesson02**.
3. Confirm its deployment branch setting, **Selected branches and tags**, with its single rule, **main**.

### 3.7 PowerShell 7, as your admin account

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7, C:\github\sc500\lab.

1. In ADMIN PowerShell, start the existing workflow:

```powershell
gh workflow run sc500-lesson02-oidc.yml --repo <your-github-owner>/sc500 --ref main
```

### 3.8 Edge, as your admin account

**Sign in as:** ADMIN, your admin account. **Where:** Edge, GitHub as your account, Lesson 2 workflow.

1. Open the **Lesson 2 workflow**. Open the new run, then the **prove-reader-boundary** job.
2. Expand **Exchange GitHub OIDC identity for the Contoso managed identity**.
3. Expand **Read the target and demonstrate rejected tag write**. Read **200**, **403** and **AuthorizationFailed**.

---

[Lesson README](README.md) | [Lab files](demos/README.md) | [Lab setup](../../lab/README.md) | [Course README](../../README.md)
