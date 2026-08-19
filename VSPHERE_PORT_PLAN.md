# ludus_sccm_mayyhem → vSphere port + second-primary answer

Public plan for a vSphere provider path alongside the existing Ludus/Proxmox collection. All target-environment specifics (vCenter server, datacenter, cluster, datastore, port-group / VLAN name, IP ranges, gateway, folder paths, credentials) live in the operator's local `ENVIRONMENT.local.md` (gitignored) and in an out-of-tree `~/.mayyhem-sccm/vsphere.tfvars` (also gitignored). See `AGENTS.md` for the full secrets policy.

Reference pattern: a working vSphere port already exists for the `GOAD` (Game of Active Directory) lab; that provider's shape is what this port mirrors.

Upstream: https://github.com/Mayyhem/ludus_sccm
Related blog: https://specterops.io/blog/2026/04/01/ludus-sccm-lab-expansion/

## 0. Baseline reality check

- The Ludus/Proxmox-native collection here is provider-agnostic in its Ansible roles and PowerShell plugins. The Ludus coupling is a handful of variables and a range-config DAG.
- The lab as shipped is 13 VMs across two Ludus VLANs (CAS tier + PS1 tier), site codes `CAS` / `PS1` / `SEC`, domain `mayyhem.com`.
- CAS is built by *extending* PS1 (the `install_primary_site` role runs on `cas-pss` with `ExtendPrimaryToCAS.ini.j2` and `Action=InstallCAS`), not stood up independently.

## 1. Port strategy — mirror the GOAD pattern, keep the Ansible collection intact

The Ansible collection (roles, plugins, templates) is largely provider-agnostic. Do not rewrite it.

### 1.1 What has to be replaced

| Ludus artifact | Replacement |
|---|---|
| `new-config.yml` (range config with `ludus:` DAG) | Terraform module + a plain Ansible playbook that mirrors the `depends_on` ordering. |
| Ludus/Proxmox template names | vSphere template names via variables (see local plan). |
| `ludus_install_directory: /opt/ludus` (controller-side cache) | Controller-agnostic download cache path (group_var). |
| `ludus_iso_path: "/var/lib/vz/template/iso"` (Proxmox path, used in `config_pxe.yaml:26`) | vSphere-appropriate ISO source or WinPE build path. |
| `ludus_dc_vm_name` used as `delegate_to` in 4 roles | Inventory hostname of DC in the vSphere inventory. |
| `ludus_domain_netbios_name` / `ludus_domain_fqdn` | group_vars in the vSphere inventory. |
| `defaults.ad_domain_admin` / `defaults.ad_domain_admin_password` map | group_vars in the vSphere inventory. |
| `range_id`-templated VM names | Terraform locals / per-run prefix. |

### 1.2 Directory layout

```
ludus_sccm_mayyhem/
├── (existing collection, untouched)
└── vsphere/
    ├── terraform/
    │   ├── main.tf              # provider block + data sources
    │   ├── variables.tf         # vsphere_* connection vars (no defaults with real values)
    │   ├── vms.tf               # for_each over locals.vm_config
    │   ├── locals.tf            # 13-VM map: name, hostname, ip, netmask, gw, cpu, mem, disk, template
    │   ├── networks.tf          # port-group data source (name comes from tfvars, never committed)
    │   └── terraform.tfvars.example  # placeholder values only
    ├── ansible/
    │   ├── inventory.yml.template   # committed template; generated variant is gitignored
    │   ├── group_vars/all.yml       # replaces Ludus defaults (domain, admin, netbios, cache paths)
    │   ├── site.yml                 # ordered plays matching new-config.yml DAG
    │   └── sync_inventory.py        # tfstate → inventory (mirrors GOAD's provider glue)
    └── README.md
```

### 1.3 Network layout — flat single subnet (decided)

All 13 VMs share one flat port group on a `/22`. Ludus's two-VLAN split (CAS tier vs PS1 tier) is collapsed. No router VM.

**Consequences of collapsing to one subnet:**

