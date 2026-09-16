# Small always-on SCCM lab (`slab`) — plan + as-built

A minimal, always-on SCCM lab that lives alongside the existing mayyhem lab in
the same shared vCenter. Own domain, own vSphere folder, own IP block, own
Ansible inventory. Reuses the existing `mayyhem.ludus_sccm` Ansible collection
roles unchanged. Intended for security-research work against a current-baseline
SCCM install without disturbing (or being disturbed by) the big hierarchy lab.

## As-built (2026-09-09)

Lab is up and verified. Everything below in the "Plan" section captures the
original design and exploratory decisions — kept for context. This section is
the authoritative record of what actually shipped.

- 3 VMs: `slab-dc` (192.0.2.117), `slab-pss` (192.0.2.118), `slab-db`
  (192.0.2.119). All Server 2022. vSphere folder
  `Personal/example/sccm-lab-slab`.
- Domain `slab.lab` / NetBIOS `SLAB` / site code `SLB`. `SLAB\domainadmin`
  is Domain Admin + Enterprise Admin + Schema Admin.
- Terraform on branch `feat/small-latest-lab` under
  `vsphere/small-lab/terraform/`. State is local, gitignored.
- Ansible under `vsphere/small-lab/ansible/`. All 8 playbooks (00→70)
  succeeded. Standalone primary, MP+DP+SMS provider colocated on
  `slab-pss`. No PXE (avoids being a rogue responder on the shared
  subnet with mayyhem's DP).
- SCCM baseline installed: **2403** (collection default).
- SCCM upgraded to **2509** in-place on 2026-09-10 via `60_upgrade_sccm.yml`
  (see the "First in-place upgrade" section below). Site build now 9141.

### Disk-space blocker — Server 2022 template + terraform grow (fix: phase 11)

vSphere honours terraform's `disk.size` values (200 GB on slab-pss, 100 GB
on slab-db, 80 GB on slab-dc) so the VMDK arrives at the right size, but
the Windows Server 2022 template only formats its original ~60 GB C:
partition. Everything beyond that sits unallocated at the end of disk 0
until someone runs `Resize-Partition`.

