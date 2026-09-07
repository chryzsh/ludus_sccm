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
  description = "vCenter folder path (e.g. 'Personal/username/sccm-lab-mayyhem'). MUST be distinct from any other lab or personal VMs — this is a safety boundary."
  type        = string
}

### Templates ###

variable "vsphere_server_template" {
  description = "Windows Server template name (SCCM 2303 baseline requires Server 2022)."
  type        = string
}

variable "vsphere_workstation_template" {
  description = "Windows 11 template name for the client VM."
  type        = string
}

variable "vsphere_linux_template" {
  description = "Ubuntu 26.04 template name for the per-student workshop VMs. Template must have open-vm-tools installed and an SSH key baked into the initial user (auth via key, not password). Set to empty string to skip cloning the linux tier."
  type        = string
  default     = ""
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
  description = "DNS server IP. Set to the lab DC's IP after DC is up; can bootstrap with an upstream resolver."
  type        = string
}

variable "domain_fqdn" {
  description = "Lab domain FQDN (upstream default: mayyhem.com)."
  type        = string
  default     = "mayyhem.com"
}

### Lab identity ###

variable "lab_prefix" {
  description = "Name prefix applied to every VM (e.g. 'mayyhem-sccm'). Must not collide with any existing VM name in vCenter. Enforces safety boundary against overwriting unrelated VMs."
  type        = string

  validation {
    condition     = length(var.lab_prefix) > 0 && length(var.lab_prefix) <= 20
    error_message = "lab_prefix must be 1..20 chars — long enough to be distinctive, short enough to keep VM names + hostnames under 15 NetBIOS chars when combined with the host suffix."
  }
}

variable "local_admin_password" {
  description = "Password to set on the built-in Administrator account during guest customization."
  type        = string
  sensitive   = true
}

### Per-VM IP assignments ###

variable "vm_ips" {
  description = "Map of VM shortname -> IP address. Must have entries for all hosts defined in locals.tf. Provided via tfvars."
  type        = map(string)

  validation {
    condition = alltrue([
      contains(keys(var.vm_ips), "dc"),
      contains(keys(var.vm_ips), "cas-db"),
      contains(keys(var.vm_ips), "cas-scp"),
      contains(keys(var.vm_ips), "cas-pss"),
      contains(keys(var.vm_ips), "ps1-db"),
      contains(keys(var.vm_ips), "ps1-lib"),
      contains(keys(var.vm_ips), "ps1-psv"),
      contains(keys(var.vm_ips), "ps1-dp"),
      contains(keys(var.vm_ips), "ps1-mp"),
      contains(keys(var.vm_ips), "ps1-sms"),
      contains(keys(var.vm_ips), "ps1-pss"),
      contains(keys(var.vm_ips), "ps1-dev"),
      contains(keys(var.vm_ips), "ps1-sec"),
      contains(keys(var.vm_ips), "monitor"),
      contains(keys(var.vm_ips), "ps1-lab"),
      contains(keys(var.vm_ips), "ubuntu-student01"),
      contains(keys(var.vm_ips), "ubuntu-student02"),
      contains(keys(var.vm_ips), "ubuntu-student03"),
      contains(keys(var.vm_ips), "ubuntu-student04"),
      contains(keys(var.vm_ips), "ubuntu-student05"),
      contains(keys(var.vm_ips), "ubuntu-student06"),
      contains(keys(var.vm_ips), "ubuntu-student07"),
      contains(keys(var.vm_ips), "ubuntu-student08"),
      contains(keys(var.vm_ips), "ubuntu-student09"),
      contains(keys(var.vm_ips), "ubuntu-student10"),
      contains(keys(var.vm_ips), "ubuntu-student11"),
      contains(keys(var.vm_ips), "ubuntu-student12"),
    ])
    error_message = "vm_ips must contain entries for all 27 lab hosts (13 SCCM + 1 monitor + 1 ps1-lab + 12 ubuntu-studentNN). See locals.tf for the required keys."
  }
}
