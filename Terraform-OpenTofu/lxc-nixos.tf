resource "proxmox_virtual_environment_container" "nixos" {
  description   = "A NixOS LXC container generated from a Proxmox LXC image template from Hydra"
  tags          = ["terraform"]
  node_name     = var.pve_hostname
  vm_id         = 1000
  start_on_boot = true
  started       = true

  unprivileged = true
  features {
    nesting = true
  }
  
  cpu {
    architecture = "amd64"
    cores = 4
  }
  
  memory {
    dedicated = 2048
    swap = 512
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
      # password = var.vm_regular_password
      password = random_password.nixos_ct_pass.result
    }
  }

  network_interface {
    name   = "veth0"
    bridge = "vmbr0"
  }

  disk {
    datastore_id = "local"
    size         = 4
  }

  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.nixos_lxc_proxmox_image.id
    type = "nixos"
  }

  # mount_point {
  #   # bind mount, *requires* root@pam authentication
  #   volume = "/mnt/bindmounts/shared"
  #   path   = "/mnt/shared"
  #   # mount_options = [  ]
  # }

  # mount_point {
  #   # volume mount, a new volume will be created by PVE
  #   volume = "local-lvm"
  #   size   = "10G"
  #   path   = "/mnt/volume"
  # }

  # mount_point {
  #   # volume mount, an existing volume will be mounted
  #   volume = "local-lvm:subvol-108-disk-101"
  #   size   = "10G"
  #   path   = "/mnt/data"
  # }

  # To reference a mount point volume from another resource, use path_in_datastore:
  # mount_point {
  #   volume = other_container.mount_point[0].path_in_datastore
  #   size   = "10G"
  #   path   = "/mnt/shared"
  # }

  # device_passthrough {
  #   # mode = 
  #   path = 
  # }
}

resource "random_password" "nixos_ct_pass" {
  length = 16
  special = true
  override_special = "_%@" 
}

output "nixos_ct_pass" {
  value = random_password.nixos_ct_pass.result
  sensitive = true
}