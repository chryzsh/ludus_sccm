# MM technique coverage in this lab

Per-technique implementation notes for the 34
[Misconfiguration-Manager](https://github.com/subat0mik/Misconfiguration-Manager)
attack techniques against this lab (feat/vsphere-port +
feat/exec-2-lab-path + feat/cred-6-plant merged into the deployed
state).

**Coverage summary: 32 / 34.** The two not supported are ELEVATE-4
and ELEVATE-5, both of which require SCCM PKI (HTTPS-only site) —
this lab is an HTTP-configured site by design (matches the CRED-1
threat model). Everything else is reachable end-to-end.

**Status legend:**

- ✅ **Verified** — built this session, exercised in prior sessions,
  or explicitly documented working in the handover.
- 🟢 **Expected** — stock SCCM + this lab's config should make it
  work; not exercised end-to-end from a student box yet.
- ❌ **Not supported** — requires infrastructure the lab does not
  deploy.

Where a technique needs a specific starting credential, that cred is
one of:

- **any-domain-user** = `MAYYHEM\domainuser:Password123` (or any of
  the demo/student accounts; RDP-only on ps1-dev).
- **client-local-admin** = `MAYYHEM\helpdesk` on ps1-dev,
  `MAYYHEM\studentNN` on ps1-lab, or `MAYYHEM\svc_sccm_maint` on
  ps1-dev after CRED-6 loot.
- **SCCM-full-admin** = obtained via TAKEOVER-1 (relay to site DB
  MSSQL) or any of the other TAKEOVER-* chains.
- **NAA** = `MAYYHEM\networkaccess:Password123` (recoverable via
  CRED-1/2/3).

---

## RECON (7 / 7)

| # | Name | Status | Target | How it hits in this lab |
|---|---|---|---|---|
| RECON-1 | LDAP Enumeration | 🟢 | dc (.70) | Stock AD. Any domain user runs `ldeep ldap -d mayyhem.com -u domainuser -p Password123 -s ldap://<dc-ip> users` (verified installed on all student boxes). |
| RECON-2 | SMB Enumeration | 🟢 | any PS1 site system | Stock SCCM shares (`SCCMContentLib$`, `SMS_DP$`, `SMSSIG$`, etc.) exposed by role installation. `smbclient.py mayyhem.com/domainuser:...` → `shares` returns the SCCM-role fingerprint. |
| RECON-3 | HTTP Enumeration | 🟢 | ps1-mp (.78), ps1-dp (.77) | MP and DP web endpoints served over 80/tcp (HTTP-only site). `sccmhunter find -u domainuser -p Password123 -d mayyhem.com -dc-ip <dc-ip>` returns MP+DP inventory (verified per handover). |
| RECON-4 | CMPivot | 🟢 | ps1-pss (.80) | Requires SCCM admin. Reachable via TAKEOVER-1 chain, or now more directly via the NAA's "Script Approvers" role for read-only queries. |
| RECON-5 | SMS Provider Enumeration | 🟢 | ps1-sms (.79) | SMS Provider role installed on ps1-sms (separate from ps1-pss). SCCM-admin required. SharpSCCM `get users` / `get devices` against `\\ps1-sms.mayyhem.com`. |
| RECON-6 | Remote Registry Enumeration | 🟢 | ps1-pss, ps1-dp, ps1-mp | Stock Windows remote registry enum from a domain user. SCCM role fingerprints visible under `HKLM\SOFTWARE\Microsoft\SMS\...`. |
| RECON-7 | Local File Site Enumeration | 🟢 | ps1-dev (.81) or ps1-lab (.84) | Requires local admin on a CM client. `helpdesk` (on ps1-dev) or `studentNN` (on ps1-lab) both have it. `C:\Windows\CCM\Logs\*.log`, `C:\Windows\ccmcache\`, etc. |

---

## CRED (8 / 8)

| # | Name | Status | Target | How it hits in this lab |
|---|---|---|---|---|
| CRED-1 | PXE Credentials | ✅ | ps1-dp (.77) | PXE enabled (`ludus_sccm_enable_pxe: true`), no PXE password (`ludus_enable_pxe_password: false`). `pxehacker` from any student box → decrypt embedded TS policy → recover `MAYYHEM\sccm_push:Password123` from the Deploy-OS task sequence (that account is used for both client push and domain join). |
| CRED-2 | Policy Request Credentials | 🟢 | ps1-mp (.78) | MP accepts client registration under stock auto-approve setting; `MachineAccountQuota` is AD default (10). `SharpSCCM.exe get secrets` from any joined box (or `sccmwtf` after adding a machine object). Recovers NAA + Deploy-OS TS variables. |
| CRED-3 | DPAPI Credentials | ✅ | ps1-dev (.81) or ps1-lab (.84) | NAA cache confirmed present on ps1-lab per phase 37's post-install verify. Requires local admin on the client. `SharpSCCM.exe local secrets` decrypts the DPAPI-wrapped NAA + policy blobs. |
| CRED-4 | Legacy Credentials | 🟢 | ps1-dev, ps1-lab | Legacy CIM repo location (`%WinDir%\System32\wbem\Repository\OBJECTS.DATA`) is still populated on Current-Branch SCCM for backward-compat entries. Local admin on client. Rarely yields new creds beyond CRED-3, but the code path fires. |
| CRED-5 | Site Database Credentials | 🟢 | ps1-db (.74) | Requires primary-site-server admin OR direct DB read. Reachable post-TAKEOVER-1 (relay to site DB MSSQL). Once inside, `SharpSCCM.exe get secrets --database` decrypts the encrypted `RBAC_SecuredObjects` and `CI_ConfigurationItems` rows. |
| CRED-6 | Looting Distribution Points | ✅ | ps1-dp (.77) | **Planted by `misc_plant_cred6_share.yml`** (feat/cred-6-plant). Non-default share `Scripts` on ps1-dp, domain-user-readable, contains `Reset-SCCMClientCache.ps1` with `svc_sccm_maint:Password123!` hardcoded. `smbclient.py mayyhem.com/domainuser:...@<ps1-dp-ip>` → `use Scripts` → `get Reset-SCCMClientCache.ps1` → grep for password. Verified: looted cred WinRMs into ps1-dev as local admin. |
| CRED-7 | AdminService API Credentials | 🟢 | ps1-sms (.79) | SMS Provider hosts the AdminService REST endpoint. SCCM-admin required. Post-TAKEOVER-1. `Invoke-RestMethod https://ps1-sms/AdminService/wmi/SMS_R_User -UseDefaultCredentials` etc. |
| CRED-8 | Policy Creds MP Relay | 🟢 | ps1-mp (.78) → ps1-db (.74) | SMB signing not enforced on MP (only ps1-sec has enforcement, via the ELEVATE-2 lab-change playbook). Coerce a client, relay to MP, request policy, extract secrets. Standard MP-relay setup. |

---

## ELEVATE (4 / 6)

| # | Name | Status | Target | How it hits in this lab |
|---|---|---|---|---|
| ELEVATE-1 | Relay to Site System (SMB) | 🟢 | ps1-pss (.80) → site systems | Site server's machine account is admin on multiple site systems (installed by SCCM setup). No SMB signing on most site systems (only ps1-sec has it, deliberately for the ELEVATE-2/PREVENT-12 experiment). `ntlmrelayx --smb2support -t smb://ps1-mp` etc. |
| ELEVATE-2 | Relay Client Push Installation | ✅ | CM clients | Automatic client push enabled (`ludus_sccm_enable_automatic_client_push_installation: true`). `MAYYHEM\sccm_push` is a member of the `sccm_push_accounts` group which the "SCCM Push Account Local Admin" GPO grants local Administrator on every CM client. Push authentication is relayable. Prior-session experiment confirms this path; ps1-sec has been hardened as the relay target for the PREVENT-12 measurement (`misc_enforce_smb_signing_ps1_sec.yml`). |
| ELEVATE-3 | Relay Client Push + AD Discovery | 🟢 | any PS1 site system | AD System/Group/User Discovery all enabled (`enable_active_directory_*_discovery: true` per install_primary_site defaults). Push installer triggered against attacker-controlled discovered host → relayable auth. |
| ELEVATE-4 | PXE PKI Credentials | ❌ | — | Requires PKI-configured PXE (client authentication certificates from the CA). This lab runs HTTP-only PXE by design. To enable: switch to PKI issuance on the DP, add ADCS PKI template, re-issue the boot image. Out of scope. |
| ELEVATE-5 | OSD PKI Credentials | ❌ | — | Requires PKI-configured OSD media. Same reason as ELEVATE-4. |
| ELEVATE-6 | LPE via Writable Client Cache | 🟢 | ps1-dev (.81), ps1-lab (.84) | Any CM client with `C:\Windows\ccmcache\` writable by SYSTEM (default) is vulnerable. Requires SYSTEM already (local admin escalates trivially via ccmcache package replacement). |

---

## EXEC (2 / 2)

| # | Name | Status | Target | How it hits in this lab |
|---|---|---|---|---|
| EXEC-1 | App Deployment | 🟢 | ps1-pss (.80) | SCCM-admin required (TAKEOVER-1 chain). `SharpSCCM.exe exec -d <collection> -p <program>`. |
| EXEC-2 | Script Deployment | ✅ | ps1-pss (.80) | **Wired this session** (feat/exec-2-lab-path). NAA has custom `Script Approvers` role: can Read+Approve+Modify SMS Scripts (no Run Script, no Create/Delete). Two-cred chain: NAA approves (from CRED-1/2/3), TAKEOVER-1 Full Admin executes. Deployed via `misc_grant_naa_script_approver.yml`. |

---

## TAKEOVER (9 / 9)

| # | Name | Status | Target | How it hits in this lab |
|---|---|---|---|---|
| TAKEOVER-1 | Relay to Site DB (MSSQL) | 🟢 | ps1-db (.74) | Coerce ps1-pss (via PetitPotam / SCNotification / etc.), relay ps1-pss$ auth to MSSQL on ps1-db. ps1-pss$ has sysadmin on the site DB (stock SCCM setup). Result: full DB read/write → escalate to SCCM Full Administrator. This is the workshop's canonical entry to admin-level attacks. |
| TAKEOVER-2 | Relay to Site DB (SMB) | 🟢 | ps1-db (.74) | Same coercion, SMB endpoint instead of MSSQL. ps1-pss$ is local admin on ps1-db (stock). |
| TAKEOVER-3 | Relay to AD CS | 🟢 | dc (.70) | ADCS installed on dc via `install_adcs` role. Web enrollment is stock (ESC8 territory). PetitPotam-style coerce → relay to `http://dc/certsrv/certfnsh.asp` → issue cert for coerced identity → auth as it. |
| TAKEOVER-4 | Relay CAS to Child | 🟢 | cas-pss (.73) → ps1-pss (.80) | CAS (`cas-pss`) exists as parent of PS1. Coerce cas-pss, relay to ps1-pss over SMB (CAS site server's machine account has admin on child primaries). |
| TAKEOVER-5 | Relay to AdminService | 🟢 | ps1-sms (.79) | SMS Provider role separated onto ps1-sms. AdminService exposed on the SMS provider. Coerce → relay to the REST endpoint with a client cert or NTLM. |
| TAKEOVER-6 | Relay to SMS Provider (SMB) | 🟢 | ps1-sms (.79) | Same coerce, SMB endpoint. `ps1-pss$` and `cas-pss$` are admins on ps1-sms. |
| TAKEOVER-7 | Relay Between HA | 🟢 | ps1-pss (.80) ↔ ps1-psv (.76) | Passive site server ps1-psv exists (installed by phase 50's `install_passive_site_server`). HA pair mutually-admins each other. Coerce → relay across the pair. |
| TAKEOVER-8 | Relay to LDAP | 🟢 | dc (.70) | Stock DC — LDAP signing NOT enforced (default AD config). Coerce → relay HTTP → LDAP → RBCD on the coerced identity. |
| TAKEOVER-9 | SQL Linked as DBA | ✅ | monitor (.83) → ps1-db (.74) | Set up via `misc_takeover9_setup.yml`. Third-party SQL host `monitor` has a linked server pointing at the SCCM site DB (`ps1-db`) with DBA privileges. Crawl the link from a `monitor` foothold → sysadmin on the site DB → SCCM Full Administrator. |

---

## COERCE (2 / 2)

| # | Name | Status | Target | How it hits in this lab |
|---|---|---|---|---|
| COERCE-1 | CMPivot Coercion | 🟢 | ps1-pss (.80) | CMPivot admin required (SCCM Full Admin or CMPivot-scoped role). Craft a query that triggers outbound SMB from the client → relayed. |
| COERCE-2 | CcmExec Coercion | 🟢 | ps1-dev, ps1-lab, ps1-pss (SCCM client role) | SCNotification AppDomainManager Injection. Local admin on any CM client (helpdesk, studentNN, or post-CRED-6 svc_sccm_maint). Very reliable coercion primitive for feeding all TAKEOVER-* relays. |

---

## Not supported (2 techniques)

Both require SCCM PKI (HTTPS-only site with client authentication
certificates issued by an internal CA). This lab is HTTP-configured
by design because:

- The CRED-1 (PXE) attack surface requires HTTP PXE, and CRED-1 is
  the workshop's canonical "day 0 primitive from an unauthenticated
  attacker" — a foundational technique the workshop teaches.
- Adding PKI without also serving HTTP would break the CRED-1 lab
  path.
- Running both PKI and HTTP concurrently on the same DP is possible
  but adds significant install complexity for two techniques that
  aren't in the workshop syllabus.

| # | Name | Status | Why not | To enable |
|---|---|---|---|---|
| ELEVATE-4 | PXE PKI Credentials | ❌ | HTTP-only PXE | Issue a PKI cert to ps1-dp, `Set-CMDistributionPoint -EnableForPXE $true -AllowClientCertificate ...`, re-issue boot image. |
| ELEVATE-5 | OSD PKI Credentials | ❌ | HTTP-only OSD | Same PKI setup; then generate PKI-encoded OSD media instead of stock. |

Either could be added later as its own opt-in misc playbook + role
change, following the EXEC-2 / CRED-6 pattern.

---

## Verification quick-reference

| Family | Fastest smoke test from a student box |
|---|---|
| RECON | `ldeep ldap -d mayyhem.com -u domainuser -p Password123 -s ldap://<dc-ip> users` |
| RECON | `sccmhunter find -u domainuser -p Password123 -d mayyhem.com -dc-ip <dc-ip>` |
| CRED-1 | `pxehacker <ps1-dp-ip>` (open PXE, decrypts to `domainjoin:Password123`) |
| CRED-6 | `smbclient.py 'mayyhem.com/domainuser:Password123@<ps1-dp-ip>'` → `shares` → `Scripts` |
| ELEVATE-2 | RelayInformer + trigger client push against an attacker-controlled hostname |
| EXEC-2 | `sccmhunter script -u networkaccess -p Password123 -d mayyhem.com -dc-ip <dc-ip>` (approve as NAA, execute as TAKEOVER-1 full admin) |
| TAKEOVER-9 | Auth to `monitor` MSSQL → `EXEC ... AT [PS1-DB]` |

Full technique descriptions in the
[Misconfiguration-Manager repo](https://github.com/subat0mik/Misconfiguration-Manager).
