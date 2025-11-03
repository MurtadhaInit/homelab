# === Proxmox variables ===
variable "pve_host_ip" {
  type        = string
  description = "The Proxmox host endpoint - IP address"
}

variable "pve_host_port" {
  type        = string
  description = "The Proxmox host endpoint - port number"
}

variable "pve_host_user" {
  type        = string
  description = "The Proxmox host username to be used (PAM user)"
}

variable "pve_host_api_token" {
  type        = string
  description = "The Proxmox host API token"
}

variable "pve_hostname" {
  type        = string
  description = "The hostname given for the Proxmox host"
}

# === Shared between various Linux VMs ===
variable "vm_ssh_public_key" {
  type        = string
  description = "The default public SSH key to supply to all VMs"
  default     = "~/.ssh/keys/proxmox-vms.pub"
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

# === vm - ubuntu_docker
variable "ubuntu_docker_static_ip" {
  type        = string
  description = "The static IP address for the core ubuntu VM configured with Docker"
  default     = "10.20.30.41/24"
}
