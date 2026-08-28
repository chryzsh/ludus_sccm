# Structural VM map — 13 hosts matching Mayyhem's new-config.yml.
#
# Sensitive per-environment values (IPs, template names, folder) come from
# variables. This file only carries the shape of the lab: hostnames, RAM,
# CPU counts, disk size, and which template family each VM uses.
#
# CPU and RAM values match new-config.yml exactly. Do not silently diverge.

locals {
  # Base disk in GB. All VMs share the template's base disk; SCCM installs
  # and content library growth happen inside that disk. If a specific VM
  # needs a larger disk (ps1-lib is the likely candidate for a boost later),
  # override per-VM here.
  default_disk_gb = 80

  vm_config = {
    # ── CAS tier ────────────────────────────────────────────────────────
    "dc" = {
      hostname     = "dc"
      cpus         = 2
      memory_mb    = 4096
      disk_gb      = local.default_disk_gb
      template_key = "server"
    }
    "cas-db" = {
      hostname     = "cas-db"
      cpus         = 4
      memory_mb    = 4096
      disk_gb      = local.default_disk_gb
      template_key = "server"
    }
    "cas-scp" = {
      hostname     = "cas-scp"
      cpus         = 2
      memory_mb    = 2048
      disk_gb      = local.default_disk_gb
      template_key = "server"
    }
    "cas-pss" = {
      hostname     = "cas-pss"
      cpus         = 4
      memory_mb    = 4096
      disk_gb      = local.default_disk_gb
      template_key = "server"
    }
    # ── PS1 tier ────────────────────────────────────────────────────────
    "ps1-db" = {
      hostname     = "ps1-db"
      cpus         = 4
      memory_mb    = 4096
      disk_gb      = local.default_disk_gb
      template_key = "server"
    }
    "ps1-lib" = {
      hostname     = "ps1-lib"
      cpus         = 2
      memory_mb    = 2048
      disk_gb      = local.default_disk_gb
      template_key = "server"
    }
    "ps1-psv" = {
      hostname     = "ps1-psv"
      cpus         = 2
      memory_mb    = 2048
      disk_gb      = local.default_disk_gb
      template_key = "server"
    }
    "ps1-dp" = {
      hostname     = "ps1-dp"
      cpus         = 2
      memory_mb    = 2048
      disk_gb      = local.default_disk_gb
      template_key = "server"
    }
    "ps1-mp" = {
      hostname     = "ps1-mp"
      cpus         = 2
      memory_mb    = 2048
      disk_gb      = local.default_disk_gb
      template_key = "server"
    }
    "ps1-sms" = {
      hostname     = "ps1-sms"
      cpus         = 2
      memory_mb    = 2048
      disk_gb      = local.default_disk_gb
      template_key = "server"
    }
    "ps1-pss" = {
      hostname     = "ps1-pss"
      cpus         = 4
      memory_mb    = 4096
      disk_gb      = local.default_disk_gb
      template_key = "server"
    }
    "ps1-dev" = {
      hostname     = "ps1-dev"
      cpus         = 4
      memory_mb    = 4096
      disk_gb      = local.default_disk_gb
      template_key = "workstation"
    }
    "ps1-sec" = {
      hostname     = "ps1-sec"
      cpus         = 2
      memory_mb    = 4096
      disk_gb      = local.default_disk_gb
      template_key = "server"
    }
    # ── Third-party integration (TAKEOVER-9 lab scenario) ───────────────
    # Not part of Mayyhem's upstream new-config.yml. This VM plays the
    # role of a third-party product's SQL backend that has a linked
    # server pointing at ps1-db with SA credentials. See
    # docs/takeover-9-lab-plan.md for the full design.
    "monitor" = {
      hostname     = "monitor"
      cpus         = 2
      memory_mb    = 4096
      disk_gb      = local.default_disk_gb
      template_key = "server"
    }
  }
}
