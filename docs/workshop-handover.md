# Workshop lab handover — 2026-09-07

Handover for the next Claude Code session (or a fresh you) working on
the SCCM workshop lab. Everything the previous session built + current
state + what's left.

Workshop date: **2026-09-17**.

## Lab topology (all in vCenter folder `Personal/example/sccm-lab-mayyhem`)

### SCCM hierarchy (15 VMs, previously existing + one added this session)

| Host | IP | Role |
|---|---|---|
| dc | 192.0.2.70 | DC (mayyhem.com) |
| cas-db, cas-scp, cas-pss | .71–.73 | CAS tier |
| ps1-db, ps1-lib, ps1-psv, ps1-dp, ps1-mp, ps1-sms, ps1-pss | .74–.80 | PS1 site systems |
| ps1-dev | .81 | Win11 client, CM-enrolled |
| ps1-sec | .82 | PS1 secondary site server |
| monitor | .83 | Third-party SQL host (TAKEOVER-9 lab) |
| **ps1-lab** | **192.0.2.84** | **Workshop RDP host (Server 2022, RDS Session Host, CM-enrolled)** |

### Ubuntu student workstations (12 VMs, all new this session)

| Host | IP | User |
|---|---|---|
| ubuntu-student01 | 192.0.2.90 | student01 |
| ubuntu-student02 | 192.0.2.91 | student02 |
| ubuntu-student03 | 192.0.2.92 | student03 |
| ubuntu-student04 | 192.0.2.93 | student04 |
| ubuntu-student05 | 192.0.2.94 | student05 |
| ubuntu-student06 | 192.0.2.95 | student06 |
| ubuntu-student07 | 192.0.2.96 | student07 |
| ubuntu-student08 | 192.0.2.97 | student08 |
| ubuntu-student09 | 192.0.2.98 | student09 |
| ubuntu-student10 | 192.0.2.99 | student10 |
| ubuntu-student11 | 192.0.2.101 | student11 |
| ubuntu-student12 | 192.0.2.102 | student12 |

`.100` deliberately skipped (in use elsewhere on the network).

Ubuntu VMs are Ubuntu 26.04.1 LTS, not domain-joined, sized 2 vCPU /
4 GB RAM / 60 GB thin disk. Not in `site.yml` — provisioned via
`misc_provision_ubuntu_students.yml`.

## Credentials (all lab-grade)

| What | Value |
|---|---|
| Domain admin | `MAYYHEM\domainadmin` / `<domain-admin-password>` |
| Local Windows Admin | `Administrator` / `<domain-admin-password>` |
| ps1-dev pre-domain-join | `Admin` / see `ENVIRONMENT.local.md` |
| Windows student accounts (RDP to ps1-lab) | `MAYYHEM\studentNN` / `Password123` (NN = 01..10) |
| Windows demo users (ps1-dev) | `MAYYHEM\domainuser` / `Password123`, `MAYYHEM\helpdesk` / `Password123` |
| Ubuntu student accounts (SSH) | `studentNN` / `Password123` (NN = 01..12), sudo NOPASSWD |
| Ubuntu ansible bootstrap user | `ansible` / SSH key at `~/opt/keys/id_ecdsa` |
| SCCM NAA account | `MAYYHEM\networkaccess` / `Password123` |
| SCCM client push account | `MAYYHEM\clientpush` / `Password123` |
| vCenter connection | in `~/.mayyhem-sccm/vsphere.tfvars` (out-of-tree, gitignored) |

## What was done this session (in order)

1. **Lab change request executed** — enforced SMB signing on ps1-sec
   for the ELEVATE-2 / PREVENT-12 experiment. Playbook:
   `vsphere/ansible/misc_enforce_smb_signing_ps1_sec.yml`.
   `RequireSecuritySignature=1` + `EnableSecuritySignature=1` on
   ps1-sec's LanmanServer; ps1-pss$ still local admin; signed SMB
   from ps1-pss → ps1-sec still works. **Uncommitted** (never got
   the sign-off to commit that one specifically).

2. **`create_demo_users` role** — cherry-picked from
   `origin/feat/demo-user` onto `feat/vsphere-port`. Creates
   `domainuser` (RDP-only) + `helpdesk` (RDP + local admin) on ps1-dev
   as the collection's default. Run via
   `vsphere/ansible/36_demo_users.yml` (wired into `site.yml`).

3. **PR draft** for upstreaming `create_demo_users` — sits at
   `docs/pr-draft-create-demo-users.md`. Head branch on origin is
   `feat/demo-user`, base is `Mayyhem/ludus_sccm:main`. **Not opened
   as a PR** — per CLAUDE.md rules the operator opens PRs, not
   Claude.

4. **ps1-lab workshop RDP host added** — new Server 2022 host at
   `192.0.2.84`, 8 vCPU / 16 GB RAM / 80 GB. RDS Session Host role
   installed (120-day grace, no CAL server needed). 10 student
   accounts (`MAYYHEM\student01..student10`, `Password123`, all local
   Administrators + Remote Desktop Users). CM-enrolled via manual
   ccmsetup bootstrap (client push discovery is too slow for
   workshop timing). NAA cache verified on the client, so CRED-1
   works. Files: `vsphere/ansible/host_vars/ps1-lab/`,
   `37_workshop_rds.yml`, terraform locals/variables. Committed +
   pushed as commit `f1ae590`.