SCCM's setup prereq check hard-fails with `"site server must have at
least 15GB free"` once one 2509-sized pack downloads plus the CMUStaging
folder — with a 60 GB C: partition and a full standalone-primary
install already resident, free space drops below 15 GB. Empirically
observed 2026-09-10: `Install-CMSiteUpdate 2509` staged 3 GB in
`C:\Program Files\Microsoft Configuration Manager\CMUStaging\{GUID}\`,
prereq check ran, failed on disk-space, `SMS_CM_UpdatePackages.State`
went to `196607` (`PrereqFlag=2`, `WarningFlag=1`), engine parked.
No amount of nudging (restart of `CONFIGURATION_MANAGER_UPDATE` service
or re-firing `Install-CMSiteUpdate`) will help — SCCM won't proceed
until prereq passes.

Fix (permanent): playbook `11_grow_partitions.yml` runs
`Resize-Partition -DriveLetter C -Size (Get-PartitionSupportedSize
-DriveLetter C).SizeMax` on all hosts. Live, no reboot, idempotent
(no-op when C: already covers the whole disk). Placed in the spine
between `10_windows_base` and `15_domain_join`; runs on every fresh
deploy so the disk is right by the time SCCM is ever installed.

### First in-place upgrade (2403 → 2509)

Timeline observed on 2026-09-10 after fixing the disk-space blocker:

```
11:05  poll 1  state 65538  = Downloading
11:10  poll 2  state 131075 = Downloaded
11:15  poll 3  state 196609 = Installing (steady)
...    (21 min of Installing)
11:41  poll 8  siteVersion = 5.00.9141.1000  → DONE
```

Total wall-clock: 36 minutes. Empirical `SMS_CM_UpdatePackages.State`
codes are captured in the label table in `60_upgrade_sccm.yml`; use
that to interpret the `-e slab_upgrade_dry_run=true` output.

### 2603 upgrade attempt — stuck at Downloaded, deferred (2026-09-10)

Second in-place upgrade attempt (2509 → 2603) got the pack downloaded
and prereq-checked, but hman refused with "site server reporting
WARNING in prereq check. Setup will not continue." Warnings were the
usual ConfigMgrPrereq.log advisories that 2509 tolerated but 2603 does
not:

- SQL Server Native Client version (slab-pss)
- SQL Server minimum memory (slab-db, 2048 MB → recommended 8 GB)
- SQL Server security mode (Mixed vs Windows-only — advisory only)
- NAA account usage alert (deprecated on HTTPS/Enhanced HTTP sites)

Applied the two easy fixes:
- Installed MSOLEDBSQL19 v19.4.2.0 on slab-pss via chocolatey (the
  registry key SCCM's prereq check probes for).
- `sp_configure 'min server memory (MB)', 8192; RECONFIGURE;` on
  slab-db.

Fixes stuck. But re-firing `Install-CMSiteUpdate "Configuration
Manager 2603"` after the fixes (with `-Force -IgnorePrereqWarning
-SkipPrerequisiteCheck` — even with all three flags) produced ZERO
CMUpdate or hman activity: empty inbox, quiet hman (only routine
HSMonitoring), state stayed at 131075 (Downloaded). Reads like
SCCM's state machine considers the pack "install request already
handled" and cmdlet re-fires no-op.

Not solved. Options to actually finish 2603:

1. **RDP to slab-pss, right-click 2603 in the console → Install Update
   Pack**. SCCM console has state-reset paths PowerShell doesn't
   expose. Least risk.
2. Undocumented SMS_CM_UpdatePackages WMI method invocation to force
   a state reset. Risky, may corrupt the pack.
3. Wait for a newer baseline to supersede 2603 (SCCM ships new
   baselines every ~6 months); the state machine resets when a
   superseding pack arrives.

Deferred to option 3 for now — slab is fully functional on 2509 and
the 2603 upgrade isn't blocking any research work. Improvements from
this attempt that DID land in 60_upgrade_sccm.yml:

- `-IgnorePrereqWarning` on `Install-CMSiteUpdate` (variable
  `slab_upgrade_ignore_prereq_warning`, default true). Would have
  worked for 2509-style warning tolerance — didn't help 2603 because
  the retry never got issued to CMUpdate.
- Poll task hardened with `failed_when: false` alongside
  `ignore_unreachable: true` — mid-install WinRM HTTP 400 blips no
  longer kill the play.

### AdminConsole SiteVersionMismatch (fix: 60_upgrade_sccm.yml
### post-install task)

`Install-CMSiteUpdate` upgrades the site database + site components
but does NOT upgrade the ConfigMgr AdminConsole binaries on the site
server itself. Launching the console interactively detects the
mismatch and offers to auto-upgrade; PowerShell automation via
`New-PSDrive -PSProvider CMSite` gets a `SiteVersionMismatch` error
with no prompt to click, and every subsequent CM cmdlet fails.

Post-2509 upgrade on slab-pss, this manifested as:
    Console EXE: 5.2403.x
    Site       : 5.00.9141.1000 (2509)
    New-PSDrive: `SiteVersionMismatch`

Fix: run the on-disk `ConsoleSetup.exe /q` that the site upgrade
staged at
`C:\Program Files\Microsoft Configuration Manager\tools\ConsoleSetup\ConsoleSetup.exe`.
Fast (~30 s), silent, upgrades the console to match the site. The
2509 console version we landed on was `5.2509.1038.1000`. New-PSDrive
worked immediately afterward.

Baked into `60_upgrade_sccm.yml` as a post-install task (after
SMS_Executive restart, before the "Report new site version" step).
Followed by an assertion that `New-PSDrive` connects cleanly, so
any future upgrade that leaves the console mismatched fails loudly
instead of silently breaking every downstream CM cmdlet run.

### Windows guest-customization taints (harmless)

Terraform's first `apply` reported `Virtual machine customization failed:
timeout waiting for customization to complete` for all 3 VMs. Guest
customization actually succeeded — vSphere just didn't emit the
completion signal within terraform's 10-min poll. Same failure mode
`VSPHERE_PORT_PLAN.md` flags for Linux GOSC.

Recovery pattern: verify with `./run.sh 00_connectivity.yml`, then
`terraform untaint 'vsphere_virtual_machine.slab_vm["<key>"]'` for each
of `dc`, `pss`, `db`. Never re-apply on the taint — it would destroy the
working VMs. Do not touch `customize.timeout` (it's ForceNew, would mass-
recreate).

### NetBIOS collision fix

`vms.tf` sets Windows `computer_name = "${var.lab_prefix}-${each.value.hostname}"`
so slab's DC becomes `slab-dc` on the wire, not `dc`. Necessary because
mayyhem's DC already uses NetBIOS name `DC` on the shared L2 subnet.
The mayyhem terraform uses the bare hostname; slab's terraform diverges
on this line only.

### The "latest SCCM" attempt that didn't work

Original plan called for overriding `configmgr_url` / `adksetup_url` /
`adkwinpesetup_url` in slab's group_vars to the newest baseline. Tried
2509 — the newest EXE on Microsoft's eval center as of 2026-09-09.

Result: **the SCCM 2509 self-extractor hangs indefinitely** when driven
with the `/s -dPATH` silent syntax the collection uses. Process runs
with zero CPU, no window (`MainWindowHandle=0`), never writes files.
Killed after 81 minutes. Root cause: Microsoft does not publicly
document silent-extract flags for the SCCM baseline self-extractor —
the `/s` convention was Wise/InstallShield-SFX behavior that empirically
worked for 2303/2403 but no longer parses in 2509. Microsoft also frames
2509 as an in-console update pack applied on top of 2403+, not a fresh
baseline.

Fallback (what shipped): no URL overrides in `group_vars/all/main.yml`
— the collection's 2403 defaults win. Rationale documented inline in
that file (search for "Latest SCCM plumbing"). Do not re-attempt
overriding to 2509+ without first solving the silent-extract problem
(likely path: install 7-Zip via chocolatey on slab-pss, extract with
`7z x ...`, and patch the collection's hardcoded `cd.retail.LN`
references to the actual 2509 top-level folder).

### Update path to "latest"

Two ways, use whichever fits:

**Automated** (one-shot, installs one update per run — re-run to walk
a chain):
```
cd vsphere/small-lab/ansible
./run.sh 60_upgrade_sccm.yml -e slab_upgrade_dry_run=true   # list what's available
./run.sh 60_upgrade_sccm.yml                                # install the newest available
```
First run needs Microsoft's metadata sync to complete (hours-to-days after
the site is first up — `dmpdownloader` fetches from the CMUdatafeed cloud
service). Subsequent runs are fast because the local catalog stays warm.
See the playbook header for options.

**Manual**, from the SCCM console on `slab-pss` (RDP as `SLAB\domainadmin`):

1. `Administration → Overview → Updates and Servicing`.
2. Install the newest update pack.
3. Reboot if prompted.

## Scope

- 3 VMs, all Windows Server 2022:
  - `slab-dc` — Active Directory Domain Services + ADCS (for consistency with
    upstream, and because ELEVATE-* techniques care about it).
  - `slab-pss` — SCCM primary site server, with MP + DP + SMS Provider
    **colocated** on the same host.
  - `slab-db` — dedicated SQL Server 2022 for the site database.
- Site code: `SLB`. Domain: `slab.lab`. NetBIOS: `SLAB`.
- Flat, single subnet — same port group as mayyhem. IPs:
  - `slab-dc`  → `192.0.2.117`
  - `slab-pss` → `192.0.2.118`
  - `slab-db`  → `192.0.2.119`
- Always on. No revert automation, no snapshot policy, no scheduled teardown.
- Latest SCCM current-branch baseline at deploy time. Subsequent updates via
  in-place upgrade from the SCCM console (`Administration → Updates and
  Servicing`). No auto-upgrade automation.

## What this lab is NOT

- **Not** in the same AD forest as mayyhem. `mayyhem.com` stays untouched. If
  cross-forest attack scenarios become interesting later, revisit.
- **Not** a hierarchy. No CAS, no secondary, no passive site server. If a
  hierarchy is needed, use the mayyhem lab.
- **Not** running PXE. Only one DP, no PXE testing goal, avoids a rogue PXE
  responder on the shared subnet.

## Repo layout

Sibling to the existing vSphere port. New tree:

```
vsphere/small-lab/
├── terraform/
│   ├── main.tf              # provider block, tfvars connection details
│   ├── variables.tf         # vsphere_* connection vars, no real defaults
│   ├── locals.tf            # 3-VM map (name, hostname, ip, cpu, mem, disk, template)
│   ├── vms.tf               # for_each over locals.vm_config
│   ├── networks.tf          # port-group data source
│   ├── README.md
│   └── terraform.tfvars.example
└── ansible/
    ├── ansible.cfg
    ├── inventory.yml.template
    ├── group_vars/all/main.yml
    ├── host_vars/{slab-dc,slab-pss,slab-db}/main.yml
    ├── sync_inventory.py    # copy of the working one from vsphere/ansible/
    ├── 00_connectivity.yml
    ├── 05_ad_forest.yml
    ├── 10_windows_base.yml
    ├── 15_domain_join.yml
    ├── 20_install_adcs.yml
    ├── 30_prep_site_systems.yml
    ├── 35_admin_plumbing.yml
    ├── 40_install_database.yml
    ├── 50_install_primary.yml
    ├── 70_verify.yml
    └── site.yml
