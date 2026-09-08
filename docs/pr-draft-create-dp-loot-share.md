# PR draft — Add `create_dp_loot_share` role

Ready-to-open pull request against **`Mayyhem/ludus_sccm`**. Copy-paste
the title and body below into GitHub's PR form. Both are written with
GFM in mind — paragraph breaks are blank lines so they render right.

## Where to open it

- **Base:** `Mayyhem/ludus_sccm:main`
- **Head:** `chryzsh:feat/create-dp-loot-share`
- **Direct link:** <https://github.com/Mayyhem/ludus_sccm/compare/main...chryzsh:ludus_sccm:feat/create-dp-loot-share>

The head branch is on `origin` as a single clean commit
(`f51c426`) on top of upstream `main` — nothing further to push
before opening.

## Title

```
Add create_dp_loot_share role to make CRED-6 productive
```

## Body

---

## Summary

- New `create_dp_loot_share` role: plants a non-default SMB share on
  the distribution point containing a PowerShell utility with hardcoded
  service-account credentials, so
  [CRED-6](https://github.com/subat0mik/Misconfiguration-Manager/blob/main/attack-techniques/CRED/CRED-6/cred-6_description.md)
  (loot creds from SCCM Distribution Points and other site server
  shares) becomes a productive attack path against the lab.
- Wired into `new-config.yml` on `ps1-dp` as an opt-in role — a
  student who enumerates site-system shares finds a `Scripts` share
  (not in the RECON-2 SCCM baseline), downloads
  `Reset-SCCMClientCache.ps1`, greps for `password`, and pulls a
  working credential.

## Why

Stock SCCM leaves nothing loot-worthy on the DP. `SCCMContentLib$`
holds only WIM/boot media; no scripts, no config files, no hardcoded
credentials. CRED-6 techniques (CMLoot, sccm-http-looter,
`smbclient.py` share enumeration) still execute against the lab, but
the output contains no credentials, so the attack dead-ends.

Real environments hit CRED-6 pay-dirt because admins routinely leave
scripts with hardcoded credentials on non-default shares of SCCM
infrastructure hosts — the CRED-6 doc itself lists this as one of the
"real-life examples" of finding sensitive data. This role plants that
misconfiguration on the DP so the lab reflects the real thing.

## Design

- **Opt-in by nature.** The role is not part of any default install
  path. Adding it to a VM's `roles:` list in `new-config.yml` is the
  affirmative action — no internal `when` gate needed.
- **Three phases, all idempotent, delegated appropriately:**
  1. `microsoft.ad.user` creates the service account (delegated to
     `{{ ludus_dc_vm_name }}` so the DP does not need RSAT
     ActiveDirectory).
  2. `ansible.windows.win_group_membership` adds the service account
     to local `Administrators` on a configurable client host
     (delegated). This is the CRED-6 *payoff* — the looted cred
     actually opens a lateral-movement door. Default target is
     `ps1-dev` (a CM-enrolled client), chaining into CRED-1 /
     CRED-3 NAA cache extraction from that host.
  3. `ansible.windows.win_file` + `ansible.windows.win_template` +
     `ansible.windows.win_share` create the share + drop the file on
     the DP itself. Share is `Domain Users:Read` /
     `Administrators:Full`, matching the CRED-6 doc's
     authenticated-SMB example.
- **The `.ps1` is templated** so the credential embedded in it stays
  in sync with the AD user's password automatically. A
  `# TODO: move creds out of the script before rolling this to prod.
  (Ticket IT-4419)` comment sits at the top as the tell — it reads
  as an IT engineer's forgotten follow-up.
- **Payoff account is scoped to one client host, not domain-wide.**
  Least-privilege matches how a real IT-Ops service account
  would be scoped, and chains cleanly into further techniques
  without duplicating a domain-admin endgame that other TAKEOVER-*
  techniques already cover.
- **Password `Password123!` is intentional.** New lab-only string,
  safe to commit. The trailing `!` differentiates from the
  collection-wide `Password123` default — a student who copy-pastes
  carelessly hits an auth failure and knows the plant is precise.
- Full walkthrough with variable reference, wiring example, and
  student attack flow in `roles/create_dp_loot_share/README.md`.

## Test plan

- [x] Deployed to a live range: role runs end-to-end; AD account
  created, local-admin membership added on the payoff host, share
  visible via `Get-SmbShare Scripts`, file present in
  `C:\Scripts\Reset-SCCMClientCache.ps1`, ACLs are
  `MAYYHEM\Domain Users:Read` + `BUILTIN\Administrators:Full`.
- [x] Cred verified functional: `Invoke-Command -ComputerName ps1-dev
  -Credential svc_sccm_maint` returned `is_local_admin: true` and
  `whoami: MAYYHEM\svc_sccm_maint`, with `svc_sccm_maint` visible in
  ps1-dev's local Administrators group.
- [x] Re-ran the role: `changed=0`, confirmed idempotent.
- [ ] Reviewer to confirm it fits the collection's role conventions.

## Files touched

```
new-config.yml                                             |  10 ++
roles/create_dp_loot_share/README.md                       | 124 +++++++++++++++++++
roles/create_dp_loot_share/defaults/main.yml               |  23 ++++
roles/create_dp_loot_share/meta/main.yaml                  |  16 +++
roles/create_dp_loot_share/tasks/main.yml                  |  51 +++++++++
roles/create_dp_loot_share/templates/Reset-SCCMClientCache.ps1.j2 | 19 ++++
6 files changed, 243 insertions(+)
```

---

## GFM rendering notes

- All paragraph breaks are blank lines — safe.
- Bullet lists render one item per line automatically.
- Fenced code blocks (title, file-diff summary) render line-oriented.
- No trailing-space line breaks or `<br>` tricks used — nothing to lose
  if an editor strips whitespace.
