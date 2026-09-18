# Compact lab — ansible

Builds the 5-host compact lab (see `../README.md` for the design and
host/technique map). Reuses the `mayyhem.ludus_sccm` collection and the
mayyhem/slab playbooks; the vulnerable behaviour is driven by
`group_vars/all/main.yml`.

## Invoke

Always via `./run.sh` (proxy-safe; dispatches `.yml` → ansible-playbook,
`-m/-a` → ansible). Regenerate the inventory after any terraform change:

```bash
python3 sync_inventory.py        # inventory.yml from ../terraform/terraform.tfstate
./run.sh site.yml
```

Create `group_vars/all/local.yml` (gitignored, mode 0600) with the
secrets before running — copy the mayyhem lab's and adjust:

```yaml
ansible_password: <local Administrator / WinRM password>
defaults:
  ad_domain_admin: domainadmin
  ad_domain_admin_password: <domain admin password>
```

## Prerequisites — plant files must be on this branch

`site.yml` references plants that live on separate feature branches. For
a real build, assemble an integration branch that has all of:

- this `feat/compact-lab` (compact terraform + ansible + group_vars)
- `feat/create-dp-loot-share` — the `create_dp_loot_share` role (CRED-6)
- `feat/exec-2-svc-maint` — `misc_grant_svc_maint_script_approver.yml`
  + the `create_script_approver_role` / `add_administrative_user`
  modules (EXEC-2, Proposal D)

Merging cleanly (they sit on different bases) is itself part of the
deploy-prep; do it on an integration branch and test, don't force it.

## Building the pipeline

This branch ships `group_vars`, `host_vars`, `run.sh`, `ansible.cfg`,
`sync_inventory.py`, and a `site.yml` **skeleton**. The numbered phase
playbooks (`00_connectivity` … `70_verify`, plus `52_install_dp` /
`54_enroll_client`) are the slab/mayyhem pipeline and must be copied in
and re-targeted for the compact hosts:

| Compact host | Takes the role(s) the mayyhem/slab playbook applied to |
|---|---|
| cl-dc | slab-dc / dc (AD promote, ADCS) |
| cl-mecm | ps1-pss **+** ps1-mp **+** ps1-sms (primary + MP + provider) |
| cl-sql | ps1-db / slab-db (SQL + add_pss_to_admins) |
| cl-dp | ps1-dp (DP + PXE) — see mayyhem's DP install |
| cl-client | ps1-dev (CM client via push) |

The one genuinely new thing vs. slab is **role co-location on cl-mecm**
(primary+MP+provider on one host) and adding the **DP** on cl-dp — both
are supported by the collection but the mayyhem lab spreads them, so the
first deploy needs a verify pass.

## After deploy — verify the attack paths

Confirm each technique lands, using the private ops repo's
`docs/cred6-exec2-test-handover.md` as the model:

- CRED-1: read NAA policy from cl-client (SharpSCCM `local naa`).
- CRED-2: policy/DB secrets reachable.
- CRED-6: loot `\\cl-dp\Scripts` → `svc_sccm_maint`; local admin on cl-client.
- EXEC-2: `svc_sccm_maint` holds Script Approvers; approve→run cycle.
- ELEVATE-1: `sccm_push` local admin on the servers (GPO).
- TAKEOVER-1: coerce cl-client → relay to cl-mecm (SMB signing off).
