# slab lab — handover for a takeover session

Lean companion to `docs/small-latest-lab-plan.md` (472 lines of full
plan + as-built narrative). This doc is what a fresh agent — human or
Claude — reads first when they need to actually **operate** the slab
lab: check health, apply an upgrade, respond to a breakage, extend
with something new.

If anything here disagrees with the plan doc, the plan doc's As-built
section is authoritative — it's the running record of what actually
shipped and got fixed.

## Bootstrap prompt for a fresh Claude Code session

Paste after starting Claude in `/Users/chrisr/opt/ludus_sccm_mayyhem`
on branch `feat/small-latest-lab`:

> You're taking over the slab lab. Read `docs/small-latest-lab-handover.md`
> first, then `docs/small-latest-lab-plan.md` for background if the
> task requires it. Acknowledge when the handover doc is loaded, then
> wait for me to describe the task. Do not push, do not run
> `terraform apply` or `terraform destroy` without an explicit plan
> review, do not fire in-place SCCM upgrades without confirming the
> lab is at a clean baseline first.

## What the slab lab is

Standalone SCCM primary site running the current baseline (2509 as of
2026-09-11). 3 VMs in vSphere, own domain, sibling to the mayyhem
hierarchy lab but completely isolated in state, folder, prefix, and
credentials. Meant to be **always on** for security research on a
current SCCM version without disturbing the big lab's rebuild cadence.

## Quick reference

- Domain: **slab.lab** / NetBIOS `SLAB` / site code `SLB`
- vSphere folder: `Personal/example/sccm-lab-slab`
- SCCM version: **2509 (build 9141, 5.00.9141.1000)** — upgraded from
  2403 baseline 2026-09-10
- Branch: `feat/small-latest-lab` (subordinate to `feat/vsphere-port`)
- Terraform: `vsphere/small-lab/terraform/` — state local, gitignored
- Ansible: `vsphere/small-lab/ansible/` — 10 phase playbooks (00→70),
  invoke via `./run.sh`
- tfvars: `~/.mayyhem-sccm/slab.tfvars` (gitignored, mode 600)

### Hosts

| Host | IP | Role | vCPU / RAM / C: |
|---|---|---|---|
| slab-dc | 192.0.2.117 | DC (`slab.lab`) + ADCS ("SLAB-CA") | 2 / 4 GB / 80 GB |
| slab-pss | 192.0.2.118 | SCCM primary + MP + DP + SMS Provider + SCP (all colocated); PXE disabled | 4 / 8 GB / 200 GB |
| slab-db | 192.0.2.119 | SQL Server 2022 (`MSSQLSERVER`), site DB `CM_SLB` | 4 / 8 GB / 100 GB |

### Credentials

| What | Value |
|---|---|
| Local Administrator (all 3) | `Administrator` / `<domain-admin-password>` |
| Domain admin (Domain + Enterprise + Schema Admin, SCCM Full Admin, SQL sysadmin) | `SLAB\domainadmin` / `<domain-admin-password>` |
| Domain join account | `SLAB\domainjoin` / `Password123` |
| SCCM NAA | `SLAB\networkaccess` / `Password123` |
| SCCM client push / task-seq / domain-join | `SLAB\sccm_push` / `Password123` |
| SQL Server service account | `SLAB\sqlsccmsvc` / `Password123` |

### Access

- **RDP** to any slab-*: address `slab-<host>.slab.lab` (or IP), user
  `SLAB\domainadmin` / `<domain-admin-password>`.
- **Configuration Manager Console**: Start Menu on slab-pss (RDP in
  first). Signs in as the logged-in user.
- **WinRM (Ansible)**: 5985/HTTP, NTLM, `Administrator` (local) or
  `SLAB\domainadmin`, both password `<domain-admin-password>`.
- **SSMS to SQL**: `slab-db.slab.lab`, Windows Auth as
  `SLAB\domainadmin`.

## Health check — 30-second procedure

    cd /Users/chrisr/opt/ludus_sccm_mayyhem/vsphere/small-lab/ansible
    python3 sync_inventory.py                 # regenerate from tfstate
    ./run.sh 00_connectivity.yml              # WinRM to all 3
    ./run.sh 70_verify.yml                    # SQL up, CM_SLB present,
                                              # SMS provider WMI, SLB
                                              # boundary group

If both playbooks are green, slab is healthy. Site version:

    ./run.sh -m ansible.windows.win_shell -a 'Import-Module "C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1"; $mp = (Get-ItemProperty ''HKLM:\SOFTWARE\Wow6432Node\Microsoft\ConfigMgr10\AdminUI\Connection'' -Name Server).Server; if (-not (Get-PSDrive -Name SLB -PSProvider CMSite -ErrorAction SilentlyContinue)) { New-PSDrive -Name SLB -PSProvider CMSite -Root $mp | Out-Null }; Set-Location "SLB:\"; (Get-CMSite -SiteCode SLB).Version' slab-pss --extra-vars 'ansible_become=true ansible_become_method=runas ansible_become_user=SLAB\domainadmin ansible_become_password=<domain-admin-password>'

Should show `5.00.9141.1000` (2509).

## Regular maintenance

### Upgrading to the next SCCM baseline

    cd vsphere/small-lab/ansible
    ./run.sh 60_upgrade_sccm.yml -e slab_upgrade_dry_run=true   # list what's available
    ./run.sh 60_upgrade_sccm.yml                                # install newest applicable

