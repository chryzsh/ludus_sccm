# Compact SCCM workshop lab — 5-host VM map.
#
# Role-split but small (see ../README.md): DC+ADCS, a co-located site
# server (primary+MP+provider), site DB, DP+PXE, and one CM-enrolled
# client. `cl-` prefix keeps these distinct from the mayyhem (ps1-/cas-)
# and slab (slab-) hosts sharing the vCenter.
#
# Same module as the mayyhem lab (../../terraform); only this map, the
# vm_ips validation, and the tfvars differ.

locals {
  default_disk_gb = 80

  vm_config = {
    # Domain controller + ADCS. Cert services present for ESC / relay
    # targets alongside the AD role.
    "cl-dc" = {
      hostname     = "cl-dc"
      cpus         = 2
      memory_mb    = 4096
      disk_gb      = local.default_disk_gb
      template_key = "server"
    }
    # Primary site server with MP + SMS provider co-located. The SCCM
    # brain and the relay/coerce target (TAKEOVER-1). Sized up because it
    # carries three roles that the mayyhem lab spreads over ps1-pss /
    # ps1-mp / ps1-sms.
    "cl-mecm" = {
      hostname     = "cl-mecm"
      cpus         = 4
      memory_mb    = 8192
      disk_gb      = local.default_disk_gb
      template_key = "server"
    }
    # Site database (MSSQL). CRED-2 surface (policy/DB secrets) and
    # linked-server target.
    "cl-sql" = {
      hostname     = "cl-sql"
      cpus         = 4
      memory_mb    = 6144
      disk_gb      = local.default_disk_gb
      template_key = "server"
    }
    # Distribution point + PXE. Hosts the CRED-6 loot share.
    "cl-dp" = {
      hostname     = "cl-dp"
      cpus         = 2
      memory_mb    = 4096
      disk_gb      = local.default_disk_gb
      template_key = "server"
    }
    # CM-enrolled Win11 client. CRED-1 (NAA policy) source, coercion
    # source for TAKEOVER-1, EXEC-2 execution target, and where
    # svc_sccm_maint (CRED-6 loot) is local admin.
    "cl-client" = {
      hostname     = "cl-client"
      cpus         = 2
      memory_mb    = 4096
      disk_gb      = local.default_disk_gb
      template_key = "workstation"
    }
  }

  # No per-student attack VMs in the target lab — students attack from
  # their own boxes (see ../../ansible/files/install-workshop-tools.sh)
  # or a small externally-managed jump tier. all_vms is just the targets.
  all_vms = local.vm_config
}