- **Assignment boundaries can't be subnet-based** (both sites would see identical subnets). Use IP-range boundaries carved from the flat subnet — one range per site. The hardcoded boundary-group name bug (§2.1) MUST be fixed before adding a second primary or the second site would stomp the first site's boundary group.
- **Two PXE responders race in one broadcast domain.** `ludus_sccm_enable_pxe` defaults to true; both `ps1-dp` and any future `ps2-dp` would answer PXE requests. Recommend: keep PXE enabled on one DP only via role_vars (`ludus_sccm_enable_pxe: false` on the others). If PXE testing is a lab goal, only enable it on the DP under test at any given time.
- **No segmentation story.** The Ludus VLAN split provided rudimentary segmentation; that's gone. Fine for functional testing; call it out if this lab feeds detection-engineering exercises that assume segmentation.

### 1.4 Windows templates

Two vSphere templates are required in the target vCenter: a Windows Server template and a Windows 11 template. Server version should match Mayyhem upstream (Server 2022) — the collection installs SCCM 2303, which pre-dates Server 2025 and does not list it as a supported site-system OS. Bumping to a later Server release would also mean bumping SCCM baseline, which is a larger deviation than this port intends. Exact template names live in the operator's tfvars, not in this file. Templates must have VMware Tools installed, WinRM enabled (HTTP/5985, NTLM), a known local Administrator password, and a guest customization spec ready. No Packer work needed if the templates already exist.

## 2. Fixes to make in the collection regardless of provider

These bugs exist in upstream too. Fixing them is provider-agnostic and should be the first commits — cherry-pickable as an upstream PR.

### 2.1 `discovery_methods.yml` hardcoded boundary group name

`roles/install_primary_site/tasks/discovery_methods.yml:27` — `boundary_group_name: "Discovery Default Boundary Group"`.
Change to per-site: `boundary_group_name: "Discovery Default Boundary Group - {{ ludus_sccm_sitecode }}"` (or similar). Required before any second primary site can exist without stomping the first site's boundary group.

### 2.2 `create_boundary_group.ps1` unconditional writes

`plugins/modules/create_boundary_group.ps1:35` — `Set-CMBoundaryGroup -DefaultSiteCode` runs every call. Line 43 — `Add-CMBoundaryToGroup` runs every call. Wrap both in idempotency checks and add a check-mode guard.

### 2.3 `ExtendPrimaryToCAS.ini.j2` issues

`roles/prep_siteserver/templates/ExtendPrimaryToCAS.ini.j2`:
- Line 3: remove `CDLatest=1` (lab runs from `cd.retail.LN`, not a CD.Latest source).
- Line 29: strip trailing space after `CCARSiteServer=…`.
- Verify `JoinPrimarySiteName` should be an FQDN vs a site name — capture from the wizard autosave (see §3.3) before deciding.

### 2.4 Dead template

`CASConfigMgrSetup.ini.j2` is never referenced by `new-config.yml`. Either delete it or wire it up. Leaving it around is misleading.

## 3. Second child primary of CAS (PS2) — answering the maintainer's question

### 3.1 VLAN answer

Not strictly required. Two primaries doing boundary-based site assignment need non-overlapping assignment boundaries. Options in order of tidiness:

1. **Distinct port group / VLAN per primary** with IP subnet boundaries — cleanest in a segmented environment; not available in the flat-subnet target used here.
2. **IP address range boundaries** carving one flat subnet — the approach for this port.
3. AD site boundaries (still needs distinct subnets underneath).
4. `SMSSITECODE` client push property per collection — bypasses boundaries entirely.

### 3.2 Feasibility

Yes. `ParentSiteCode` / `ParentSiteServer` in `[Options]` is the documented path for installing a child primary. Maintainer's placement is correct; his install isn't producing a hierarchy join.

### 3.3 How to get the definitive answer file (the missing piece)

Setup itself generates the answer file: run the GUI wizard to the summary page and setup writes the config to `%TEMP%\ConfigMgrAutoSave.ini`. This is the artifact missing from every blog post on this topic.

Procedure:

1. Bring up CAS + PS1 to a working state.
2. Snapshot everything.
3. Drop a fresh Windows Server VM in as `ps2-pss`.
4. Run `setupwpf.exe` interactively.
5. Choose "Primary site" and point it at the CAS FQDN.
6. Advance to the summary page. Cancel the wizard (do not install).
7. Copy `%TEMP%\ConfigMgrAutoSave.ini` off the VM.
8. Diff it against `ChildSiteConfigMgrSetup.ini.j2`. Every delta is a candidate fix.
9. Update the template, rebuild, run headless.

