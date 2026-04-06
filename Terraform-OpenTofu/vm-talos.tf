# === Talos cluster definition ===
locals {
  talos_cluster_name     = "homelab"
  talos_cluster_vip      = "10.20.30.59"
  talos_cluster_endpoint = "https://${local.talos_cluster_vip}:6443"

  # Each entry creates a Proxmox VM and a corresponding Talos machine config.
  # Using a map (not a list) so that adding/removing a node doesn't affect others.
  talos_nodes = {
    "talos-cp-1" = {
      role    = "controlplane"
      ip      = "10.20.30.60"
      vm_id   = 810
      cores   = 2
      memory  = 2048
      disk_gb = 10
    }
    "talos-cp-2" = {
      role    = "controlplane"
      ip      = "10.20.30.61"
      vm_id   = 811
      cores   = 2
      memory  = 2048
      disk_gb = 10
    }
    "talos-cp-3" = {
      role    = "controlplane"
      ip      = "10.20.30.62"
      vm_id   = 812
      cores   = 2
      memory  = 2048
      disk_gb = 10
    }
    "talos-worker-1" = {
      role    = "worker"
      ip      = "10.20.30.70"
      vm_id   = 820
      cores   = 1
      memory  = 1024
      disk_gb = 10
    }
    "talos-worker-2" = {
      role    = "worker"
      ip      = "10.20.30.71"
      vm_id   = 821
      cores   = 1
      memory  = 1024
      disk_gb = 10
    }
  }

  # Filtered views used by talos.tf to target nodes by role
  controlplane_nodes = { for name, node in local.talos_nodes : name => node if node.role == "controlplane" }
  worker_nodes       = { for name, node in local.talos_nodes : name => node if node.role == "worker" }
}

# === Proxmox VMs ===
resource "proxmox_virtual_environment_vm" "talos" {
  for_each = local.talos_nodes

  name        = each.key
  description = "Talos Linux ${each.value.role} node"
  tags        = ["terraform", "k8s", each.value.role]
  node_name   = var.pve_hostname
  vm_id       = each.value.vm_id
  on_boot     = true
  started     = true

  bios = "ovmf"

  machine = "q35"

  efi_disk {
    datastore_id = var.pve_storage
    type         = "4m"
  }

  memory {
    dedicated = each.value.memory
    floating  = 0 # disables ballooning — Talos doesn't support it
  }

  cpu {
    cores   = each.value.cores
    type    = "host" # best performance but no live VM migration
    sockets = 1
    # units   = 1024
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  disk {
    datastore_id = var.pve_storage
    size         = each.value.disk_gb
    interface    = "scsi0"
    file_format  = "raw"
    ssd          = true
    discard      = "on"
    cache        = "writethrough"
    file_id      = proxmox_download_file.talos_image.id
  }

  scsi_hardware = "virtio-scsi-pci" # VirtIO SCSI - since VirtIO SCSI Single is unsupported by Talos

  operating_system {
    type = "l26"
  }

  agent {
    enabled = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = var.vm_gateway
      }
    }
    datastore_id = var.pve_storage
  }
}
