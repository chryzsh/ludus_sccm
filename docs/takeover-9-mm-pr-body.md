# PR body for `subat0mik/Misconfiguration-Manager` — flesh out TAKEOVER-9

Copy the section below into the PR description on GitHub.

---

## Flesh out TAKEOVER-9

### What this changes

`attack-techniques/TAKEOVER/TAKEOVER-9/takeover-9_description.md` was a stub — title + SQLRecon reference only, with empty Description / Requirements / Summary / Impact / Examples. This PR fills those sections in.

Two commits:
1. Initial write-up based on the abuse scenario Chris Thompson (Mayyhem) clarified in the SpecterOps SCCM community Slack on 2026‑08‑21.
2. Refinements after reproducing the attack end-to-end in a lab: the SQL-authentication requirement on the site database, and a defender-oriented note about SCCM's own hierarchy-replication linked server (which is not the TAKEOVER-9 target and is a common false trail).

### The abuse scenario in one paragraph

A third-party product's SQL Server instance (backup/recovery, monitoring, asset/CMDB, custom reporting or ETL, …) is configured with a linked server pointing at an SCCM site database, storing a fixed SQL credential that has `sysadmin` on the site database. An attacker who lands on the third-party SQL — typically a softer target than SCCM's own SQL — enumerates linked servers with SQLRecon, identifies the SA-privileged hop, and uses `EXECUTE (…) AT [LinkedServerName]` to run T-SQL on the site database as SA. Post-exploitation is identical to TAKEOVER-1 / TAKEOVER-2 / TAKEOVER-3 after site-database access is obtained: insert the attacker into `RBAC_Admins` and `RBAC_ExtendedPermissions` to gain the SCCM "Full Administrator" role.

### Why the misconfiguration is hard to spot from the SCCM operator's perspective

Linked-server definitions and stored credentials live on the initiating side (the third-party host), not the target. Auditing `sys.servers` on the site database will never surface a third-party-side link pointing inward. Authentication logs on the site database show a normal SQL-login sign-on, because the stored credential is legitimate. Third-party SQL instances often fall outside the SCCM team's operational scope and are inspected less rigorously than SCCM's own site systems. PREVENT-19's guidance ("audit and remove unnecessary links to site databases, particularly those created with DBA privileges") is best implemented by inventorying SQL Server instances *around* SCCM — not just the SCCM SQL hosts themselves — for links pointing at the site database.

### What was validated in a lab

The lab used to validate this write-up runs SCCM 2403 (CAS + child primary) on an in-house vSphere port of Mayyhem's `ludus_sccm` collection. The following were confirmed:

- The SCCM-native linked server on the CAS side (`sys.servers` on cas-db) is created with `uses_self_credential = 1` and — on this collection's install path — is registered against the legacy `SQLNCLI10` OLE DB provider, which isn't installed on the site-database host. It's inert; it isn't the TAKEOVER-9 attack surface.
- Standing up an additional SQL Server instance representing a "third-party monitoring product," creating a linked server on it pointing at the primary site's SQL with a stored SQL login granted `sysadmin` on the site database, is sufficient to reproduce the attack. `OPENQUERY([SCCMSITEDB], 'SELECT @@servername, IS_SRVROLEMEMBER(''sysadmin'')')` returned `ps1-db, 1` — confirming the pivot lands as SA.
- The linked-server credential path in practice requires the site database to accept SQL Server authentication (mixed mode, `LoginMode = 2` under the versioned-instance registry key). The Windows-login-with-stored-password path exists on paper but requires Kerberos delegation from the third-party SQL host and is rarely how a real integration is set up.

### Changes vs upstream

Diff scope: one file (`attack-techniques/TAKEOVER/TAKEOVER-9/takeover-9_description.md`), 99 lines of stub replaced with a full write-up matching the style of TAKEOVER-1 / TAKEOVER-3.

Nothing else touched.

### Credits

Thanks to Chris Thompson (Mayyhem) for clarifying the intended abuse scenario for TAKEOVER-9 in the SpecterOps SCCM community Slack.

### Reviewers

Anyone from the MM maintainer team. I'll re-request review after any changes.