The playbook handles: metadata check → wait for updates → filter to
installable (state 262146 NewestApplicable + 327682 OlderApplicable)
→ install → poll until site version flips → **console upgrade**
(`ConsoleSetup.exe /q`) → **`New-PSDrive` smoke test** → report new
version. One update per run — re-run to walk a chain.

Default flags include `-IgnorePrereqWarning:$true` because 2509+
refuses to install on outstanding site-server warnings. Override with
`-e slab_upgrade_ignore_prereq_warning=false` if you want warnings
enforced (rare).

**Known stuck**: 2603 (5.00.9146.1000) is Downloaded but SCCM's state
machine refuses to re-queue via cmdlet. See "2603 upgrade attempt" in
the plan doc for the full diagnostic story. To eventually install:
RDP to slab-pss and right-click "Install Update Pack" in the console;
that path has state-reset behaviour PowerShell doesn't expose.

### Snapshot before an upgrade

Not automated. Take a manual vSphere snapshot of slab-pss and slab-db
before running `60_upgrade_sccm.yml` on anything larger than a hotfix
rollup. `slab-dc` doesn't need snapshotting for an SCCM update.

### 180-day eval clock

SCCM installs on eval by default. Rebuild before day ~150 if the lab
is on eval, or license the site. Not currently tracked — set a
calendar reminder if you care.

## Common failure modes

### slab-pss unreachable

    ./run.sh 00_connectivity.yml

If just slab-pss fails: check vSphere UI (VM up? disk full?). If C: is
under ~5 GB free, that's the disk-grow issue rearing again — but
Phase 11 (`11_grow_partitions.yml`) should have already put C: at
199.66 GB. If not, re-run `11_grow_partitions.yml`.

### SCCM component down

Restart SMS_EXECUTIVE on slab-pss (restarts every SMS_* dependent):

    ./run.sh -m ansible.windows.win_service -a 'name=SMS_EXECUTIVE state=restarted force_dependent_services=true' slab-pss

Wait 2–3 min for components to settle. Then re-run `70_verify.yml`.

Logs to tail:
- `C:\Program Files\Microsoft Configuration Manager\Logs\smsexec.log`
- `C:\Program Files\Microsoft Configuration Manager\Logs\hman.log`
- `C:\Program Files\Microsoft Configuration Manager\Logs\SMSProv.log`
- `C:\Program Files\Microsoft Configuration Manager\Logs\CMUpdate.log`
  (during an upgrade)

### SQL down

    ./run.sh -m ansible.windows.win_service -a 'name=MSSQLSERVER state=restarted' slab-db
    # then restart the dependent SMS_EXECUTIVE
    ./run.sh -m ansible.windows.win_service -a 'name=SMS_EXECUTIVE state=restarted' slab-pss

### New-PSDrive fails with `SiteVersionMismatch`

Console was upgraded on the site or an update landed without the
post-install console fix. Run manually:

    ./run.sh -m ansible.windows.win_shell -a '"C:\Program Files\Microsoft Configuration Manager\tools\ConsoleSetup\ConsoleSetup.exe" /q' slab-pss

Then retry your work.

### Terraform state / vCenter drift

    cd vsphere/small-lab/terraform
    terraform plan -var-file=~/.mayyhem-sccm/slab.tfvars -out=plan.tfplan

**Any plan showing destroy or replace on VMs the module created** =
STOP, do not apply. Read `AGENTS.md` § "VM safety in a shared vCenter".
On slab specifically, `lifecycle.ignore_changes = [clone[0].template_uuid]`
should prevent template-rebuild churn; if you see it anyway,
investigate before applying.

Guest customization "timeout" errors on a fresh apply are false
negatives — verify with `00_connectivity.yml`, then `terraform untaint`
each VM. **Never re-apply on taint** — destroys the working VMs.

## Extending the lab

- **Bake a fix into future deploys**: change the playbook, commit on
  `feat/small-latest-lab`. Terraform lives at
  `vsphere/small-lab/terraform/`, ansible at
  `vsphere/small-lab/ansible/`. Sync inventory (`sync_inventory.py`)
  after any terraform apply.
- **Add a new phase to the spine**: create `NN_<name>.yml` and add it
  to `site.yml` in the right order. Keep it idempotent so re-running
  `site.yml` end-to-end doesn't damage a healthy lab.
- **Reuse a mayyhem-side `mayyhem.ludus_sccm.*` role**: the collection
  is provider-agnostic. Just include it in a new playbook here; no
  changes to the collection needed. If the change is a collection bug
  fix that should go upstream, put it on `feat/upstream-fixes` as a
  cherry-pickable commit.

## Where the fuller context lives

- **Full plan + as-built narrative** (why decisions were made, what
  didn't work): `docs/small-latest-lab-plan.md`.
- **Operational rules + Ansible-on-Windows gotchas + secrets policy**:
  `AGENTS.md` (top of repo).
- **User-personal quick reference (creds + rebuild)**:
  `~/.mayyhem-sccm/slab-summary.txt` (outside repo, mode 600).
- **Real vCenter connection**: `~/.mayyhem-sccm/slab.tfvars`
  (outside repo, mode 600).
- **Auto-loaded per session**: `~/.claude/operational-rules.md`
  (universal), `~/.claude/projects/-Users-chrisr-opt/memory/project_slab_lab.md`
  (slab-specific), plus the disk-grow and active-monitoring feedback
  memories.
