# Structural VM map — 3 hosts for the always-on small SCCM lab.
#
# Sensitive per-environment values (IPs, template name, folder) come from
# variables. This file only carries the shape of the lab: hostnames, RAM,
# CPU counts, disk size.
#
# All 3 hosts use the same Server 2022 template. slab-pss colocates the
# management point, distribution point, and SMS provider — a minimal
# standalone primary needs no separate site-system hosts.

locals {
  vm_config = {
    "dc" = {
      hostname  = "dc"
      cpus      = 2
      memory_mb = 4096
      # Template base disk. Do not shrink below the template's disk size —
      # vSphere refuses to clone with a smaller disk than the source.
      disk_gb = 80
    }
    "pss" = {
      # Primary site server. Colocated MP + DP + SMS provider. Content
      # library grows here over time; 200 GiB gives headroom without
      # being excessive.
      hostname  = "pss"
      cpus      = 4
      memory_mb = 8192
      disk_gb   = 200
    }
    "db" = {
      # Site database (SQL Server 2022). SQL data + log files live here;
      # 100 GiB is comfortable for a lab-scale site.
      hostname  = "db"
      cpus      = 4
      memory_mb = 8192
      disk_gb   = 100
    }
  }
}
