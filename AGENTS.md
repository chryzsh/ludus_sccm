# Agents Guide

Instructions for AI agents working in this fork.

## Repository context

Fork of `Mayyhem/ludus_sccm`. Three things going on, on three branches:

- **`feat/vsphere-port`** — a vSphere provider path so the lab can run outside Ludus/Proxmox. Terraform + Ansible playbooks under `vsphere/`, plus `docs/` design notes and handoff files. This is where lab-side work happens (adding VMs, tooling, ad-hoc fix playbooks). Deliberately not upstream-clean — carries the port scaffolding.
- **`feat/upstream-fixes`** — collection bugs surfaced while building the port, kept as isolated single-file commits that touch only `roles/` or `plugins/`. Cherry-pickable straight into a PR against `Mayyhem/ludus_sccm:main`. Current contents include per-site boundary group naming, `create_boundary_group` idempotency + the site-assignment flag, `force_gpupdate` graceful-missing-OU handling, SQL probe retry, PXE ISO filename parameterization, `New-CMOperatingSystemImage` WQL retry, ADCS Web Enrollment install, and a few smaller fixes.
- **`feat/takeover-9-role`** — deliberate misconfiguration for reproducing [TAKEOVER-9](https://github.com/subat0mik/Misconfiguration-Manager/blob/main/attack-techniques/TAKEOVER/TAKEOVER-9/takeover-9_description.md) in a lab. Adds `roles/takeover_9_setup/` that stands up a third-party SQL host with an SA-linked linked server pointing at `ps1-db`. Separate from `feat/upstream-fixes` because Mayyhem may or may not want attack-scenario roles in the collection.

Related work in the sibling repo `chryzsh/Misconfiguration-Manager` (fork of `subat0mik/Misconfiguration-Manager`): branch `docs/takeover-9-description` fleshes out the TAKEOVER-9 write-up that was previously a stub.

Remotes:
- `origin` → `chryzsh/ludus_sccm` (fork, may be public)
- `upstream` → `Mayyhem/ludus_sccm`
- Default working branch: `feat/vsphere-port`

## Secrets policy (CRITICAL — read before writing any code or docs)

**This fork may be pushed to a public GitHub repository.** No commit — code, terraform, ansible, docs, comments, examples, or plan files — may contain any of the following:

- The target vCenter server hostname or IP.
- vCenter usernames or passwords.
- Datacenter, cluster, resource pool, or datastore names.
- Port group / distributed port group / VLAN names.
- vCenter folder paths.
- Template names IF they encode organisational naming.
- Real IP addresses, subnets, gateways, DNS servers, or netmasks used in the target environment.
- Domain names owned by the operator (as opposed to the lab's own `mayyhem.com`).

**Where these values must live instead**: `ENVIRONMENT.local.md` at the repo root (gitignored, single source of truth for target-environment specifics), plus an out-of-tree tfvars file (default location `~/.mayyhem-sccm/vsphere.tfvars`) for terraform to consume at plan/apply time. Ansible group_vars files that would contain these values are also gitignored (see `.gitignore`).

**What CAN be committed**:
- Terraform variable declarations with no defaults, or with generic placeholder defaults (`"CHANGE_ME"`, `"vcenter.example"`, `10.0.0.0/24`).
- README or plan examples that use RFC1918 example blocks (`192.0.2.x`, `198.51.100.x`, `203.0.113.x`) or the documentation-only `example.com` FQDN.
- Ansible role logic and templates — the collection itself is provider-agnostic and safe to publish.

**Before any push to `origin`**:
```
git ls-files -z | xargs -0 grep -lE '<partial-vcenter-fqdn>|<datacenter-token>|<real-ip-prefix>|<port-group-name>' || echo "clean"
```
Replace the tokens with the operator's real values (the operator's local `VSPHERE_PORT_PLAN.local.md` — gitignored — is where those real values are recorded for reference). If any file matches, do not push; move the offending values into `ENVIRONMENT.local.md` or the tfvars file, and re-scan.

**If a leak happens**: force-push is not enough (mirrors and GitHub caches persist). Rotate the exposed credentials, delete the offending refs from GitHub, and treat the fork as compromised until credentials rotate.

## VM safety in a shared vCenter (CRITICAL)

The target vCenter hosts multiple independent labs and personal VMs. **Never destroy or overwrite any VM.** Applies to terraform, govc, PowerCLI, or any other path.

Hard rules:

- All lab VMs get a distinct name prefix via `range_id` / `lab_prefix` variable, and a distinct vSphere folder path. No name collisions with existing VMs.
- `for_each` over `local.vm_config` only. Never `count = length(...)` — index shifts silently reassign resource identity across applies.
- Never write `data "vsphere_virtual_machine"` against anything except the templates. Referencing a live VM by name via a data source is a footgun.
- Never run `terraform import`. State moves are a conversation, not an autonomous action.
- Never run `terraform destroy` autonomously. Always run `terraform plan -out=<file>` first, surface the summary, and pause for explicit operator go-ahead.
- On any plan that shows `will be destroyed` or `-/+ must be replaced`, STOP. Confirm the resource was created by this workflow before proceeding. Template UUID drift is a common cause of unexpected replacement — the port's terraform includes `lifecycle { ignore_changes = [clone[0].template_uuid] }` to prevent that.

If a plan wants to replace or destroy anything unexpected, the correct response is to stop and ask, not to `-refresh=false` or `--target` around the surprise.

## Workflow

1. Follow the active written plan when one exists (`VSPHERE_PORT_PLAN.md`).
2. If no plan exists and the task is multi-step, create or request a concrete plan before large changes.
3. After each meaningful milestone or blocker, explicitly state the recommended next step from the plan.
4. Before taking a material next step that changes infrastructure, deployment state, or multiple files, prompt the operator to confirm.
5. If execution diverges from the plan, say why, update the plan or propose the correction, and then prompt with the new next step.
6. End substantive progress updates with a clear `Next step:` line that matches the active plan.

## Planning rule

- Treat the plan as the source of truth for sequencing.
- Do not silently jump ahead to later phases when an earlier dependency is not validated.
- If a prerequisite is missing, the next step is to satisfy that prerequisite, not to continue past it.
- If a command or script fails, fix the failure mode first, then restate the next plan-aligned step before continuing.

## Upstream discipline

- Keep `main` clean and mergeable with `upstream/main` for future rebases.
- Do all vSphere work on `feat/vsphere-port` or a **subordinate branch of it** — see the branch table below for which work goes where.
- Collection-level bug fixes that would be useful to upstream should live in commits that touch no vSphere-specific files, so they can be cherry-picked into a PR against `upstream/main` cleanly.

## Branches — where each kind of change lives

| Change kind | Branch | Notes |
|---|---|---|
| Mayyhem lab (`vsphere/{terraform,ansible}/*`) infra + playbooks | `feat/vsphere-port` | Default working branch. Also lands `misc_*.yml` playbooks and any docs that describe the port itself. |
| Docs, PR drafts, workshop handovers | `feat/lab-docs` | Descended from `feat/vsphere-port`. Prefer for doc-only PRs and repository-hygiene edits (AGENTS.md, `docs/*`). |
| Slab (small always-on) lab: `vsphere/small-lab/*` + `docs/small-latest-lab-plan.md` | `feat/small-latest-lab` | Descended from `feat/vsphere-port`. All slab code + plan doc lives here. Do not co-mingle with mayyhem-lab work. |
| Collection bug fixes cherry-pickable upstream | `feat/upstream-fixes` | Single-file commits under `roles/` or `plugins/` only. No `vsphere/` in the diff. |
| TAKEOVER-9 attack-scenario role | `feat/takeover-9-role` | Kept separate from upstream-fixes because Mayyhem may not want attack roles in the collection. |

When crossing branches to commit multi-branch WIP (e.g. AGENTS.md changes belong on `feat/lab-docs` but a playbook goes on `feat/vsphere-port`), use the stash+switch+commit+switch+pop dance rather than committing everything to whichever branch you happen to be on.

## Ansible-on-Windows via WinRM — operational patterns

These bit us during the slab lab bring-up; codified so nobody repeats them.

- **Always invoke playbooks via `./run.sh <playbook>` from the ansible directory.** Bare `ansible` / `ansible-playbook` routes WinRM traffic through the corp outbound proxy (`corp-proxy.example:8080`) and times out with `Read timed out`. The wrapper prepends RFC1918 CIDRs to `NO_PROXY`. For ad-hoc `ansible` commands, set `NO_PROXY='10.0.0.0/8,172.16.0.0/12,192.168.0.0/16' no_proxy=…` inline.
- **Every `win_powershell` task runs in a fresh PowerShell session.** The ConfigMgr module's PSDrive is NOT auto-registered by `Import-Module`. Every task that calls a CM cmdlet must first:
  ```powershell
  Import-Module "$env:SMS_ADMIN_UI_PATH\ConfigurationManager.psd1" -ErrorAction Stop
  if (-not (Get-PSDrive -Name <SC> -PSProvider CMSite -ErrorAction SilentlyContinue)) {
    $mp = (Get-ItemProperty 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\ConfigMgr10\AdminUI\Connection' -Name Server).Server
    New-PSDrive -Name <SC> -PSProvider CMSite -Root $mp -Scope Script | Out-Null
  }
  Set-Location "<SC>:\"
  ```
  Skip this and cmdlets fail with `"cannot be run from the current drive"` — often silently, because ansible flags it as `changed=true` while the underlying PowerShell exception is buried.
- **Server 2022 templates run Windows PowerShell 5.1**, not PS Core. Null-conditional operator (`?.`), pipeline chain operators (`&&`/`||`), and PS7-only cmdlets fail. Use `if ($obj.PSObject.Properties['X']) { $obj.PSObject.Properties['X'].Value }` and old-style `Invoke-*` fallbacks.
- **`ansible.windows.win_service` returns `state: running`**, not `state: started`. `failed_when: sms.state != 'started'` is always-true. Use `!= 'running'`.
- **Multi-line PowerShell in `ansible` ad-hoc is a syntax-quoting nightmare.** Anything beyond a single line: write a probe playbook file, run it with `./run.sh`. Faster and reliable.
- **PowerShell here-strings (`@"..."@`) confuse YAML's block scalar parser.** In `win_powershell.script:` blocks, prefer single-line quoted PowerShell strings or compact `+`-concatenated strings over here-strings.
- **`vars: "{{ some_dict_var }}"` at task scope is not valid Ansible YAML.** Use YAML anchors (`vars: &elevated { … }`, later `vars: *elevated`) or duplicate the `become_*` block per task.

## Windows guest-customization false-negative recovery

Terraform's first `apply` against this vCenter reports `Virtual machine customization failed: timeout waiting for customization to complete` for every Windows VM even when customization actually succeeded — vSphere just doesn't emit the completion signal within terraform's 10-min poll on our datacenter. Same shape `VSPHERE_PORT_PLAN.md` flags for Linux GOSC.

Recovery:

1. `./run.sh 00_connectivity.yml` — if all VMs answer `win_ping`, customization did succeed.
2. `terraform untaint 'vsphere_virtual_machine.<name>["<key>"]'` for each VM in state.
3. `terraform plan` should show `No changes` afterward. That's the safe state.

**Never re-apply while VMs are tainted — they'll be destroyed and recreated.** Do not touch `customize.timeout` in `vms.tf` (it's ForceNew — changing it triggers destroy+recreate on every existing VM in state).

