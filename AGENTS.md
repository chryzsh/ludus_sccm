# Agents Guide

Instructions for AI agents working in this fork.

## Repository context

This is a fork of `Mayyhem/ludus_sccm` being extended with a vSphere provider path so the lab can run outside of Ludus/Proxmox. Upstream remains the Ludus/Proxmox-native collection; the vSphere additions live alongside it in a `vsphere/` directory (see `VSPHERE_PORT_PLAN.md`).

- `origin` → `chryzsh/ludus_sccm` (fork, may be public)
- `upstream` → `Mayyhem/ludus_sccm`
- Working branch: `feat/vsphere-port`

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

**Where these values must live instead**: an out-of-tree tfvars file (default location `~/.mayyhem-sccm/vsphere.tfvars`), or ansible group_vars files whose paths are gitignored (see `.gitignore`).

**What CAN be committed**:
- Terraform variable declarations with no defaults, or with generic placeholder defaults (`"CHANGE_ME"`, `"vcenter.example"`, `10.0.0.0/24`).
- README or plan examples that use RFC1918 example blocks (`192.0.2.x`, `198.51.100.x`, `203.0.113.x`) or the documentation-only `example.com` FQDN.
- Ansible role logic and templates — the collection itself is provider-agnostic and safe to publish.

**Before any push to `origin`**:
```
git ls-files -z | xargs -0 grep -lE '<partial-vcenter-fqdn>|<datacenter-token>|<real-ip-prefix>|<port-group-name>' || echo "clean"
```
Replace the tokens with the operator's real values (the operator's local `VSPHERE_PORT_PLAN.local.md` — gitignored — is where those real values are recorded for reference). If any file matches, do not push; move the offending values into the tfvars file and re-scan.

**If a leak happens**: force-push is not enough (mirrors and GitHub caches persist). Rotate the exposed credentials, delete the offending refs from GitHub, and treat the fork as compromised until credentials rotate.

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
- Do all vSphere work on `feat/vsphere-port` (or subordinate branches).
- Collection-level bug fixes that would be useful to upstream should live in commits that touch no vSphere-specific files, so they can be cherry-picked into a PR against `upstream/main` cleanly.
