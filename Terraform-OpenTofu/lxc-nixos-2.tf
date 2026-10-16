resource "proxmox_virtual_environment_download_file" "nixos_2_lxc_proxmox_image" {
  provider     = proxmox.node["prox2"]
  content_type = "vztmpl"
  datastore_id = var.pve_hosts["prox2"].storage.files
  node_name    = "prox2"

  # NixOS Proxmox LXC template - optionally update with new releases when building fresh CTs.
  # The first deploy (through deploy-rs) replaces the template's system anyway (by switching
  # it to the flake's system), so it only needs to boot and accept SSH (the template's NixOS
  # version doesn't matter).
  url                = "https://hydra.nixos.org/build/320902448/download/1/nixos-image-lxc-proxmox-25.11pre-git-x86_64-linux.tar.xz"
  checksum           = "335a2c2425ec03f3cabd283fb7e9c094f05133b380fd7a919ee3e2e677777350"
  checksum_algorithm = "sha256"
  overwrite          = false
}

resource "proxmox_virtual_environment_container" "nixos_2" {
  provider      = proxmox.node["prox2"]
  description   = "A NixOS LXC container generated from a Proxmox LXC image template from Hydra"
  tags          = ["terraform", "ansible"]
  node_name     = "prox2"
  vm_id         = 1001
  start_on_boot = true
  started       = true

  # Nothing here needs host UIDs (no bind mounts), so it runs unprivileged, which
  # also lets the API token set nesting (in here rather than imperatively via Ansible).
  unprivileged = true
  features {
    nesting = true
  }

  console {
    type = "shell"
    # NOTE: password login is disabled by default so 'console' type access is useless
  }

  cpu {
    architecture = "amd64"
    cores        = 2
  }

  # AdGuard + Tailscale idle at a few hundred MB; the headroom is for deploys,
  # which build on the target.
  memory {
    dedicated = 1024
    swap      = 512
  }

  initialization {
    hostname = "nixos-ct-2"

    ip_config {
      ipv4 {
        address = var.nixos_2_static_ip
        gateway = var.vm_gateway
      }
    }

    # This configures the root user only
    user_account {
      keys = [
        trimspace(file(var.vm_ssh_public_key))
      ]
      password = random_password.nixos_ct_2_pass.result
    }
  }

  network_interface {
    name   = "eth0" # instead of veth0 because the NixOS LXC container might expect this
    bridge = "vmbr0"
  }

  # The btrfs root rather than `storage.disks`: the thin pool is already
  # overprovisioned, and a container rootfs is a btrfs subvolume, free of the CoW
  # fragmentation that keeps VM images off btrfs.
  disk {
    datastore_id = var.pve_hosts["prox2"].storage.files
    size         = 16
  }

  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.nixos_2_lxc_proxmox_image.id
    type             = "nixos"
  }

  # TUN passthrough (for Tailscale) is managed via Ansible: device passthrough
  # requires root@pam *password* authentication.
  lifecycle {
    ignore_changes = [device_passthrough]
  }
}

resource "random_password" "nixos_ct_2_pass" {
  length           = 16
  special          = true
  override_special = "_%@"
}

output "nixos_ct_2_pass" {
  value     = random_password.nixos_ct_2_pass.result
  sensitive = true
}

output "nixos_ct_2_ssh" {
  description = "SSH connection command for the 2nd NixOS LXC container"
  value       = "ssh -i ${trimsuffix(var.vm_ssh_public_key, ".pub")} root@${trimsuffix(var.nixos_2_static_ip, "/24")}"
}
