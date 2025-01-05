terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # version = "0.69.0"
    }
  }
}

provider "proxmox" {
  endpoint = var.pve_host_ip
  username = "${var.pve_host_user}@pam"
  password = var.pve_host_pass
  # because self-signed TLS certificate is in use
  insecure = true
  tmp_dir  = "../.tmp/"

  ssh {
    agent    = true
    username = var.pve_host_user
  }
}

variable "pve_host_ip" {
  type        = string
  description = "The Proxmox host endpoint"
}

variable "pve_host_user" {
  type        = string
  description = "The Proxmox host username to be used (PAM user)"
}

variable "pve_host_pass" {
  type        = string
  description = "The Proxmox host user password (PAM user)"
}

variable "pve_hostname" {
  type        = string
  description = "The hostname given for the Proxmox host"
}
