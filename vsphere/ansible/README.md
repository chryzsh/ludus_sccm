# vSphere ansible bring-up

Runs the Mayyhem SCCM collection against the 13 VMs provisioned by `../terraform/`.

## Layout

- `ansible.cfg` — points at the generated `inventory.yml`, WinRM defaults, YAML stdout.
- `sync_inventory.py` — regenerates `inventory.yml` from `../terraform/terraform.tfstate`. Read-only against state; safe to rerun.
- `inventory.yml` — **generated, gitignored** (contains real IPs). Regenerate with `python3 sync_inventory.py`.
- `group_vars/all/main.yml` — non-sensitive defaults (domain, cache paths, DC hostname). Auto-loaded.
- `group_vars/all/local.yml` — **local, gitignored, mode 0600.** Sensitive values: `ansible_password`, `defaults.ad_domain_admin*`. Auto-loaded from the `all/` directory alongside `main.yml`.
- `run.sh` — wrapper around `ansible-playbook` that prepends RFC1918 CIDRs to `NO_PROXY` so pywinrm doesn't route lab WinRM through a corporate outbound proxy. Use this instead of calling `ansible-playbook` directly.
- `00_connectivity.yml` — WinRM ping against all hosts. Run first.
- `site.yml` — ordered spine; imports each numbered phase playbook. Phases beyond 00 are stubs pending §4 execution.

## Prerequisites

1. **Install the collection**, so `mayyhem.ludus_sccm.*` roles and plugin modules resolve. From the repo root:
   ```bash
   # Option A: symlink (best for iterative development on the collection)
   mkdir -p ~/.ansible/collections/ansible_collections/mayyhem
   ln -sf "$(pwd)" ~/.ansible/collections/ansible_collections/mayyhem/ludus_sccm

   # Option B: build + install (best for a stable snapshot)
   ansible-galaxy collection build --force
   ansible-galaxy collection install mayyhem-ludus_sccm-*.tar.gz --force
   ```

2. **WinRM pywinrm dependency**:
   ```bash
   pip3 install pywinrm requests-ntlm
   ```

3. **Terraform state present** (`../terraform/terraform.tfstate`) — this feeds the inventory sync.

4. **Populate `group_vars/all/local.yml`** with real credentials — the file was created with a `CHANGE_ME` placeholder for `defaults.ad_domain_admin_password`.

## Usage

```bash
cd vsphere/ansible
python3 sync_inventory.py                # (re)generate inventory.yml

# Connectivity first — do not skip this.
./run.sh 00_connectivity.yml --limit '!ps1-dev'

# Once phases are written:
# ./run.sh site.yml
# ./run.sh 10_windows_base.yml    # single phase
```

## Notes on ps1-dev

ps1-dev is in the inventory but not yet functional — the Windows 11 template's VMware Tools didn't respond during guest customization, so it has no IP. Use `--limit '!ps1-dev'` on all plays until the template is fixed and the resource is tainted + reapplied. See VSPHERE_PORT_PLAN.md "Known state / deferred items".

## Collection bugs found during bring-up

If a play surfaces a bug that lives in the collection itself (roles under `../../roles/`, plugin modules under `../../plugins/`), fix it as a separate commit that touches ONLY collection files — no `vsphere/` paths in the diff. That way the commit can be cherry-picked into an upstream PR against `Mayyhem/ludus_sccm` cleanly. Examples of that pattern: the four §2 commits on this branch (`74ed638`, `2c82885`, `281caf4`, `17f06d6`).