5. **Workshop reliability** — SharpSCCM v2.0.13 staged at
   `C:\tools\SharpSCCM.exe` on ps1-lab (checksum-pinned), Defender
   exclusion for `C:\tools` in the Policies subtree, Windows Update
   frozen (wuauserv + UsoSvc disabled, WaaSMedicSvc stopped). Files:
   `misc_workshop_prep_ps1_lab.yml`, `misc_freeze_windows_update_ps1_lab.yml`.
   Committed + pushed as commit `a206613`.

6. **Secrets remediation** — the branch was carrying two files with
   real credentials in commit history that were about to hit origin
   (a possibly-public fork):
   - `docs/takeover-9-handoff.md` (<domain-admin-password>, CHANGE_ME, real IPs) —
     redacted via `git rebase --exec` across the two commits that
     touched it. Squashed into single commit `fecf847`. Force-push
     not needed — those commits weren't yet on origin.
   - `VSPHERE_PORT_PLAN.md` (CHANGE_ME for ps1-dev packer bootstrap)
     — redacted in a follow-forward commit `2d14d91`. **Historic
     leak still on origin from commit `41d8ffb` (already public);
     packer bootstrap password should be rotated at next template
     rebake.**

7. **12 Ubuntu student attack workstations** — cloned from
   `ubuntu-2604-template` (which the operator's template-agent
   rebaked mid-session to add `datasource_list: [VMware, OVF, None]`
   to `/etc/cloud/cloud.cfg.d/`, enabling vSphere GOSC via
   cloud-init). Per-student SSH login `studentNN` / `Password123` +
   NOPASSWD sudo. Shared pentest venv at `~/venv/pentest`
   auto-activates on login. Tools: impacket 0.13.1, ldeep 2.0.3,
   sccmhunter, PXEHacker, PetitPotam, RelayInformer (isolated in its
   own venv `~/venv/relayinformer/` because its pinned deps conflict
   with everything else). All 6 tools verified end-to-end against
   the real SCCM lab. Files: `misc_provision_ubuntu_students.yml`,
   terraform locals/variables, sync_inventory.py. **Uncommitted.**

## Uncommitted work

| Path | Status | Notes |
|---|---|---|
| `AGENTS.md` | modified | Pre-existing WIP from a prior session; not this session's; leave alone. |
| `vsphere/ansible/misc_enforce_smb_signing_ps1_sec.yml` | untracked | ELEVATE-2 SMB signing playbook (see item 1 above). |
| `vsphere/terraform/locals.tf` | modified | ubuntu-student range extended 1..12 + linux template branch. |
| `vsphere/terraform/variables.tf` | modified | 12 ubuntu-studentNN entries in vm_ips validation + vsphere_linux_template variable. |
| `vsphere/terraform/main.tf` | modified | `data "vsphere_virtual_machine" "linux_template"` (count-gated). |
| `vsphere/terraform/vms.tf` | modified | 3-way template_lookup (server / workstation / linux) + dynamic customize block for linux_options vs windows_options + notes on why customize.timeout must not be set. |
| `vsphere/ansible/sync_inventory.py` | modified | `STUDENTS_TIER` set + emits `students_tier` inventory group with SSH transport vars. |
| `vsphere/ansible/misc_provision_ubuntu_students.yml` | untracked | 12-VM provisioning playbook: user + sudo + uv + venv + tools. |

All the above should commit cleanly as one atomic "ubuntu-student
tier" commit — that was the deferred plan (wait until end-to-end
works before committing). It's now proven working; next-you can
commit + push.

Also uncommitted in `~/.mayyhem-sccm/vsphere.tfvars` (out of tree
per secrets policy): `vsphere_linux_template = "ubuntu-2604-template"`
+ 12 ubuntu-studentNN IP entries. Nothing to commit — this file
never gets committed by design.

## Known quirks + gotchas

- **Ubuntu customize.timeout**: DO NOT set `customize { timeout = ... }`
  in `vms.tf`. It's a ForceNew attribute in the vSphere provider —
  changing it destroys+recreates every VM in state. On the current
  config it's unset, which means terraform uses its default 10-min
  poll, sees Linux GOSC never signal completion (Ubuntu's cloud-init
  applies the config correctly but doesn't send the vSphere
  completion signal), and taints every new ubuntu VM. The workflow
  is: apply → apply "fails" with timeout → the VMs are actually
  fine → `terraform untaint ...` for each → `sync_inventory.py` →
  run playbook. Baked-in ugliness; see the comment block at the top
  of the `customize` block in `vms.tf`.

- **Ubuntu template firmware is BIOS**, not EFI. This is explicitly
  set in `template_lookup` for the linux family. If someone rebuilds
  the template as EFI in the future, flip that entry to `"efi"`.

