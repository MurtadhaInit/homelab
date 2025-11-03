terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.85.1"
    }
    external = {
      source  = "hashicorp/external"
      version = "2.3.5"
    }
  }
}
