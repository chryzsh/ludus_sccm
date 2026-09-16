# Workshop on-call runbook

Workshop: **2026-09-17**. Purpose: a lean doc for the on-call Claude
Code session (or a fresh you) to handle live workshop failures without
first reading hundreds of lines of build history. Fuller context:

- `docs/workshop-handover.md` — full "what was built and how" (on
  `feat/lab-docs`; if you're on `feat/vsphere-port`, `git show
  feat/lab-docs:docs/workshop-handover.md`).
- `docs/small-latest-lab-plan.md` — slab lab (separate from workshop).
- `AGENTS.md` — repo-wide rules including the operational-lessons
  section (secrets policy, ansible-on-Windows patterns, VM safety).

## Quick reference — mayyhem workshop lab

- Domain: **mayyhem.com** / NetBIOS `MAYYHEM`
- vSphere folder: `Personal/example/sccm-lab-mayyhem`
- Ansible controller: this Mac.
  - Repo: `/Users/chrisr/opt/ludus_sccm_mayyhem`
  - Ansible dir: `vsphere/ansible/` — **always invoke via `./run.sh`**
    (bare `ansible` routes through the corp proxy and times out).
  - Inventory is generated: `python3 sync_inventory.py` regenerates
    `inventory.yml` from `../terraform/terraform.tfstate`. Re-run
    after any terraform apply/import.
- Real credentials + vCenter connection: `~/.mayyhem-sccm/vsphere.tfvars`
  (gitignored).

### Hosts

| Host | IP | Role |
|---|---|---|
| dc | 192.0.2.70 | DC (mayyhem.com) + ADCS |
| cas-db, cas-scp, cas-pss | .71–.73 | CAS tier |
| ps1-db | .74 | Site database (MSSQLSERVER) |
| ps1-lib | .75 | Content library share |
| ps1-psv | .76 | Passive site server |
| ps1-dp | .77 | Distribution point (PXE-enabled) |
| ps1-mp | .78 | Management point |
| ps1-sms | .79 | Remote SMS provider |
| ps1-pss | .80 | PS1 primary site server |
| ps1-dev | .81 | Win11 client (CM-enrolled) |
| ps1-sec | .82 | Secondary site server (relay target) |
| monitor | .83 | TAKEOVER-9 third-party SQL host |
| ps1-lab | 192.0.2.84 | Workshop RDP host — RDS Session Host, CM-enrolled |
| ubuntu-student01..10 | 192.0.2.90–.99 | Student attack workstations |
| ubuntu-student11, .12 | 192.0.2.101, .102 | (.100 skipped, in use elsewhere) |

### Credentials

| What | Value |
|---|---|
| Domain admin | `MAYYHEM\domainadmin` / `<domain-admin-password>` |
| Local Administrator (all VMs) | `Administrator` / `<domain-admin-password>` |
| Windows student RDP (ps1-lab) | `MAYYHEM\studentNN` / `Password123` (NN=01..10) |
| Windows demo users (ps1-dev) | `MAYYHEM\domainuser` / `Password123`, `MAYYHEM\helpdesk` / `Password123` |
| Ubuntu student SSH | `studentNN` / `Password123` (NN=01..12), sudo NOPASSWD |
| Ubuntu ansible bootstrap | `ansible` user, SSH key `~/opt/keys/id_ecdsa` |
| SCCM NAA | `MAYYHEM\networkaccess` / `Password123` |
| SCCM client push | `MAYYHEM\clientpush` / `Password123` |

## Runbooks

### 1. Student ubuntu VM unreachable / SSH broken

**Diagnose (from Mac):**
```bash
ping -c 3 192.0.2.9X                            # basic reach
ssh -o ConnectTimeout=5 studentNN@192.0.2.9X true 2>&1
```

**If ping fails**: VM likely down or network broke. Check vSphere UI
(`govc find vm -name 'ubuntu-studentNN'`, or the web UI at the vCenter
URL in `~/.mayyhem-sccm/vsphere.tfvars`). Power on if off. If the VM
is missing entirely, see runbook 5.

**If ping OK but SSH fails**: sshd probably died or config broke. Use
vSphere console (web UI) to log in as `ansible` (key auth won't work
from the browser; may need to reset password via govc guest-ops if
truly locked out).

**If everything's up but the student's tools are broken** (venv gone,
missing bin, etc.): re-run the provisioning playbook against just
that host:
```bash
cd vsphere/ansible
./run.sh misc_provision_ubuntu_students.yml --limit ubuntu-studentNN
```
Idempotent — safe to re-run repeatedly.

**Nuclear**: `terraform taint 'vsphere_virtual_machine.mayyhem_vm["ubuntu-studentNN"]'`
→ `terraform apply` → the customize timeout WILL fire (see AGENTS.md
"Windows guest-customization false-negative recovery" — same for
Ubuntu GOSC) → `terraform untaint ...` → `sync_inventory.py` →
re-run misc_provision_ubuntu_students.yml. **~10 min total.**

### 2. Student can't RDP to ps1-lab / session stuck

**Diagnose:**
```bash
./run.sh -m ansible.windows.win_service -a 'name=TermService' ps1-lab
./run.sh -m ansible.windows.win_shell -a 'quser' ps1-lab
```

**Common fixes:**

- **Stuck session** — log the student off:
  ```
  ./run.sh -m ansible.windows.win_shell -a 'logoff <sessionid> /server:ps1-lab' ps1-lab
  ```
  (Get sessionid from `quser`.)

- **RDS SH quota reached** — usually not, we have 10 accounts + no CAL
  server (120-day grace). If it happens, restart TermService:
  ```
  ./run.sh -m ansible.windows.win_service -a 'name=TermService state=restarted' ps1-lab
  ```

- **SharpSCCM missing from `C:\tools\`** — re-run workshop prep:
  ```
  ./run.sh misc_workshop_prep_ps1_lab.yml
  ```
  Idempotent — restores SharpSCCM, Defender exclusion, tools folder.

- **Defender killed the tools** — check Windows Defender events. Prep
  playbook has a `Set-MpPreference -ExclusionPath 'C:\tools'` in the
  Policies subtree; if that got clobbered by GPO refresh, re-run
  `misc_workshop_prep_ps1_lab.yml`.

- **Student account locked out in AD** — 3 bad passwords lock for 30 min
  by default. Unlock:
  ```
  ./run.sh -m ansible.windows.win_shell -a 'Unlock-ADAccount -Identity studentNN' dc
  ```

### 3. SCCM core component down (SMS_EXECUTIVE / MP / DP / provider)

**Where to look first:**

| Component | Host | Log |
|---|---|---|
| SMS_EXECUTIVE | ps1-pss (site server) | `C:\Program Files\Microsoft Configuration Manager\Logs\smsexec.log` |
| SMS Provider (WMI) | ps1-sms | `C:\Program Files\Microsoft Configuration Manager\Logs\SMSProv.log` |
| Site component mgmt (hman) | ps1-pss | `hman.log` (same dir) |
| MP | ps1-mp | `mpcontrol.log`, IIS logs |
| DP | ps1-dp | `distmgr.log` on ps1-pss, `smsdpprov.log` on ps1-dp |
| Database | ps1-db | `Windows Application Log`, SQL error log |
| Client push | ps1-pss | `ccm.log` on the client, `client.msi.log` on target |

**Restart order for a full component reset** (rarely needed):

```
./run.sh -m ansible.windows.win_service -a 'name=SMS_EXECUTIVE state=restarted force_dependent_services=true' ps1-pss
```

This restarts every SMS_* component. Wait 2–3 min for them to settle.

**Common causes of degradation during a workshop:**

- **Disk space on ps1-pss** — SCCM likes 15+ GB free. Check with:
  ```
  ./run.sh -m ansible.windows.win_shell -a 'Get-CimInstance Win32_LogicalDisk -Filter "DeviceID=\"C:\""' ps1-pss
  ```
  If low, largest offenders are usually `C:\Program Files\Microsoft
  Configuration Manager\CMUStaging\` (delete per-GUID subfolders for
  updates you don't intend to install) and Windows Update cache.

- **SQL out of memory / stuck** — Restart-Service MSSQLSERVER on
  ps1-db. Then Restart-Service SMS_EXECUTIVE on ps1-pss (dependent).

- **Client push failing to students** — students aren't SCCM clients;
  they're Ubuntu attack VMs. This should only affect ps1-lab and
  ps1-dev.

### 4. Windows Update snuck in on ps1-lab despite freeze

Symptoms: ps1-lab rebooted mid-workshop, or reports "update pending".

**Diagnose:**
```
./run.sh -m ansible.windows.win_service -a 'name=wuauserv' ps1-lab
./run.sh -m ansible.windows.win_service -a 'name=UsoSvc' ps1-lab
./run.sh -m ansible.windows.win_shell -a '(New-Object -ComObject Microsoft.Update.SystemInfo).RebootRequired' ps1-lab
```

Both `wuauserv` and `UsoSvc` should show `start_mode: disabled` and
`state: stopped`. If either drifted:

**Re-freeze:**
```
./run.sh misc_freeze_windows_update_ps1_lab.yml
```

**Kill any pending update** (last resort — may leave WU in a weird
state, students shouldn't notice):
```
./run.sh -m ansible.windows.win_shell -a 'Stop-Service wuauserv,UsoSvc,WaaSMedicSvc -Force; Set-Service wuauserv,UsoSvc -StartupType Disabled' ps1-lab
```

### 5. Terraform / vCenter drift (VM missing, state confused)

**Never run `terraform apply` without a plan first**, and never
`terraform destroy` autonomously — see AGENTS.md "VM safety in a
shared vCenter".

**A VM shows as missing:**

1. Check the vSphere UI first. If the VM is there and healthy,
   terraform state may just be stale — do NOT immediately refresh
   or import. Just proceed with ansible against the live VM.
2. If the VM is genuinely gone, produce a plan:
   ```
   cd vsphere/terraform
   terraform plan -var-file=~/.mayyhem-sccm/vsphere.tfvars -out=recover.tfplan
   ```
   The plan should show only the missing VM as a re-create. If it
   shows anything else destroyed/replaced, STOP.
3. Get explicit operator go-ahead before `terraform apply recover.tfplan`.

**Lock a student out temporarily** (e.g. rogue behaviour, unauthorised
access):
```
./run.sh -m ansible.windows.win_shell -a 'Disable-ADAccount -Identity studentNN' dc
```
Re-enable with `Enable-ADAccount -Identity studentNN`. For the ubuntu
tier: `sudo passwd -l studentNN` on the specific VM (or add a shutdown
via govc). Do not delete the account — recovery is harder than a
disable.

## Common commands cheat sheet

```
# Regenerate inventory after any terraform change
cd vsphere/ansible && python3 sync_inventory.py

# WinRM ping a single host (or group)
./run.sh -m ansible.windows.win_ping <host-or-group>

# Read a Windows log tail without downloading it
./run.sh -m ansible.windows.win_shell -a 'Get-Content <path> -Tail 30' <host>

# Restart a Windows service
./run.sh -m ansible.windows.win_service -a 'name=<svc> state=restarted' <host>

# Run a misc_ playbook against one host only
./run.sh misc_<name>.yml --limit <host>

# See what's on the ansible controller's mind for a given host
./run.sh -m ansible.builtin.setup -a 'gather_subset=network' <host>
```

## Where the fuller context lives

- **Full build history + why decisions were made**:
  `docs/workshop-handover.md` (on `feat/lab-docs`).
- **Slab lab (separate from workshop, standalone SCCM 2509)**:
  `docs/small-latest-lab-plan.md`.
- **Operational rules + Ansible-on-Windows gotchas + secrets policy**:
  `AGENTS.md` (top of repo).
- **Real vCenter/creds/IPs**: `~/.mayyhem-sccm/vsphere.tfvars`,
  `ENVIRONMENT.local.md` (both gitignored, mode 600).
- **Universal operational rules loaded by any Claude Code session**:
  `~/.claude/operational-rules.md` + memory under
  `~/.claude/projects/-Users-chrisr-opt/memory/`.
