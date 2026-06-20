# === Proxmox variables ===
# Standalone (un-clustered) nodes, each gets its own provider instance + reads its own SOPS API token.
# `inventory_host` selects that node's ansible/inventory/host_vars/<host>/proxmox-api-token.sops.yaml.
variable "pve_hosts" {
  type = map(object({
    ip             = string
    inventory_host = string
  }))
  description = "Proxmox nodes keyed by node name (i.e. hostname) — e.g. prox, prox2"
}

variable "pve_host_port" {
  type        = string
  description = "The Proxmox host endpoint - port number"
}

variable "pve_host_user" {
  type        = string
  description = "The Proxmox host username to be used (PAM user)"
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

variable "pve_secondary_storage" {
  type        = string
  description = "The name of the secondary Proxmox storage (e.g., for disks)"
  default     = "media-lv"
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

# === vm - ubuntu ===
variable "ubuntu_vm_static_ip" {
  type        = string
  description = "The static IP address for the core ubuntu VM configured with Docker"
  default     = "10.20.30.41/24"
}

# === ct - nixos ===
variable "nixos_static_ip" {
  type        = string
  description = "The static IP address for the NixOS LXC container"
  default     = "10.20.30.50/24"
}

# === k8s ===
variable "talos_version" {
  type        = string
  description = "The version of Talos features to use in generated machine configuration"
  default     = "v1.12.6"
}

variable "k8s_version" {
  type        = string
  description = "The version of Kubernetes to use in generated machine configuration"
  default     = "v1.35.2"
}

variable "flux_bootstrap_revision" {
  type        = number
  description = "Bump to force the Flux Operator bootstrap Job to re-run (idempotent re-apply)"
  default     = 1
}

variable "sops_age_key_path" {
  type        = string
  description = "Path to the SOPS age private key file. Seeded into the cluster as Secret/sops-age in flux-system"
  default     = "~/.ssh/keys/sops-age.txt"
  sensitive   = true
}
