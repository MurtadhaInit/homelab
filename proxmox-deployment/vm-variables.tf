# === Images ===
resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.pve_hostname

  # The URL for the latest Ubuntu Server LTS minimal cloud image
  url = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

# === Shared between various Linux VMs ===
variable "vm_ssh_public_key" {
  type        = string
  description = "The default public SSH key to supply to all VMs"
  default     = "~/.ssh/keys/proxmox-vms.pub"
}

variable "vm_automation_username" {
  type        = string
  description = "The username to set by default for all Linux VMs"
  default     = "automator"
}

variable "vm_gateway" {
  type        = string
  description = "The IP address for the default gateway for core VMs with static IPs"
  default     = "10.20.30.1"
}

# === Config date for regular users on Linux VMs ===
variable "vm_regular_username" {
  type        = string
  description = "The username to set for all regular Ubuntu cloud image VMs by default"
  default     = "murtadha"
}

variable "vm_regular_password" {
  type        = string
  description = "The password to set for all regular Ubuntu cloud image VMs by default"
  sensitive   = true
}

variable "vm_regular_pass_salt" {
  type        = string
  description = "The password salt to use for all regular Ubuntu cloud image VMs by default"
  sensitive   = true
}

data "external" "reg_password_hash" {
  # the salt is only provided to guarantee idempotency
  program = ["./utils/hash-password.py", var.vm_regular_password, var.vm_regular_pass_salt]
}
