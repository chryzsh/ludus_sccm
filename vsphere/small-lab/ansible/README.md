# vSphere ansible bring-up for the slab (small always-on) lab

Runs the `mayyhem.ludus_sccm` collection against the 3 VMs provisioned by
`../terraform/`. Standalone primary, no hierarchy.

## Layout

- `ansible.cfg` — points at generated `inventory.yml`, WinRM defaults, YAML stdout.
- `sync_inventory.py` — regenerates `inventory.yml` from
  `../terraform/terraform.tfstate`. Read-only against state; safe to rerun.
  Inventory hostnames match the full VM names (slab-dc, slab-pss, slab-db).
- `inventory.yml` — **generated, gitignored** (contains real IPs).
- `group_vars/all/main.yml` — non-sensitive defaults (domain, cache path,
  DC hostname). Placeholder for the "latest SCCM" URL overrides (Phase 5).
- `group_vars/all/local.yml` — **local, gitignored, mode 0600.** Sensitive
  values: `ansible_password`, `defaults.ad_domain_admin*`. Auto-loaded
  alongside `main.yml`.
- `host_vars/{slab-pss,slab-db}/main.yml` — per-host role variables.
  slab-dc needs none.
- `run.sh` — wrapper around `ansible-playbook` that prepends RFC1918
  CIDRs to `NO_PROXY` so pywinrm doesn't route lab WinRM through a
  corporate outbound proxy.
- `00_..70_*.yml` — numbered phase playbooks; each individually runnable.
- `site.yml` — imports each phase in order.

## Prerequisites

1. **Terraform apply already done**, so `../terraform/terraform.tfstate`
   has the 3 slab VMs and their IPs.
2. **Collection installed.** Same install as the mayyhem lab — if you
   already have the symlink from `../ansible/README.md`'s Option A, it
   covers this lab too:
   ```bash
   mkdir -p ~/.ansible/collections/ansible_collections/mayyhem
   ln -sf "$(git rev-parse --show-toplevel)" \
       ~/.ansible/collections/ansible_collections/mayyhem/ludus_sccm
   ```
3. **WinRM deps**: `pip3 install pywinrm requests-ntlm` (once per Python env).
4. **`group_vars/all/local.yml`** exists with sensitive values. Already
   populated by the initial scaffolding.

## Usage

```bash
cd vsphere/small-lab/ansible
python3 sync_inventory.py                # (re)generate inventory.yml

# Connectivity first — do not skip.
./run.sh 00_connectivity.yml

# Then either the full spine:
./run.sh site.yml

# Or one phase at a time (recommended for first run):
./run.sh 05_ad_forest.yml
./run.sh 10_windows_base.yml
./run.sh 15_domain_join.yml
./run.sh 20_install_adcs.yml
./run.sh 30_prep_site_systems.yml   # long — pulls SCCM baseline + ADK
./run.sh 35_admin_plumbing.yml
./run.sh 40_install_database.yml    # long — SQL 2022 install
./run.sh 50_install_primary.yml     # longest — SCCM install (~1h)
./run.sh 70_verify.yml
```

## Phase 5 (SCCM baseline URL overrides) — deliberately deferred

Phase 30 (`prep_siteserver`) currently uses the collection's built-in
baseline URLs (2403). For "always on the LATEST SCCM," override the
three URLs in `group_vars/all/main.yml` — search for `PHASE 5` in that
file for the placeholder block. See `docs/small-latest-lab-plan.md`.

## Relationship to the mayyhem lab

Uses the same collection roles, same vCenter, same network. Isolated by:

- Different domain (slab.lab vs mayyhem.com).
- Different Windows computer names (slab-* vs mayyhem's dc/cas-*/ps1-*).
- Different SCCM site code (SLB vs PS1/CAS/SEC).
- Different controller-side download cache (`/tmp/slab-sccm-cache`).
- Different terraform state and folder in vCenter.

Both labs' VMs sit on the same L2 subnet, so any shared-subnet concerns
(NetBIOS name conflicts, PXE responders, DHCP scope) get addressed by
choosing distinct hostnames and disabling PXE in slab.
