variable "ubuntu_cloud_image" {
  type        = string
  description = "The URL for the latest Ubuntu Server LTS minimal cloud image"
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "vm_ssh_pub_key" {
  type        = string
  description = "The default public SSH key to supply to all VMs"
  default     = "~/.ssh/keys/proxmox-vms.pub"
}

variable "vm_gateway" {
  type        = string
  description = "The IP address for the default gateway for core VMs with static IPs"
}

# === Config date for regular Ubuntu VMs ===
variable "vm_regular_username" {
  type        = string
  description = "The username to set for all Ubuntu cloud image VMs by default"
  default     = "murtadha"
}

variable "vm_regular_password" {
  type        = string
  description = "value"
}

# === Config date for automated Ubuntu VMs ===
variable "ubuntu_docker_static_ip" {
  type        = string
  description = "The static IP address for the core ubuntu VM configured with Docker"
}

variable "vm_automation_username" {
  type        = string
  description = "The username to set for all core Ubuntu cloud image VMs by default"
  default     = "automator"
}
