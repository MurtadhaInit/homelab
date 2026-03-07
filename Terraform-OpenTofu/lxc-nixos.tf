resource "proxmox_virtual_environment_container" "nixos" {
  description   = "A NixOS LXC container generated from a Proxmox LXC image template from Hydra"
  tags          = ["terraform", "ansible"]
  node_name     = var.pve_hostname
  vm_id         = 1000
  start_on_boot = true
  started       = true

  unprivileged = false

  console {
    type = "shell"
    # NOTE: password login is disabled by default so 'console' type access is useless
  }

  cpu {
    architecture = "amd64"
    cores        = 4
  }

  memory {
    dedicated = 2048
    swap      = 1024
  }

  initialization {
    hostname = "nixos-ct"

    ip_config {
      ipv4 {
        address = var.nixos_static_ip
        gateway = var.vm_gateway
      }
    }

    # This configures the root user only
    user_account {
      keys = [
        trimspace(file(var.vm_ssh_public_key))
      ]
      password = random_password.nixos_ct_pass.result
    }
  }

  network_interface {
    name   = "eth0" # instead of veth0 because the NixOS LXC container might expect this
    bridge = "vmbr0"
  }

  disk {
    datastore_id = var.pve_storage
    size         = 8
  }

  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.nixos_lxc_proxmox_image.id
    type             = "nixos"
  }

  # Bind mount managed via Ansible (proxmox-nfs.yaml) because API tokens
  # cannot create bind mounts — requires root@pam *password* authentication.
  # mount_point {
  #   volume = "/mnt/media"
  #   path   = "/mnt/media"
  # }
  # features { nesting = true } is also needed for this CT and applied as above for the
  # same reasons.

  lifecycle {
    ignore_changes = [mount_point]
  }
}

resource "random_password" "nixos_ct_pass" {
  length           = 16
  special          = true
  override_special = "_%@"
}

output "nixos_ct_pass" {
  value     = random_password.nixos_ct_pass.result
  sensitive = true
}

output "nixos_ct_ip" {
  description = "IP address of the nixos LXC container"
  value       = proxmox_virtual_environment_container.nixos.initialization[0].ip_config[0].ipv4[0].address
}

output "nixos_ct_ssh" {
  description = "SSH connection command for nixos LXC container"
  value       = "ssh -i ~/.ssh/keys/proxmox-vms root@${trimsuffix(var.nixos_static_ip, "/24")}"
}
