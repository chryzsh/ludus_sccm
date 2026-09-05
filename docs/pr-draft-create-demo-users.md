# PR draft — Add `create_demo_users` role

Ready-to-open pull request against **`Mayyhem/ludus_sccm`**. Copy-paste
the title and body below into GitHub's PR form. Both are written with
GFM in mind — paragraph breaks are blank lines so they render right.

## Where to open it

- **Base:** `Mayyhem/ludus_sccm:main`
- **Head:** `chryzsh:feat/demo-user`
- **Direct link:** <https://github.com/Mayyhem/ludus_sccm/compare/main...chryzsh:ludus_sccm:feat/demo-user>

The head branch is already on `origin` as a single clean commit
(`3068399`) on top of `main` — nothing further to push before opening.

## Title

```
Add create_demo_users role for low-priv RDP demo access
```

## Body

---

## Summary

- New `create_demo_users` role: creates one or more regular domain user
  accounts, adds them to **Remote Desktop Users** on the assigned host,
  and optionally to local **Administrators**.
- Wired into `new-config.yml` on `ps1-dev` so every deploy gets
  `domainuser` (a plain domain account) and `helpdesk` (also gets local
  admin — a realistic "support account with local admin"
  misconfiguration).

## Why

Every VM in the lab autologs on as the range-wide domain admin
(`windows_base`'s AutoAdminLogon), which leaves no low-privileged
persona to demo from — no non-admin to RDP in as, no realistic
support-account-with-local-admin scenario, no non-DA target for
kerberoast/coerce exercises. This role fills that gap without changing
anything about the hierarchy itself.

## Design

- **AD account creation is delegated to `{{ ludus_dc_vm_name }}`**, so
  the assigned host does not need RSAT ActiveDirectory installed.
- **Idempotent** — every mutation is guarded; re-runs are no-ops.
- **Variable-driven** via `ludus_sccm_demo_users`, a list of
  `{ username, password, local_admin }` entries. Defaults are
  `domainuser` (no admin) and `helpdesk` (local admin), both
  `Password123` to match other collection defaults.
- Full walkthrough with usage snippets in
  `roles/create_demo_users/README.md`.

## Test plan

- [x] Deployed in a lab: both accounts created in AD, `helpdesk` shows
  up in `net localgroup Administrators` on `ps1-dev`, both in Remote
  Desktop Users, RDP works interactively as each.
- [x] Re-ran the role: `changed=0`, confirmed idempotent.
- [ ] Reviewer to confirm it fits the collection's role conventions.

## Files touched

```
new-config.yml                            |  7 ++++
roles/create_demo_users/README.md         | 56 +++++++++++++++++++++++++++++
roles/create_demo_users/defaults/main.yml | 14 ++++++++
roles/create_demo_users/meta/main.yaml    | 20 +++++++++++
roles/create_demo_users/tasks/main.yml    | 58 +++++++++++++++++++++++++++++++
5 files changed, 155 insertions(+)
```

---

## GFM rendering notes

- All paragraph breaks are blank lines — safe.
- Bullet lists render one item per line automatically.
- Fenced code blocks (title, file-diff summary) render line-oriented.
- No trailing-space line breaks or `<br>` tricks used — nothing to lose
  if an editor strips whitespace.
