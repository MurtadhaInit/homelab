variable "pve_host_ip" {
  type = string
}

variable "pve_host_user" {
  type = string
}

variable "pve_host_pass" {
  type = string
}

variable "pve_hostname" {
  type        = string
  description = "The hostname for the primary Proxmox node"
  default     = "prox"
}

variable "ubuntu_cloud_image" {
  type        = string
  description = "The latest LTS minimal Ubuntu server cloud image URL"
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "vm_username" {
  type        = string
  description = "The default username to use on all VMs"
  default     = "murtadha"
}

# TODO: generate a separate key for each VM
variable "vm_ssh_pub_key" {
  type        = string
  description = "The default public SSH key to supply to all VMs"
  default     = "~/.ssh/keys/proxmox-vms.pub"
}

variable "vm_static_ip" {
  type        = string
  description = "The static IP address for the core ubuntu VM with Docker"
}

variable "vm_gateway_ip" {
  type        = string
  description = "The IP address for the default gateway for core ubuntu VM with Docker"
}
