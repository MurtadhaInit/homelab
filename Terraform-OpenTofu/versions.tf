terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.95.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "2.3.5"
    }
  }
}
