# vSphere terraform for ludus_sccm_mayyhem

Provisions the 13 VMs of Mayyhem's SCCM lab against vSphere, matching the RAM/CPU shape defined in `new-config.yml`. The Ansible collection installs on top; this layer only deals with VM lifecycle.

## Read this before your first apply

- **VM safety rules** are in `../../AGENTS.md`. In particular: never run `terraform destroy` autonomously, and if `terraform plan` shows anything being destroyed or replaced that this module didn't create, stop and check.
- The target vCenter hosts unrelated labs and personal VMs. Isolation depends on two variables being distinct from anything already in the environment:
  - `lab_prefix` — every VM in this module gets named `${lab_prefix}-${hostname}`.
  - `vsphere_folder` — every VM lands in this folder.
- Neither the folder nor VMs with that name prefix should exist before your first apply. If they do, terraform will fail loudly rather than overwrite.

## Prerequisites

1. **Create the target folder in vCenter** with the path you'll set in `vsphere_folder`. This module does not create the folder — that would give the module a way to accidentally delete a folder that contains VMs it doesn't know about.
2. Confirm both templates exist in the target vCenter:
   - Windows Server: matches Mayyhem upstream (Server 2022 — SCCM 2303 doesn't list Server 2025 as supported).
   - Windows 11.
   - Both must have VMware Tools installed, WinRM enabled (HTTP/5985, NTLM), and a known local Administrator password.
3. Confirm the port group and IP range are free — every IP in `vm_ips` must be unused on the network.

## Usage

```bash
cd vsphere/terraform
terraform init

# Always plan first. Read the summary. If anything is being destroyed
# or replaced, STOP and check.
terraform plan -var-file=~/.mayyhem-sccm/vsphere.tfvars -out=plan.tfplan

# After reading the plan output:
terraform apply plan.tfplan
```

## What the plan should look like on a first apply

- 13 `vsphere_virtual_machine.mayyhem_vm[<hostname>]` resources to create.
- Zero destroy or replace lines.
- If you see anything else, stop and read carefully. In particular:
  - `-/+ must be replaced` with the reason being `clone[0].template_uuid` means one of the templates was rebuilt. The lifecycle block should prevent this, but if it does appear, investigate before applying.
  - `destroy` on any resource you didn't just create is not expected — check that no one else has been touching this state file.

## Tearing down

Never run `terraform destroy` in this directory without confirmation from the operator. When it is genuinely time to tear the lab down:

```bash
terraform plan -destroy -var-file=~/.mayyhem-sccm/vsphere.tfvars -out=destroy.tfplan
# Confirm ALL 13 VMs are the mayyhem-sccm-* set and no unrelated VMs are in the plan.
terraform apply destroy.tfplan
```

If the plan wants to destroy more than the 13 VMs this module created, do not apply.

## Files

- `main.tf` — provider block + data sources. Only data-source references are to vCenter objects (datacenter, resource pool, datastore, network) and the two templates. **No data source ever references an existing lab VM by name** — that path would silently make an existing VM part of this state file.
- `variables.tf` — all input variables. No defaults for anything sensitive.
- `locals.tf` — the 13-host structural map (hostnames, RAM, CPU, disk, template family). Matches `new-config.yml` line-for-line.
- `vms.tf` — the single `vsphere_virtual_machine` resource with `for_each` over `locals.vm_config`. Includes `lifecycle.ignore_changes = [clone[0].template_uuid]` so template rebuilds don't mass-replace lab VMs.
- `terraform.tfvars.example` — placeholder values only. Copy to `~/.mayyhem-sccm/vsphere.tfvars` and fill in real values there.
- `README.md` — this file.
