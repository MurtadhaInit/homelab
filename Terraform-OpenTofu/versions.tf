terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.100.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "2.3.5"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.10.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.8.0"
    }
  }
}
