# PR draft — Add opt-in Script Approvers RBAC for NAA (EXEC-2)

Ready-to-open pull request against **`Mayyhem/ludus_sccm`**. Copy-paste
the title and body below into GitHub's PR form. Both are written with
GFM in mind — paragraph breaks are blank lines so they render right.

## Where to open it

- **Base:** `Mayyhem/ludus_sccm:main`
- **Head:** `chryzsh:feat/script-approver-role`
- **Direct link:** <https://github.com/Mayyhem/ludus_sccm/compare/main...chryzsh:ludus_sccm:feat/script-approver-role>

The head branch is on `origin` as a single clean commit
(`f30eae1`) on top of upstream `main` — nothing further to push
before opening.

## Title

```
Add opt-in Script Approvers RBAC for NAA (EXEC-2 lab path)
```

## Body

---

## Summary

- Two new plugin modules for managing SCCM RBAC — `create_script_approver_role`
  (creates a custom security role by copying a source and applying a hardcoded
  permission set) and `add_administrative_user` (grants a security role to a
  domain user or group). No existing module in the collection touches SCCM RBAC.
- New task file `roles/install_primary_site/tasks/config_naa_admin.yml` uses
  those two modules to grant the NAA a custom **"Script Approvers"** role
  matching Microsoft's documented definition on the SMS Scripts axis
  (Site: Read; SMS Scripts: Read, Approve, Modify).
- Included from `install_primary_site`'s `main.yml` right after `config_naa.yml`,
  gated on a new `ludus_sccm_naa_grant_script_approver` variable that defaults
  to `false` in `defaults/main.yml` and is turned on in `new-config.yml` for the
  PS1 primary as the example wiring.

## Why

[CRED-1](https://github.com/subat0mik/Misconfiguration-Manager/blob/main/attack-techniques/CRED/CRED-1/cred-1_description.md),
[CRED-2](https://github.com/subat0mik/Misconfiguration-Manager/blob/main/attack-techniques/CRED/CRED-2/cred-2_description.md),
and
[CRED-3](https://github.com/subat0mik/Misconfiguration-Manager/blob/main/attack-techniques/CRED/CRED-3/cred-3_description.md)
all recover the Network Access Account credentials from various angles.
The NAA ships with no SCCM RBAC rights, so recovering it in the stock
lab dead-ends unless the student separately obtains an SCCM admin cred.

[EXEC-2](https://github.com/subat0mik/Misconfiguration-Manager/blob/main/attack-techniques/EXEC/EXEC-2/exec-2_description.md)'s
requirements doc explicitly names a custom RBAC role granting script
approval rights as one route to the technique. Wiring the NAA to hold
exactly that role — Microsoft's own documented "Script Approvers" — turns
the CRED-* chain from "you have a cred with no privilege" into "you have
half of what you need for EXEC-2." The other half (Collection: Run Script)
is intentionally left out so a single-cred path doesn't short-circuit the
narrative — the intended chain is NAA approves, a separate SCCM-admin
cred (e.g. from a TAKEOVER-* chain) executes.

## Design

- **Opt-in gate.** The behaviour is default-off in
  `defaults/main.yml` (`ludus_sccm_naa_grant_script_approver: false`) and
  turned on in `new-config.yml` for the PS1 primary. Matches the collection's
  pattern of shipping deliberate misconfigurations as example wiring rather
  than defaults.
- **Two general-purpose modules** rather than one narrowly-scoped module:
  - `create_script_approver_role` starts from `Copy-CMSecurityRole -SourceRoleName 'Read-only Analyst'`
    and layers `Set-CMSecurityRolePermission` on top. The read surface is
    broader than Microsoft's narrow four-bit Script Approvers definition
    because `Copy-CMSecurityRole` inherits the source's full permission set
    and `Set-CMSecurityRolePermission` does not clear un-named categories —
    the module description acknowledges this explicitly. The permission
    hashtable is reconciled every run, so editing it in a later revision
    picks up on re-deploy without a manual role delete.
  - `add_administrative_user` handles the three admin-user states cleanly:
    create if missing (with a security scope), add role if user exists
    without it, no-op if user already has the role.
- **`config_naa_admin.yml` uses the same become-user convention as
  `config_naa.yml`** (`ludus_domain_netbios_name` for `ansible_become_user`
  under runas), and is included by `install_primary_site`'s `main.yml`
  immediately after `config_naa.yml` so both tasks share the same NAA
  configuration cadence.
- **Two-cred chain is intentional.** The `Site: Read` + `SMS Scripts: Read,
  Approve, Modify` permission set does not include `Collection: Run Script`.
  A student who recovers only the NAA cred can approve a script but cannot
  execute it — they need a separately-obtained SCCM-admin cred (e.g. from a
  TAKEOVER-1 relay) for the execute step. This preserves the pedagogical
  chain of CRED-* + TAKEOVER-* → EXEC-2 rather than collapsing it.

## Test plan

- [x] Deployed to a live range: `create_script_approver_role` created
  the `Script Approvers` role with the expected permission bits;
  `add_administrative_user` added `MAYYHEM\networkaccess` as an SCCM
  administrative user with that role. `Get-CMSecurityRole -Name 'Script Approvers'`
  and `Get-CMAdministrativeUser -Name 'MAYYHEM\networkaccess'` both return
  the expected state.
- [x] Re-ran the role: `changed=0`, confirmed idempotent. Permission
  hashtable reconciled onto the pre-existing role without a manual
  delete.
- [ ] Reviewer to confirm it fits the collection's module + role conventions.

## Files touched

```
new-config.yml                                          |   2 +
plugins/modules/add_administrative_user.ps1             |  35 +++++++++++++
plugins/modules/add_administrative_user.py              |  48 +++++++++++++++++
plugins/modules/create_script_approver_role.ps1         |  44 +++++++++++++++
plugins/modules/create_script_approver_role.py          |  45 +++++++++++++++
roles/install_primary_site/defaults/main.yml            |   8 ++
roles/install_primary_site/tasks/config_naa_admin.yml   |  24 ++++++++
roles/install_primary_site/tasks/main.yml               |   8 ++
8 files changed, 214 insertions(+)
```

---

## GFM rendering notes

- All paragraph breaks are blank lines — safe.
- Bullet lists render one item per line automatically.
- Fenced code blocks (title, file-diff summary) render line-oriented.
- No trailing-space line breaks or `<br>` tricks used — nothing to lose
  if an editor strips whitespace.
