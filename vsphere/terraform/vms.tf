# One resource block for all 13 lab VMs. for_each keys on the local map's
# short hostname so a rename of one VM never shifts the identity of another.
#
# SAFETY:
# - Every VM name is prefixed with var.lab_prefix. If lab_prefix collides
#   with an existing VM name in vCenter, terraform will refuse to create
#   (vSphere unique-name constraint) rather than overwrite.
# - folder is set on every VM — VMs land in the dedicated lab folder path,
#   never at the datacenter root.
# - lifecycle.ignore_changes = [clone[0].template_uuid] prevents a template
#   rebuild from marking every lab VM for replacement on the next plan.

resource "vsphere_virtual_machine" "mayyhem_vm" {
  for_each = local.vm_config

  name             = "${var.lab_prefix}-${each.value.hostname}"
  folder           = var.vsphere_folder
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id     = data.vsphere_datastore.datastore.id

  num_cpus  = each.value.cpus
  memory    = each.value.memory_mb
  guest_id  = each.value.template_key == "workstation" ? data.vsphere_virtual_machine.workstation_template.guest_id : data.vsphere_virtual_machine.server_template.guest_id
  scsi_type = each.value.template_key == "workstation" ? data.vsphere_virtual_machine.workstation_template.scsi_type : data.vsphere_virtual_machine.server_template.scsi_type

  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = each.value.template_key == "workstation" ? data.vsphere_virtual_machine.workstation_template.network_interface_types[0] : data.vsphere_virtual_machine.server_template.network_interface_types[0]
  }

  disk {
    label            = "disk0"
    size             = each.value.disk_gb
    thin_provisioned = true
  }

  clone {
    template_uuid = each.value.template_key == "workstation" ? data.vsphere_virtual_machine.workstation_template.id : data.vsphere_virtual_machine.server_template.id

    customize {
      windows_options {
        computer_name  = each.value.hostname
        admin_password = var.local_admin_password
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

  annotation = "ludus_sccm_mayyhem lab (${var.lab_prefix}) — vSphere port"

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
    for k, vm in vsphere_virtual_machine.mayyhem_vm :
    k => {
      full_name = vm.name
      ip        = vm.default_ip_address
    }
  }
}
