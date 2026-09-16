### vCenter connection ###

variable "vsphere_server" {
  description = "vCenter FQDN or IP. Provide via tfvars."
  type        = string
}

variable "vsphere_user" {
  description = "vCenter username. Provide via tfvars."
  type        = string
}

variable "vsphere_password" {
  description = "vCenter password. Provide via tfvars."
  type        = string
  sensitive   = true
}

variable "vsphere_insecure" {
  description = "Skip TLS verification (true for self-signed / internal CAs)."
  type        = bool
  default     = false
}

### vSphere objects ###

variable "vsphere_datacenter" {
  description = "vCenter datacenter object name."
  type        = string
}

variable "vsphere_resource_pool" {
  description = "Resource pool name (usually 'Resources' for cluster-default)."
  type        = string
  default     = "Resources"
}

variable "vsphere_datastore" {
  description = "Datastore name."
  type        = string
}

variable "vsphere_network" {
  description = "Port group name (dvPortGroup or standard port group)."
  type        = string
}

variable "vsphere_folder" {
  description = "vCenter folder path (e.g. 'Personal/username/slab-sccm-latest'). MUST be distinct from the mayyhem lab folder and any other lab or personal VMs — this is a safety boundary. The folder must already exist; this module does not create it."
  type        = string
}

### Templates ###

variable "vsphere_server_template" {
  description = "Windows Server 2022 template name. Same template mayyhem uses is fine — this module only reads it."
  type        = string
}

### Guest customization / network ###

variable "ipv4_netmask" {
  description = "Netmask in bits (e.g. 22 for a /22)."
  type        = number
}

variable "ipv4_gateway" {
  description = "Default gateway IP."
  type        = string
}

variable "dns_server" {
  description = "DNS server IP. Bootstrap with an upstream resolver (e.g. the network's default), then flip to slab-dc's IP after the DC promotion. Not automated — operator flips it before the domain-join playbook."
  type        = string
}

variable "domain_fqdn" {
  description = "Lab domain FQDN. Default is slab.lab; keep this distinct from mayyhem.com."
  type        = string
  default     = "slab.lab"
}

### Lab identity ###

variable "lab_prefix" {
  description = "Name prefix applied to every VM (e.g. 'slab'). Must not collide with any existing VM name in vCenter — in particular MUST NOT match the mayyhem lab's prefix. vCenter's unique-name constraint enforces this at create time; the validation below is a fast local check."
  type        = string
  default     = "slab"

  validation {
    condition     = length(var.lab_prefix) > 0 && length(var.lab_prefix) <= 10
    error_message = "lab_prefix must be 1..10 chars — long enough to be distinctive, short enough to keep VM names + hostnames under 15 NetBIOS chars when combined with the host suffix (e.g. slab-pss = 8)."
  }
}

variable "local_admin_password" {
  description = "Password to set on the built-in Administrator account during guest customization."
  type        = string
  sensitive   = true
}

### Per-VM IP assignments ###

variable "vm_ips" {
  description = "Map of VM shortname -> IP address. Must have entries for all 3 hosts defined in locals.tf. Provided via tfvars."
  type        = map(string)

  validation {
    condition = alltrue([
      contains(keys(var.vm_ips), "dc"),
      contains(keys(var.vm_ips), "pss"),
      contains(keys(var.vm_ips), "db"),
    ])
    error_message = "vm_ips must contain entries for the 3 slab hosts: dc, pss, db. See locals.tf."
  }
}
