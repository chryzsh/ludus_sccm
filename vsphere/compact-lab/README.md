# Compact SCCM workshop lab

A small, role-split SCCM lab for the attack workshop — the "navigable"
alternative to the 13-host mayyhem lab (post-workshop review, Proposal
A). Same attack surface, few enough hosts that a student can hold the
topology in their head.

> **Status: scaffold, not yet deployed.** Terraform + ansible are written
> and internally consistent, reusing the `mayyhem.ludus_sccm` collection
> and the mayyhem lab's plants, but this has **not** been `terraform
> apply`'d or run end to end. Treat like Proposal D was: deploy, then
> iterate/verify. See "Deploy" and "Open items" below.
>
> This is a **separate** lab from `vsphere/small-lab/` (slab), which is
> the owner's standalone latest-version vuln-discovery lab and is
> explicitly not a teaching lab.

## Hosts (5)

| Host | Roles (co-located) | Why |
|---|---|---|
| `cl-dc` | Domain controller + **ADCS** | AD + cert services (ESC/relay targets) |
| `cl-mecm` | Primary **site server** + **MP** + **SMS provider** | the SCCM brain; relay/coerce target (TAKEOVER-1) |
| `cl-sql` | Site **database** (MSSQL) | CRED-2 (policy/DB secrets), linked-server surface |
| `cl-dp` | **Distribution point** + **PXE** | CRED-6 loot share; PXE/OSD surface |
| `cl-client` | Win11, **CM-enrolled** client | CRED-1 (NAA policy), coercion source, EXEC-2 target |

Naming uses a `cl-` prefix (compact-lab) so nothing collides with the
mayyhem (`ps1-`/`cas-`) or slab (`slab-`) hosts in the same vCenter.

## Attack coverage — what delivers each technique

Most techniques fall out of the **base `install_primary_site`** config;
only CRED-6 and EXEC-2 need explicit plants.

| Technique | How it's present | Source |
|---|---|---|
| **CRED-1** (NAA policy) | NAA configured (`config_naa`); readable from the enrolled client | base install (`ludus_sccm_configure_naa: true`) |
| **CRED-2** (policy/DB secrets) | site DB on `cl-sql` + NAA/collection-var policy secrets | inherent to a working site |
| **CRED-6** (loot a DP share) | `Scripts` share on `cl-dp` with `svc_sccm_maint` creds in a script; account is local admin on `cl-client` | `create_dp_loot_share` role |
| **EXEC-2** (script approver) | `Script Approvers` role granted to `svc_sccm_maint` (Proposal D), with the AD-description breadcrumb | `misc_grant_svc_maint_script_approver.yml` |
| **ELEVATE-1** (client-push acct local admin) | `sccm_push` in `sccm_push_accounts`, GPO grants local admin on `OU=Servers` | base install `client_push.yml` GPO |
| **TAKEOVER-1** (relay coerced auth → site server) | SMB signing **not enforced** on `cl-mecm`; `cl-client` coercible (CcmExec/PetitPotam) | base config (leave signing off) |

(ELEVATE-2 — machine-account fallback when push accounts fail — is
inherent behaviour, same as the mayyhem lab.)

## Layout

```
compact-lab/
  terraform/   # 5-host vm_config; copy of the mayyhem module, new prefix/folder
  ansible/     # group_vars enable the plants; host_vars co-locate roles; site.yml
```

## Deploy (once tfvars are filled in)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # fill in vCenter/creds/IPs
terraform init && terraform plan -out=up.tfplan   # REVIEW: 5 VMs created, nothing else
terraform apply up.tfplan
cd ../ansible
python3 sync_inventory.py          # inventory from tfstate
./run.sh site.yml                  # full build + plants
```

## Open items (the deploy-iterate pass)

- Not applied — GOSC (guest customization) timing, template names, and IP
  map are env-specific; expect the usual customize-timeout dance on first
  apply (see AGENTS.md).
- `site.yml` sequences the collection roles + plants for the co-located
  hosts, but role co-location on `cl-mecm` (primary+MP+provider on one
  box) needs a real run to shake out (the mayyhem lab splits these).
- CRED-6 / EXEC-2 plant playbooks target `cl-dp` / `cl-mecm` here; confirm
  host names line up after inventory generation.
- Verify each technique post-deploy using `docs/cred6-exec2-test-handover.md`
  (private ops repo) as the model.
