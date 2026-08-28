# TAKEOVER-9 lab reproduction — design notes

Status: **not implemented**. Design notes only, saved for a future build pass. Nothing here has been applied to the live lab.

## Why this doc exists

While auditing which Misconfiguration Manager techniques the Mayyhem lab actually reproduces, we found that TAKEOVER-9 is the only one Mayyhem himself skipped for reasons other than fundamental infeasibility (unlike ELEVATE-4/5, which are unreachable in HTTP-only mode). The MM entry for TAKEOVER-9 was an empty stub. We wrote a description PR (in a separate fork of the MM repo, branch `docs/takeover-9-description`), but the lab does not currently expose the attack surface, so we can't independently verify the writeup end-to-end.

This is the plan for making the lab actually vulnerable to TAKEOVER-9 later, so we can (a) prove the description is accurate, (b) hand the SpecterOps SCCM team a working PoC alongside the docs PR, and (c) demonstrate the attack in defensive exercises.

## What TAKEOVER-9 requires (clarified by Mayyhem in the SCCM community Slack, 2026-08-21)

The abuse pattern is **not** SCCM ↔ SCCM linked servers (those exist by default for hierarchy replication, but are configured with `uses_self_credential = 1` passthrough auth — not exploitable via a compromised low-privilege caller).

The exploitable pattern is:

