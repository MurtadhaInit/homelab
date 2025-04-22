terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # version = "0.76.0"
    }
    external = {
      source = "hashicorp/external"
      # version = "2.3.4"
    }
  }
}

provider "external" {}

provider "proxmox" {
  endpoint = "https://${var.pve_host_ip}:${var.pve_host_port}/"
  username = "${var.pve_host_user}@pam"
  password = var.pve_host_pass

  # because self-signed TLS certificate is in use
  insecure = true

  # a directory with enough space when using proxmox_virtual_environment_file
  tmp_dir = "../.tmp/"

  ssh {
    agent = true
    # a PAM user with password-less sudo privileges
    username = var.pve_host_user
    node {
      name    = var.pve_hostname
      address = var.pve_host_ip
    }
    # additional nodes can be added below the same way
  }

  # generate a random ID for each VM or Container when the vm_id attribute is not specified
  # this is to guarantee non-conflict of IDs
  random_vm_ids = true
}

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

variable "pve_host_pass" {
  type        = string
  description = "The Proxmox host user password (PAM user)"
}

variable "pve_hostname" {
  type        = string
  description = "The hostname given for the Proxmox host"
}
