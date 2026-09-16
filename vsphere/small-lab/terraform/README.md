# vSphere terraform for the small always-on SCCM lab (`slab`)

Provisions 3 VMs (`slab-dc`, `slab-pss`, `slab-db`) as a minimal standalone
SCCM primary site, sibling to the mayyhem lab and completely isolated from
its terraform state. See `docs/small-latest-lab-plan.md` for the full plan.

## Read this before your first apply

Same rules as the mayyhem terraform, with an extra emphasis:

- **This module has its own terraform state.** It lives in this directory
  (`vsphere/small-lab/terraform/terraform.tfstate` on a local backend). It
  has zero knowledge of the mayyhem lab's VMs, and cannot address them.
  That's the primary safety property against cross-lab damage.
- **`vsphere_folder`, `lab_prefix`, and `vm_ips` MUST all be distinct** from
  the mayyhem lab's values. vCenter's unique-name constraint enforces
  prefix distinctness; the folder and IPs are your responsibility.
- Never run `terraform destroy` autonomously. If `terraform plan` shows
  anything being destroyed or replaced that this module did not create,
  stop and check — that would indicate someone else has been touching
  this state file.
- If the plan output shows the folder path missing or a template rebuild,
  investigate before applying.

## Prerequisites

1. **Create the target folder in vCenter** with the path you'll set in
   `vsphere_folder`. This module does not create the folder.
2. Confirm the Server 2022 template exists (same one the mayyhem lab uses
   is fine).
3. Confirm the IPs `192.0.2.117-119` (or whatever you set) are free on
   the shared subnet.

## Usage

```bash
cd vsphere/small-lab/terraform
terraform init

# Always plan first. Read the summary. If anything is being destroyed
# or replaced, STOP.
terraform plan -var-file=~/.mayyhem-sccm/slab.tfvars -out=plan.tfplan

# After reading the plan output and confirming it matches expectations:
terraform apply plan.tfplan
```

## What the plan should look like on a first apply

- Exactly **3** `vsphere_virtual_machine.slab_vm[<hostname>]` resources to
  create (`slab_vm["dc"]`, `slab_vm["pss"]`, `slab_vm["db"]`).
- Zero destroy or replace lines.
- Data source reads only against: the datacenter, the resource pool, the
  datastore, the network, and the Server 2022 template.

Anything else is unexpected — stop and read carefully:

- `-/+ must be replaced` with reason `clone[0].template_uuid` means the
  Server 2022 template was rebuilt. The lifecycle block should prevent
  this; if it appears, investigate before applying.
- Any `destroy` line means the state file has been touched by something
  else — do not apply.
- Any VM name outside `slab-{dc,pss,db}` means someone edited `locals.tf`
  or `lab_prefix`; verify that was intentional.

## Cross-lab safety check

Before your first apply, verify that no existing VM in vCenter shares the
`slab-*` name prefix or is in the folder you set for `vsphere_folder`.
`govc find` from the operator's shell can do this quickly:

```bash
govc find vm -name 'slab-*'
govc ls "vm/<your-vsphere_folder-path>"
```

If either command lists results, do not apply until you understand why.

## Tearing down

Never run `terraform destroy` without confirmation from the operator.
When it is genuinely time:

```bash
terraform plan -destroy -var-file=~/.mayyhem-sccm/slab.tfvars -out=destroy.tfplan
# Confirm all listed VMs are slab-{dc,pss,db} and nothing else.
terraform apply destroy.tfplan
```

If the plan wants to destroy anything other than the 3 slab VMs, do not
apply.

## Files

- `main.tf` — provider block + data sources. Only vCenter objects and the
  Server 2022 template are read via data sources.
- `variables.tf` — all input variables. No defaults for anything sensitive.
- `locals.tf` — the 3-host structural map (hostnames, RAM, CPU, disk).
- `vms.tf` — the single `vsphere_virtual_machine.slab_vm` resource with
  `for_each` over `locals.vm_config`. Includes `lifecycle.ignore_changes
  = [clone[0].template_uuid]`.
- `terraform.tfvars.example` — placeholder values only. Copy to a location
  outside the repo and fill in real values there.
- `README.md` — this file.
