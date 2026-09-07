# One resource block for all lab VMs. for_each keys on the local map's
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
#
# Template selection:
#   template_key = "server"      → Windows Server 2022 template  (BIOS)
#   template_key = "workstation" → Windows 11 template           (EFI)
#   template_key = "linux"       → Ubuntu 26.04 template         (EFI)
# Ordering matters below — the linux branch is evaluated first so the
# subsequent Windows ternary still reads naturally for the common case.

locals {
  # Look up the right template data source for a given template_key.
  # This is a small helper that keeps the guest_id / scsi_type / adapter
  # ternaries below from tripling in length. Note the linux template is
  # count-gated (0 or 1), so we index with [0] here — if a "linux" VM is
  # in vm_config but vsphere_linux_template is empty, terraform surfaces
  # a clear "index 0 out of range" error rather than silently misbehaving.
  template_lookup = {
    server      = { id = data.vsphere_virtual_machine.server_template.id,       guest_id = data.vsphere_virtual_machine.server_template.guest_id,       scsi = data.vsphere_virtual_machine.server_template.scsi_type,       nic = data.vsphere_virtual_machine.server_template.network_interface_types[0],       firmware = "bios" }
    workstation = { id = data.vsphere_virtual_machine.workstation_template.id,  guest_id = data.vsphere_virtual_machine.workstation_template.guest_id,  scsi = data.vsphere_virtual_machine.workstation_template.scsi_type,  nic = data.vsphere_virtual_machine.workstation_template.network_interface_types[0],  firmware = "efi"  }
    linux       = length(data.vsphere_virtual_machine.linux_template) > 0 ? { id = data.vsphere_virtual_machine.linux_template[0].id, guest_id = data.vsphere_virtual_machine.linux_template[0].guest_id, scsi = data.vsphere_virtual_machine.linux_template[0].scsi_type, nic = data.vsphere_virtual_machine.linux_template[0].network_interface_types[0], firmware = "bios" } : null
  }
}

resource "vsphere_virtual_machine" "mayyhem_vm" {
  for_each = local.all_vms

  name             = "${var.lab_prefix}-${each.value.hostname}"
  folder           = var.vsphere_folder
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id     = data.vsphere_datastore.datastore.id

  num_cpus  = each.value.cpus
  memory    = each.value.memory_mb
  guest_id  = local.template_lookup[each.value.template_key].guest_id
  scsi_type = local.template_lookup[each.value.template_key].scsi

  # firmware NOT inherited from the source template by
  # data.vsphere_virtual_machine — it defaults to bios/false unless
  # declared explicitly here. A BIOS-firmware clone of an EFI/GPT
  # template will fail to find a bootloader and drop to PXE, and an
  # EFI-firmware clone of a BIOS/MBR template drops straight into the
  # EFI Boot Manager because no EFI loader exists on disk. Set per
  # template family based on how each template was built:
  #   - Windows Server 2022 template: BIOS, secure boot off.
  #   - Windows 11 template: EFI, secure boot off.
  #   - Ubuntu 26.04 template: BIOS (per govc config.firmware=bios).
  firmware                = local.template_lookup[each.value.template_key].firmware
  efi_secure_boot_enabled = false

  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = local.template_lookup[each.value.template_key].nic
  }

  disk {
    label            = "disk0"
    size             = each.value.disk_gb
    thin_provisioned = true
  }

  clone {
    template_uuid = local.template_lookup[each.value.template_key].id

    customize {
      # NOTE on Linux GOSC timeout: cloud-init-based GOSC on Ubuntu
      # 26.04 applies hostname + static IP + DNS correctly, but does
      # not emit the completion signal vSphere expects — so terraform's
      # default 10-min customize.timeout poll times out and taints an
      # otherwise-perfectly-provisioned VM. Do NOT set `timeout` in
      # this block: `customize.timeout` is a ForceNew attribute in the
      # vsphere provider — changing it triggers destroy+recreate on
      # every existing VM in state. Accept the "taint on apply,
      # untaint after verify" ugliness for Linux VMs, or apply Linux
      # VMs via a separate resource block if that becomes tedious.

      # Windows guest customization block — only emitted for Windows
      # template families. Linux uses linux_options below.
      dynamic "windows_options" {
        for_each = each.value.template_key == "linux" ? [] : [1]
        content {
          computer_name  = each.value.hostname
          admin_password = var.local_admin_password
        }
      }

      # Linux guest customization block — only emitted for the linux
      # template family. Requires open-vm-tools installed in the source
      # template (Ubuntu cloud images have it by default).
      #
      # No password is set here: the Ubuntu template ships with an SSH
      # key baked into the initial user (`ubuntu`), and password auth
      # is off at this stage. Ansible enables the studentNN local user
      # and password auth post-boot.
      dynamic "linux_options" {
        for_each = each.value.template_key == "linux" ? [1] : []
        content {
          host_name = each.value.hostname
          domain    = var.domain_fqdn
        }
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