- **RelayInformer needs its own venv** (`~/venv/relayinformer/`).
  Its pyproject pins impacket at a specific commit + msldap 0.4.7 +
  ldap3 2.9.1 + pyasn1 0.5.0 — all conflict with the shared pentest
  venv's stack. The `relayinformer` alias in the students'
  auto-activated venv points at the isolated venv's binary.

- **ldeep needs the cannatag@dev ldap3 fork** + pyasn1 pinned to
  0.4.8. Neither pypi mainline ldap3 (2.9.1) nor `ldap3-bleeding-edge`
  provide the `ENCRYPT` symbol ldeep imports. The `ldeep_stack`
  install task in the provisioning playbook installs
  `pyasn1==0.4.8`, `git+cannatag/ldap3.git@dev`, and `ldeep` in one
  `--reinstall` pass, positioned LAST in the task order so nothing
  clobbers the dev-branch ldap3 afterwards.

- **`ansible_password` leaks** from `group_vars/all/local.yml`
  (Windows WinRM) into the SSH connection for the ubuntu tier and
  triggers a `sshpass` demand. Overridden at play level
  (`vars: { ansible_password: "" }`) in
  `misc_provision_ubuntu_students.yml`. Any future playbook
  targeting `students_tier` must do the same override.

- **passlib not required on controller** — student password hash
  is pre-computed with `openssl passwd -6` and hard-coded as
  `student_password_hash` in the provisioning playbook. If the
  plaintext ever changes, regenerate:
  `openssl passwd -6 -salt $(openssl rand -hex 8) 'NewPassword'`.

- **ps1-lab customization also timed out on apply** (same Linux-ish
  behaviour on Server 2022 — completed past the 10-min poll horizon
  but VM was actually functional). Untainted after verify. Precedent
  for the ubuntu workflow.

- **Historic `CHANGE_ME` leak** on `VSPHERE_PORT_PLAN.md` (commit
  `41d8ffb` on origin). Force-push would only partially remove it —
  GitHub caches persist. Operator plans to rotate the packer
  bootstrap password when rebuilding the Win11 template.

## Workshop student getting-started (already tested)

Every student's VM is ready. Give each student their line:

```
ssh studentNN@192.0.2.9X    # password: Password123
```

(Where NN = 01..12 and X = last octet, e.g. student01 → .90,
student11 → .101, student12 → .102.)

On login the venv auto-activates. Verified working end-to-end
against the real SCCM lab:

- **Impacket suite**: `GetADUsers.py`, `secretsdump.py`,
  `ntlmrelayx.py`, `GetNPUsers.py`, `GetUserSPNs.py`, etc. — 40+
  scripts on `$PATH`.
- **`ldeep`**: e.g.
  `ldeep ldap -d mayyhem.com -u domainuser -p Password123 -s ldap://192.0.2.70 users`
  returns the actual AD user list.
- **`sccmhunter find -u domainuser -p Password123 -d mayyhem.com -dc-ip 192.0.2.70`**
  returns real SCCM enum: 1 MP, 1 potential PXE DP, 3 SCCM
  principals.
- **`sccmhunter`, `PXEHacker`, `PetitPotam`** — aliases in `.bashrc`.
- **`relayinformer`** — command from isolated venv.

For the RDP side: `MAYYHEM\studentNN` with `Password123` RDPs into
`ps1-lab` (192.0.2.84); each student gets their own session on the
RDS Session Host. SharpSCCM.exe is at `C:\tools\`.

## Recommended next steps for the next session

1. **Commit the ubuntu-student tier** — everything's proven working
   end-to-end. One atomic commit on `feat/vsphere-port`:
   ```
   git add \
     vsphere/terraform/{locals,variables,main,vms}.tf \
     vsphere/ansible/sync_inventory.py \
     vsphere/ansible/misc_provision_ubuntu_students.yml
   git commit -m "vsphere: add 12-VM Ubuntu student tier for workshop"
   ```
   Then ask the operator before push.

2. **Optionally commit `misc_enforce_smb_signing_ps1_sec.yml`** —
   ask the operator first; that was from a separate task earlier.

3. **On workshop day (2026-09-17)**: freeze is already in place on
   ps1-lab (`wuauserv`, `UsoSvc` disabled). Sanity-check that RDP
   still works from 2-3 clients simultaneously to ps1-lab, and that
   one student VM's `sccmhunter find` still returns data.

## Where key context lives (for the next you)

- Local rules: `/Users/chrisr/opt/CLAUDE.md` — HARD RULES about not
  opening PRs and always asking before push.
- Global memory: `~/.claude/projects/-Users-chrisr-opt/memory/`
  (auto-loaded).
- Secrets policy: `AGENTS.md` (top of this repo) — pre-push scan
  before ANY push to origin; scan for the operator's real
  environment-specific tokens listed in
  `~/.mayyhem-sccm/pre-push-tokens.txt` (a local-only file, kept
  outside the repo so this doc itself doesn't leak the patterns).
- Real env values: `ENVIRONMENT.local.md` + `~/.mayyhem-sccm/vsphere.tfvars`
  (both gitignored).
- Workshop VM layout is documented above; SCCM lab layout is in
  the collection's own docs + `new-config.yml`.
