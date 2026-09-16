# One resource block for all 3 VMs. for_each keys on the local map's short
# hostname so a rename of one VM never shifts the identity of another.
#
# SAFETY:
# - Every VM name is prefixed with var.lab_prefix. If lab_prefix collides
#   with an existing VM name in vCenter, terraform will refuse to create
#   (vSphere unique-name constraint) rather than overwrite.
# - folder is set on every VM — VMs land in the dedicated lab folder path,
#   never at the datacenter root.
# - lifecycle.ignore_changes = [clone[0].template_uuid] prevents a template
#   rebuild from marking every lab VM for replacement on the next plan.
# - This module's terraform state lives in this directory only. It has no
#   knowledge of the mayyhem lab's state and cannot address a mayyhem VM.
#
# All 3 VMs use the Server 2022 template family: BIOS firmware, secure
# boot off.

resource "vsphere_virtual_machine" "slab_vm" {
  for_each = local.vm_config

  name             = "${var.lab_prefix}-${each.value.hostname}"
  folder           = var.vsphere_folder
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id     = data.vsphere_datastore.datastore.id

  num_cpus  = each.value.cpus
  memory    = each.value.memory_mb
  guest_id  = data.vsphere_virtual_machine.server_template.guest_id
  scsi_type = data.vsphere_virtual_machine.server_template.scsi_type

  # firmware NOT inherited from the source template — defaults to bios
  # unless declared explicitly. Server 2022 template was built BIOS,
  # secure boot off. Do not change without rebuilding the template.
  firmware                = "bios"
  efi_secure_boot_enabled = false

  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.server_template.network_interface_types[0]
  }

  disk {
    label            = "disk0"
    size             = each.value.disk_gb
    thin_provisioned = true
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.server_template.id

    customize {
      windows_options {
        # Include the lab_prefix in the Windows computer name (not just the
        # VM name) so slab's hosts don't collide with mayyhem on NetBIOS
        # names in the shared L2 domain. Mayyhem's DC uses computer name
        # `dc`; slab's DC becomes `slab-dc` here.
        computer_name  = "${var.lab_prefix}-${each.value.hostname}"
        admin_password = var.local_admin_password
        # Windows customization TimeZone ID 110 = W. Europe Standard Time
        # (Amsterdam / Berlin / Oslo / Stockholm). Without this the
        # provider default is 85 (GMT Standard Time, London), one hour
        # behind Oslo in summer. See misc_set_timezone_oslo.yml for the
        # runtime fix on already-deployed VMs.
        time_zone = 110
      }

      network_interface {
        ipv4_address = var.vm_ips[each.key]
        ipv4_netmask = var.ipv4_netmask
      }

      ipv4_gateway    = var.ipv4_gateway
      dns_server_list = [var.dns_server]
      dns_suffix_list = [var.domain_fqdn]
    }
  }

  annotation = "slab: always-on small SCCM lab (${var.lab_prefix}) — separate from mayyhem"

  wait_for_guest_ip_timeout  = 0
  wait_for_guest_net_timeout = 0

  lifecycle {
    ignore_changes = [
      clone[0].template_uuid,
    ]
  }
}

output "vm_summary" {
  description = "Map of short hostname -> {full_name, ip} for the ansible sync step."
  value = {
    for k, vm in vsphere_virtual_machine.slab_vm :
    k => {
      full_name = vm.name
      ip        = vm.default_ip_address
    }
  }
}
