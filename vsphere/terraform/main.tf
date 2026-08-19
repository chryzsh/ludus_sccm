terraform {
  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "= 2.10.0"
    }
  }
  required_version = ">= 1.6.0"
}

provider "vsphere" {
  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = var.vsphere_insecure
}

data "vsphere_datacenter" "dc" {
  name = var.vsphere_datacenter
}

data "vsphere_resource_pool" "pool" {
  name          = var.vsphere_resource_pool
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_datastore" "datastore" {
  name          = var.vsphere_datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  name          = var.vsphere_network
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Templates: the ONLY VMs referenced via data sources. Never add data sources
# for lab VMs — that path silently makes existing VMs part of this state.
data "vsphere_virtual_machine" "server_template" {
  name          = var.vsphere_server_template
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "workstation_template" {
  name          = var.vsphere_workstation_template
  datacenter_id = data.vsphere_datacenter.dc.id
}