## SCCM in-place upgrade patterns

Full write-up: `docs/small-latest-lab-plan.md`, sections "First in-place upgrade" and "2603 upgrade attempt". Highlights that would otherwise bite a fresh session:

- **Baseline install lands on 2403** (`prep_siteserver` role default; slab's `group_vars/all/main.yml` documents *why* we don't override the URL). Path to newer versions is in-console upgrade via `Install-CMSiteUpdate`, driven by `vsphere/small-lab/ansible/60_upgrade_sccm.yml`.
- **Disk space is the #1 prereq blocker.** Server 2022 template ships with ~60 GB C:; terraform grows the VMDK but Windows doesn't auto-extend the partition. `vsphere/small-lab/ansible/11_grow_partitions.yml` does the `Resize-Partition` on every deploy — not optional.
- **Install-CMSiteUpdate upgrades the site but not the console.** Post-upgrade `New-PSDrive` fails with `SiteVersionMismatch` until `C:\Program Files\Microsoft Configuration Manager\tools\ConsoleSetup\ConsoleSetup.exe /q` runs. The playbook does this automatically in a post-install task; it verifies with a fresh `New-PSDrive` before reporting success.
- **`-IgnorePrereqWarning` is required for stricter baselines.** 2509 tolerated site-server prereq WARNINGS implicitly; 2603 refuses to proceed until they're either fixed or the flag is set. Playbook default is `slab_upgrade_ignore_prereq_warning: true` (variable-controllable).
- **SCCM state codes on `SMS_CM_UpdatePackages.State`** (empirically verified 2026-09-10): 65538=Downloading, 131075=Downloaded, 196607=PrereqFailed, 196609=Installing, 196612=Installed, 262146=NewestApplicable (install candidate), 327682=OlderApplicable. `StateName` comes back null on this baseline — do not filter on it.
- **`Install-CMSiteUpdate` is not restartable via cmdlet.** Once SCCM's state machine has attempted install on a pack, re-firing the cmdlet is a no-op even with all flags. Recovery is to RDP + right-click "Install Update Pack" in the console, or to wait for a superseding baseline. See the "2603 upgrade attempt" section of the plan doc for the specific case that hit this and the diagnostic pattern (empty inbox, quiet hman, state stuck at Downloaded).

## Long-running background job monitoring

Applies to SCCM installs, VM provisioning, anything that runs 15+ min:

- **Do not kick off a long job and immediately hand off with "waiting for notification".** Actively probe within 15-20 min of start to verify PROGRESS, not just presence. State code changed? Log tail advanced? CPU / disk delta?
- **If two consecutive probes show the same non-terminal state, investigate.** Passive-observe-stuck-state for hours is worse than useless. For SCCM: state stuck at `131075` (Downloaded) > 15 min means CMUpdate refused the install; read `CMUpdate.log` and `hman.log` for "Setup will not continue" / "WARNING" lines.
- **A `WATCH_STATUS: IN_PROGRESS` message emitted every 5 min for an hour with identical values is silence, not progress.** Kill the watch and diagnose.