1. A **non-SCCM SQL Server instance** (a third-party product's backend — monitoring, backup/recovery, asset management, CMDB, reporting, ETL, etc.) is configured with a **linked server pointing at an SCCM site database**.
2. The linked server stores a **fixed remote credential** (`uses_self_credential = 0`).
3. That credential is a member of the `sysadmin` role on the SCCM site database.
4. Attacker compromises the third-party SQL (or gets query rights on it — this is a softer target than SCCM's own SQL).
5. Attacker uses SQLRecon to enumerate the linked server, then `EXECUTE ... AT [SCCMSITEDB]` to run T-SQL on the site database as SA.
6. Standard SCCM takeover post-exploitation: insert self into `RBAC_Admins` + `RBAC_ExtendedPermissions` to become Full Administrator (same tail as TAKEOVER-1 / TAKEOVER-2 / TAKEOVER-3).

The important defensive point Mayyhem emphasized: linked-server definitions live on the initiating (third-party) side. Auditing `sys.servers` on the site database will NOT surface them. That's why the misconfig persists in real environments — the SCCM operator can't see it from their side.

## What the lab needs to have to reproduce this

Minimum:

- One additional SQL Server (representing the third-party integration).
- On that SQL: a linked server pointing at `ps1-db.mayyhem.com` with a stored login granted `sysadmin` on `ps1-db`.
- A domain user (the "linked login") — created in AD, granted sysadmin on `ps1-db` only.

Nothing on the SCCM side needs to change. The whole misconfiguration lives on the foreign system.

## Design decisions to make when we build it

### 1. Where does the third-party SQL live?

Three realistic options, in ascending order of realism/effort:

- **A: Repurpose an existing lab VM.** Install SQL Express on, say, `ps1-lib` or `ps1-sec`. Cheapest — no terraform change, no new IP. Downsides: those hosts are SCCM site systems, so a "third-party" SQL on them isn't quite the realistic pattern (auditors would spot it immediately). Fine for a functional PoC.
- **B: Add a new small VM** — one extra `mayyhem-sccm-tp` node running SQL Express, joined to `mayyhem.com`, on a spare IP. Fits the topology story: "org has a third-party monitoring appliance on the LAN." Terraform + Ansible changes needed but small (~50 lines).
- **C: Add a new *unjoined* VM** (workgroup Windows). Would be more realistic ("appliance-shaped SQL box outside the domain") but requires more Ansible plumbing to reach without Kerberos. Not worth the extra work for a PoC.

**Recommendation: B.** New VM, joined, SQL Express. Clear story, small lift.

### 2. What SQL edition to install on the third-party host?

- **SQL Express 2022** — free, downloadable, works for linked servers and `xp_cmdshell`, small footprint (~1 GB install). Fine for the demo.
- **Full SQL Server (Developer edition)** — the same 6 GB install the collection already automates for `install_site_database`. Overkill unless we specifically want the identical setup.

**Recommendation: SQL Express 2022.** Add a small role that mirrors `install_site_database` but points at Express installer. Should be reusable from other lab work.

### 3. What credential does the linked server authenticate as?

- **A: Dedicated AD user** — new user like `MAYYHEM\svc_thirdparty_sccm_link`, granted `sysadmin` on `ps1-db`. Cleanest, stays in Windows auth. Realistic ("service account for the monitoring product's data pull"). Easy to unwind by dropping the user + the SQL login.
- **B: Built-in `sa`** — most textbook, but requires enabling SQL Mixed Mode + setting an `sa` password on ps1-db. More state to unwind. Not more educational for the attacker.
- **C: Existing `MAYYHEM\domainadmin`** — trivially wrong because it defeats the point (domain admin is domain admin either way).

**Recommendation: A.** Named service account (`svc_thirdparty_sccm_link` or `MAYYHEM\sqllinkuser`), granted `sysadmin` on ps1-db only.

### 4. What OLE DB provider?

- The existing SCCM-created link on cas-db uses `SQLNCLI10` — SQL Native Client 10, from the SQL 2008 era. Not installed on modern Server 2022 by default. That's why our probe query failed: "provider has not been registered."
- **`MSOLEDBSQL`** is Microsoft's current-generation OLE DB provider. Installs with the SQL Server 2022 client tools. Working out of the box.

**Recommendation: MSOLEDBSQL.** Install it as part of the third-party host provisioning. Configure the linked server with `@provider='MSOLEDBSQL'`.

### 5. Direction / count of links?

- **One link, third-party → ps1-db.** Minimum viable, matches Mayyhem's description exactly.
- Optionally also **third-party → cas-db** for extra demo material (attacker crawls, finds two SA hops). Marginal added realism.

**Recommendation: one link, third-party → ps1-db.** Keep it clean. Adding cas-db is trivial later if we want.

### 6. Ansible role vs port playbook?

- **Role in the collection** — inappropriate. This is a deliberate misconfiguration, not a general-purpose function. Mayyhem's collection doesn't ship attack scaffolding for the other techniques either.
- **Port-level playbook** — right shape. Something like `vsphere/ansible/misc_takeover9_setup.yml` that:
  1. Creates `MAYYHEM\svc_thirdparty_sccm_link` in AD (via `microsoft.ad.user`).
  2. Installs SQL Express + MSOLEDBSQL on the third-party host.
  3. Grants the service account `sysadmin` on ps1-db (via `sqlcmd -E -Q "CREATE LOGIN [MAYYHEM\...]... ; EXEC sp_addsrvrolemember ..."`).
  4. Creates the linked server on the third-party host (via `sqlcmd -E -Q "EXEC sp_addlinkedserver ...; EXEC sp_addlinkedsrvlogin ..."`).
  5. Verifies with an outbound query from the third-party host: `EXEC ('SELECT @@servername') AT [SCCMSITEDB]` should return `PS1-DB`.

### 7. How to invoke the attack for verification

From the third-party host, running as any account (attacker doesn't need SA on the third-party):

```powershell
# Enumerate linked servers via SQLRecon or plain T-SQL
sqlcmd -E -Q "SELECT name, is_data_access_enabled FROM sys.servers WHERE server_id <> 0"

# Test the pivot — should return sysadmin: True on the remote
sqlcmd -E -Q "SELECT * FROM OPENQUERY([SCCMSITEDB], 'SELECT @@servername AS srv, IS_SRVROLEMEMBER(''sysadmin'') AS sa')"

# Elevate: insert self into RBAC_Admins via EXECUTE ... AT
# (same T-SQL as TAKEOVER-1's example, wrapped in EXEC ('...') AT [SCCMSITEDB])
```

Success signal: the target user appears as Full Administrator in the SCCM console immediately (RBAC_Admins is read live).

## Revert plan

At the code level:
- `git checkout feat/vsphere-port` if the changes are on a separate branch.

At the live-lab level (order matters — undo the exposed link first):
1. On the third-party host: `sp_dropserver @server = 'SCCMSITEDB', @droplogins = 'droplogins'`.
2. On ps1-db: `EXEC sp_dropsrvrolemember @loginame = 'MAYYHEM\svc_thirdparty_sccm_link', @rolename = 'sysadmin'; DROP LOGIN [MAYYHEM\svc_thirdparty_sccm_link]`.
3. On the DC: remove the AD user `svc_thirdparty_sccm_link`.
4. Destroy the third-party host VM (if option B was chosen) via terraform: taint + apply.

None of this touches SCCM's own operational state (site database schema, hierarchy replication, boundary group, etc.).

## Risk assessment

- **Data destruction risk:** none. Everything is additive.
- **SCCM operational impact:** none. The linked server is on a foreign box; SCCM never queries it. Site DB replication (Service Broker, port 4022) is unaffected.
- **Blast radius if the third-party VM is compromised in real life:** the whole point of the technique — that's what we're demonstrating.
- **Blast radius while just having the misconfig in the lab:** limited to the lab subnet. `svc_thirdparty_sccm_link` is a new named account with no purpose outside the linked server, so any use of it is a signal.

## Open questions to answer at build time

1. Do we want to also enable `xp_cmdshell` on ps1-db so the attacker can move from SA-on-SQL to code exec on the SQL host? (Adds one line, deeper impact demo, but wanders slightly outside strict TAKEOVER-9.)
2. Do we want a matching PREVENT-19 demo — a playbook that finds and removes the offending linked server for the defensive-exercise story?
3. Do we want to seed the third-party SQL with a plausibly-named product database (e.g., a `Monitoring` DB with tables like `Events`, `Devices`) so it looks like a real appliance, not an empty SQL Express install? Purely cosmetic.
4. When we push the MM PR for the description, do we push a companion PR to the collection adding a new `takeover_9_setup` role? Probably no — Mayyhem's collection intentionally leaves lab tradecraft out. Keep it as port-only Ansible.

## References

- `docs/takeover-9-description` branch on the `chryzsh/Misconfiguration-Manager` fork — the MM writeup based on Mayyhem's clarification.
- Mayyhem, clarification in the SpecterOps SCCM community Slack, 2026-08-21.
- Sanjiv Kawa, [SQLRecon](https://github.com/skahwah/SQLRecon).
- PREVENT-19 in the MM repo.
