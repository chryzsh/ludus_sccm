# Compact lab — deployment checklist (pick up later)

What's needed to take this scaffold to a running, attack-ready lab for a
future workshop. Nothing here is done yet; the terraform + config +
docs are written and validated, deployment is not. Work top to bottom.

## 1. Integration branch (bring the plants together)

The plants live on separate feature branches. Make one branch that has
everything, resolve conflicts, don't force:

- [ ] Base: `feat/vsphere-port` (collection roles + terraform module)
- [ ] `feat/compact-lab` (this: compact terraform + ansible + group_vars)
- [ ] `feat/create-dp-loot-share` (CRED-6 role `create_dp_loot_share`)
- [ ] `feat/exec-2-svc-maint` (EXEC-2 Proposal D playbook + the
      `create_script_approver_role` / `add_administrative_user` modules)
- [ ] Confirm the `mayyhem.ludus_sccm` collection on the controller is a
      symlink to this checkout (not a stale copy — see the Proposal D
      test handover; a stale `~/.ansible/collections` copy bit us once).

## 2. Phase playbooks (assemble the pipeline)

`site.yml` is a skeleton. Copy the slab pipeline
(`vsphere/small-lab/ansible/0*_*.yml … 70_verify.yml`) into
`compact-lab/ansible/` and re-target hosts for the compact topology:

- [ ] `00`–`20`, `70`: swap slab-* host names for cl-* (see ansible/README table)
- [ ] `30_prep_site_systems` / `50_install_primary`: target **cl-mecm**,
      co-locating primary + MP + SMS provider (mayyhem splits these —
      this is the main thing to shake out on first run)
- [ ] `40_install_database`: target **cl-sql**; `35_admin_plumbing`
      (add_pss_to_admins) points cl-mecm's machine acct at cl-sql
- [ ] NEW `52_install_dp.yml`: DP + PXE on **cl-dp** (adapt from the
      mayyhem DP install)
- [ ] NEW `54_enroll_client.yml`: ensure **cl-client** enrolls via push

## 3. Environment values

- [ ] `terraform/terraform.tfvars` from the example: vCenter creds,
      templates, folder `sccm-compact-lab`, gateway/DNS
- [ ] **Subnet decision (important — see egress finding):** put the
      compact lab on a subnet you *control end to end*, or set the IPs so
      the egress allow-list can be the **specific lab host IPs**, not a
      whole `/24`. The mayyhem lab's `10.112.0.0/24` is a **shared**
      vCenter network — a `/24` egress allow still lets students reach
      non-lab neighbours on it (e.g. a live host at 10.112.0.111 with
      22/3389 open). Tighten `student_egress_allowed_cidrs` accordingly.
- [ ] `ansible/group_vars/all/local.yml` (secrets, mode 0600) — copy the
      mayyhem lab's and adjust for `compact.lab` / domain admin

## 4. Deploy

- [ ] `terraform init && terraform plan -out=up.tfplan` — REVIEW: 5 VMs
      created, nothing else
- [ ] `terraform apply up.tfplan` (expect the Win11 client's GOSC
      customize-timeout dance — taint/untaint per AGENTS.md)
- [ ] `cd ../ansible && python3 sync_inventory.py` (adapt its group
      structure for cl- hosts — the generated groups must match what the
      collection roles expect: DC, site server, DB, DP, client)
- [ ] `./run.sh site.yml`

## 5. Plants + verify

- [ ] Plants run as part of site.yml (CRED-6 share, EXEC-2 Proposal D)
- [ ] Verify each technique against the live lab using the private ops
      repo's `docs/cred6-exec2-test-handover.md` as the model:
      CRED-1, CRED-2, CRED-6, EXEC-2, ELEVATE-1, TAKEOVER-1
- [ ] **sccm_push enabled vs disabled — deliberate choice:** the base
      build creates it *enabled*. Leave it enabled for a realistic lab
      (relay captures the push account itself → ELEVATE-1). Disable it
      only if you specifically want to force the machine-account fallback
      demo (ELEVATE-2), which is what the mayyhem lab currently shows.

## 6. If hosting students (attacker tier)

- [ ] Add ubuntu attack VMs (reuse the mayyhem `ubuntu_students` locals
      pattern) OR have students run
      `../../ansible/files/install-workshop-tools.sh` on their own boxes
- [ ] Apply `misc_egress_lock_ubuntu_students.yml` to the attack tier
      **with a tightened allow-list** (specific lab IPs, per §3)
- [ ] Hand out the topology map + cheat sheet (post-workshop review
      Proposals A/C)
