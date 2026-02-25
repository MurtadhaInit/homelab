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

variable "pve_host_ssh_key" {
  type        = string
  description = "The path to the private SSH key to use when connecting to Proxmox hosts"
  default     = "~/.ssh/keys/proxmox-hosts"
}

variable "pve_storage" {
  type        = string
  description = "The name of storage I'm using for *everything*: VM and container disks, ISOs, snippets...etc"
  default     = "local"
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

# === Common users in VMs and Containers ===
variable "vm_regular_username" {
  type        = string
  description = "The regular username to set for all VMs and containers by default"
  default     = "murtadha"
}

# === vm - ubuntu_docker
variable "ubuntu_docker_static_ip" {
  type        = string
  description = "The static IP address for the core ubuntu VM configured with Docker"
  default     = "10.20.30.41/24"
}

# === ct - nixos
variable "nixos_static_ip" {
  type        = string
  description = "The static IP address for the NixOS LXC container"
  default     = "10.20.30.50/24"
}
