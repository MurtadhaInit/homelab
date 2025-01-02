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
    # private_key = file("./keys/proxmox-hosts-automation")
  }
}