This is the deliverable to send the maintainer — an autosave ini from a topology matching his own.

### 3.4 Candidate template edits to try before / while §3.3 is pending

Based on documentation review; the autosave is authoritative:

- Drop the single quotes on FQDN values (the child-primary install path is stricter than standalone).
- Add `MobileDeviceLanguage=0` to `[Options]`.
- Add `[SABranchOptions]` with `SAActive=1` and `CurrentBranch=1`.
- Add `[HierarchyExpansionOption]` with `CASRetryInterval=1` and `WaitForCASTimeout=60`.
- Keep `CloudConnector=0` (SCP is CAS-only in a hierarchy).

### 3.5 Ansible / range changes to add PS2

- New VM block for `ps2-pss`, `ps2-db`, `ps2-dp`, `ps2-mp` (optionally passive/secondary).
- `role_vars` on `ps2-pss`: `ludus_sccm_sitecode: PS2`, `ludus_sccm_parent_sitecode: CAS`, `ludus_sccm_win_sccm_config_default_template: ChildSiteConfigMgrSetup.ini.j2`.
- `depends_on`: PS2's `install_primary_site` must wait on CAS-PSS `install_primary_site`. Fix §2.1 and §2.2 first.
- Extend reciprocal local-admin grants (`ps2-pss$` on `cas-pss` and vice versa).

## 4. Sequenced work plan

1. **Confirm vSphere targets** — cluster, datastore, templates, port-group name, IP range. All values stay in the local plan + tfvars.
2. **Fix collection bugs (§2)** — boundary-group hardcoding, PowerShell idempotency, `ExtendPrimaryToCAS` whitespace/CDLatest, delete dead CAS template. Commit before any vSphere work — provider-agnostic and PR-clean.
3. **Scaffold `vsphere/terraform/`** — copy the shape of the GOAD vSphere provider, translate the 13 VMs from `new-config.yml` into `locals.tf`, wire up the one port group. **All real values in tfvars, none in committed .tf files.**
4. **tfstate → inventory sync** — small Python script that reads terraform state and emits an Ansible inventory YAML.
5. **`group_vars/all.yml`** — populate `ludus_domain_fqdn`, `ludus_domain_netbios_name`, `defaults.ad_domain_admin*`, `ludus_install_directory`, `ludus_iso_path`, and any other `ludus_*` vars grep'd from the collection.
6. **Write `site.yml`** — one playbook whose play ordering mirrors the `depends_on` edges from `new-config.yml`.
7. **First end-to-end run — standalone PS1** — trim `site.yml` down to DC + PS1 tier only, verify the collection completes against vSphere.
8. **Add CAS extension** — extend `site.yml` to the CAS tier, run again.
9. **Snapshot everything.**
10. **Second-primary experiment (§3.3)** — capture the wizard autosave ini from a fresh PS2 VM pointed at CAS. Diff, update the template, retry headless.
11. **Add PS2 to the layout** — new VMs, `depends_on: cas-pss install_primary_site`, boundary-group fix in place, IP-range boundary configured.
12. **Report findings back to upstream** — the autosave ini and the corrected template are the actual answer to the maintainer's question.

## 5. Open questions

All resolved. Details captured in the local plan.

## 6. Fork hygiene and secrets handling

### 6.1 Remotes

Working from a personal fork; `origin` points at the fork, `upstream` at the original repository. Working branch: `feat/vsphere-port`. `main` stays clean and mergeable with `upstream/main` for future rebases.

### 6.2 Secrets policy (summary — full policy in AGENTS.md)

- No target-environment specifics may be committed to this fork: vCenter server, credentials, VLAN / port-group name, datacenter / cluster / datastore names, folder paths, real IPs / gateways / subnets, or operator-owned domain names.
- Real values live in `~/.mayyhem-sccm/vsphere.tfvars` (external) and in `ENVIRONMENT.local.md` (gitignored).
- Committed files use `variable`s with no defaults, or placeholder examples (`vcenter.example`, RFC1918 documentation blocks).
- `.gitignore` blocks `*.tfvars`, `terraform.tfstate*`, `.terraform*`, generated inventories, and the local plan.
- Pre-push scan (see `AGENTS.md`) is mandatory.