```

Reasons for a sibling tree instead of parameterizing the existing one:

- The mayyhem terraform uses `locals.vm_config` with 13 entries; adding a
  profile toggle to swap between 13-VM and 3-VM shapes makes the existing
  module harder to reason about for the primary use case.
- Distinct `terraform state` per lab means an accidental `terraform destroy`
  in one directory cannot touch the other lab's VMs. Given the shared-vCenter
  rules in `AGENTS.md`, this is a safety property worth paying a bit of
  duplication for.
- Ansible inventory and per-host vars are lab-specific either way; sharing
  playbooks that dispatch on inventory groups saves less than it costs in
  indirection.

The Ansible **roles** (`mayyhem.ludus_sccm.*`) are shared unchanged. Only the
`vsphere/small-lab/ansible/` orchestration files are new.

## VM safety in shared vCenter

- Terraform `lab_prefix` = `slab`. Every VM name is `slab-*`. Cannot collide
  with mayyhem's `mm-*` (or whatever range_id prefix that lab uses).
- vSphere folder: `slab-lab` (or whatever the operator's `ENVIRONMENT.local.md`
  specifies for this lab). Distinct from the mayyhem folder.
- Terraform state file kept separate from the mayyhem one.
- Same rules apply as in root `AGENTS.md`: `for_each` only, never `count`;
  never `data "vsphere_virtual_machine"` against live VMs; `terraform plan
  -out=<file>` before every apply; stop on any `will be destroyed` or `-/+
  must be replaced` line.

## "Latest SCCM" plumbing

The collection currently pins the SCCM 2303 baseline via three defaults in
`roles/prep_siteserver/defaults/main.yml` (or wherever `configmgr_url`,
`adksetup_url`, `adkwinpesetup_url` are set — verify at implementation time):

- `configmgr_url` — MS download URL for the baseline `.exe` self-extractor.
- `configmgr_filename` — hardcoded as `MCM_Configmgr_2303.exe` in
  `prep_siteserver/tasks/main.yml`. Needs to be lifted into a variable so the
  filename can move with the URL.
- `adksetup_url` / `adkwinpesetup_url` — ADK matched to the SCCM baseline.

Two possible seams:

1. **Override in `slab` group_vars** — leave the collection defaults alone,
   override the three URLs (and `configmgr_filename`) in
   `vsphere/small-lab/ansible/group_vars/all/main.yml`. Simplest. Zero risk
   of breaking mayyhem.
2. **Bump collection defaults** — update the defaults to the current baseline
   in a cherry-pickable commit on `feat/upstream-fixes`. Benefits mayyhem too,
   but only if mayyhem wants a newer baseline; keep it decoupled unless
   asked.

Recommended: **option 1**. Slab overrides in group_vars, collection defaults
untouched.

Concrete task at implementation time:

- Confirm the current SCCM current-branch baseline (as of writing, likely
  2503 or 2509 — check
  https://learn.microsoft.com/en-us/intune/configmgr/core/servers/manage/updates
  and the associated Microsoft download center page).
- Grab the direct download URL for the baseline `.exe`.
- Grab the matching ADK + WinPE add-on URLs.
- Verify `ConfigMgrSetup.ini.j2` still uses the correct schema for that
  baseline. If Microsoft added or renamed keys between 2303 and current, the
  template needs a diff.

The **180-day eval clock** starts at first setup. When it approaches, either
rebuild from scratch or license the site. This lab's whole point is being
disposable, so rebuild is fine.

## Ordering (site.yml)

Same shape as the mayyhem playbook, minus the tiers that don't exist:

1. `00_connectivity.yml` — WinRM handshake to all three VMs.
2. `05_ad_forest.yml` — promote `slab-dc` to a new forest `slab.lab`.
3. `10_windows_base.yml` — `windows_base` role on all three (firewall off,
   Defender off, WebClient started).
4. `15_domain_join.yml` — join `slab-pss` and `slab-db` to `slab.lab`.
5. `20_install_adcs.yml` — ADCS on `slab-dc` (Web Enrollment included, per
   `feat/upstream-fixes` fix).
6. `30_prep_site_systems.yml` — `prep_siteserver` on `slab-pss` (this is
   where the SCCM + ADK downloads happen, using the overridden URLs).
7. `35_admin_plumbing.yml` — `add_pss_to_admins` on `slab-db` so `slab-pss$`
   is a local admin there.
8. `40_install_database.yml` — `install_site_database` on `slab-db` (SQL 2022
   from the hardcoded MS URL — leave that alone).
9. `50_install_primary.yml` — `install_primary_site` on `slab-pss`. Because
   MP+DP+SMS provider are all colocated on `slab-pss`, the site-system
   hostnames in role_vars all point at `slab-pss`. No separate `prep_mp` /
   `prep_dp` / `prep_sms` / `install_sms` steps needed for a colocated setup
   — the standalone-primary install wires those in.
10. `70_verify.yml` — confirm `SMS_EXECUTIVE` is running, console installed,
    setup log shows completion.

## Key role_vars for `slab-pss`

```yaml
ludus_sccm_sitecode: SLB
ludus_sccm_sitename: Slab Primary Site
ludus_sccm_site_server_hostname: 'slab-pss'
ludus_sccm_sql_server_hostname: 'slab-db'
# All site systems colocated on the PSS:
ludus_sccm_mgmt_server_hostname: 'slab-pss'
ludus_sccm_distro_server_hostname: 'slab-pss'
ludus_sccm_sms_provider_hostname: 'slab-pss'
# No hierarchy:
ludus_sccm_win_sccm_config_default_template: ConfigMgrSetup.ini.j2  # standalone template
ludus_sccm_parent_sitecode: ''
# Kill PXE on this single-DP lab (avoids being a rogue responder on the shared subnet):
ludus_sccm_enable_pxe: false
# Everything else can inherit collection defaults.
```

## Update strategy

Manual, in-place, via the SCCM console:

1. `Administration → Overview → Updates and Servicing`.
2. When a new current-branch update appears, right-click → `Install Update
   Pack`.
3. Reboot if prompted.

No automation. Manual because: (a) SCCM upgrades occasionally require console
attention, (b) doing them by hand is part of what makes it a research lab
worth having.

When a new **baseline** ships (2-3× per year), decide whether to:

- In-place upgrade from the current install (works between adjacent
  baselines).
- Rebuild the lab: `terraform destroy` (with plan review), bump the URLs in
  group_vars, `terraform apply`, replay playbooks. Total time ~90 minutes.

## Secrets and public-repo hygiene

Same rules as the rest of the repo (see root `AGENTS.md`):

- No vCenter server / cluster / datastore / port-group names in committed
  files. Those live in `~/.mayyhem-sccm/vsphere.tfvars` and
  `ENVIRONMENT.local.md`.
- The IPs `192.0.2.117-119` **are** committable — they're inside the RFC1918
  block already documented in the lab and don't identify the operator's real
  environment.
- Domain `slab.lab` is a lab-owned placeholder, safe to commit.

## Phased implementation — historical record

The original phase gates ran as follows (all succeeded 2026-09-09):

- **Phase 1 — terraform scaffolding.** ✓ Committed
  `8d3e707 vsphere: add small-lab (slab)`. `terraform init && validate`
  green. First `terraform plan` = 3 creates.
- **Phase 2 — terraform apply.** ✓ 3 VMs created. Guest customization
  reported timeout on all 3 despite actually succeeding — see the
  "Windows guest-customization taints" note in the As-built section.
- **Phase 3 — ansible scaffolding.** ✓ Committed
  `46a4ab5 vsphere: slab ansible scaffolding + computer_name fix`. Same
  commit rolled in the NetBIOS collision fix caught while eyeballing
  the first terraform plan.
- **Phase 4 — AD + base.** ✓ 05_ad_forest, 10_windows_base,
  15_domain_join, 20_install_adcs all clean. Phase 05 needed one retry
  on a transient WinRM 400 during the OU=Servers task — idempotent
  play, second run finished.
- **Phase 5 — SCCM baseline URL discovery.** ✓ (with a fallback — see
  the "latest SCCM attempt that didn't work" note above). Ended up
  reverting to collection defaults (2403). Committed
  `be9c2dc vsphere/small-lab: pin baseline to 2403`.
- **Phase 6 — SQL install.** ✓ SQL Server 2022 up on slab-db.
  `SLAB-PSS$` and `SLAB\domainadmin` are sysadmins.
- **Phase 7 — SCCM install.** ✓ Standalone primary on slab-pss.
  `SMS_EXECUTIVE` + `SMS_SITE_COMPONENT_MANAGER` running. Provider WMI
  reports site `SLB`. Boundary group `Discovery Default Boundary Group
  - SLB` created (also confirms the collection's per-site boundary-
  naming fix — upstream-fixes §2.1 — works).
- **Phase 8 — smoke test.** ⏳ Operator's follow-up: RDP to slab-pss,
  open console, install 2509 update pack via
  `Administration → Updates and Servicing`, then verify client push
  against a fresh test client.

## Answers to the original open questions

- **vSphere folder name.** `Personal/example/sccm-lab-slab` — parallel
  to mayyhem's `Personal/example/sccm-lab-mayyhem`. Operator created it
  in vCenter by hand before phase 2.
- **Template.** Same `windows-server-2022-template` mayyhem uses. Read-
  only reference; the module never modifies templates.
- **Disk size.** slab-dc 80 GB (template base — cannot shrink below
  template's disk), slab-pss 200 GB, slab-db 100 GB.
- **RAM / CPU.** slab-dc 4 GB / 2 vCPU, slab-pss 8 GB / 4 vCPU, slab-db
  8 GB / 4 vCPU.
- **Backup / snapshot before upgrades.** Manual, operator's call.
  Recommended before applying any Updates and Servicing pack from the
  console, since in-place SCCM upgrades are hard to roll back cleanly.
