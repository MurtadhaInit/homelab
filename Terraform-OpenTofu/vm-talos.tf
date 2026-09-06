# === Talos Image Factory ===
# We declare the extensions we want and let the provider generate the schematic + URL

data "talos_image_factory_extensions_versions" "this" {
  talos_version = var.talos_version
  filters = {
    names = [
      "qemu-guest-agent",
      "amd-ucode",       # prox  (AMD Ryzen 5 5600H)
      "intel-ucode",     # prox2 (Intel N150)
      "iscsi-tools",     # for Longhorn
      "util-linux-tools" # for Longhorn
    ]
  }
}

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = data.talos_image_factory_extensions_versions.this.extensions_info.*.name
      }
    }
  })
}

data "talos_image_factory_urls" "this" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  architecture  = "amd64"
  platform      = "nocloud"
}

# Standalone (un-clustered) Proxmox nodes, so the same image has to be downloaded
# on every host that runs Talos.
resource "proxmox_download_file" "talos_image" {
  for_each = local.talos_hosts

  provider     = proxmox.node[each.key]
  content_type = "iso"
  datastore_id = var.pve_hosts[each.key].storage.files
  node_name    = each.key

  # disk_image URL is the .raw.xz image — rename to .img for Proxmox/provider compatibility
  url       = trimsuffix(data.talos_image_factory_urls.this.urls.disk_image, ".xz")
  overwrite = false
  file_name = "talos-nocloud-amd64.img"
}

output "talos_upgrade_image" {
  description = "Installer image URL for `talosctl upgrade`"
  value       = data.talos_image_factory_urls.this.urls.installer
}

# === Talos cluster definition ===
locals {
  talos_cluster_name     = "homelab"
  talos_cluster_vip      = "10.20.30.59"
  talos_cluster_endpoint = "https://${local.talos_cluster_vip}:6443"

  # Hosts that carry Talos VMs.
  # Its own list rather than being derived from talos_nodes below, so the boot image
  # stays staged on a host even while it temporarily has no nodes (e.g. mid-migration).
  # Can't be folded into pve_hosts because of rule 3 of 'provider for_each' (see providers.tf).
  talos_hosts = toset(["prox", "prox2"])

  # Each entry creates a Proxmox VM and a corresponding Talos machine config.
  # Using a map (not a list) so that adding/removing a node doesn't affect others.
  # `host` picks which Proxmox node the VM lands on.
  talos_nodes = {
    "talos-cp-1" = {
      host             = "prox"
      role             = "controlplane"
      ip               = "10.20.30.60"
      vm_id            = 810
      cores            = 2
      memory           = 3072
      disk_gb          = 10
      longhorn_disk_gb = null
    }
    "talos-cp-2" = {
      host             = "prox"
      role             = "controlplane"
      ip               = "10.20.30.61"
      vm_id            = 811
      cores            = 2
      memory           = 3072
      disk_gb          = 10
      longhorn_disk_gb = null
    }
    "talos-cp-3" = {
      host             = "prox2"
      role             = "controlplane"
      ip               = "10.20.30.62"
      vm_id            = 812
      cores            = 2
      memory           = 3072
      disk_gb          = 10
      longhorn_disk_gb = null
    }
    "talos-worker-1" = {
      host             = "prox"
      role             = "worker"
      ip               = "10.20.30.70"
      vm_id            = 820
      cores            = 2
      memory           = 4096
      disk_gb          = 15
      longhorn_disk_gb = 60
    }
    "talos-worker-2" = {
      host             = "prox2"
      role             = "worker"
      ip               = "10.20.30.71"
      vm_id            = 821
      cores            = 4
      memory           = 4096
      disk_gb          = 20
      longhorn_disk_gb = 60
    }
  }

  # Filtered views used by talos.tf to target nodes by role
  controlplane_nodes = { for name, node in local.talos_nodes : name => node if node.role == "controlplane" }
  worker_nodes       = { for name, node in local.talos_nodes : name => node if node.role == "worker" }
}

# === Proxmox VMs ===
# The node's `host` selects the provider instance, the Proxmox node to place the
# VM on, and which datastores its disks land on.
resource "proxmox_virtual_environment_vm" "talos" {
  for_each = local.talos_nodes
  provider = proxmox.node[each.value.host]

  name        = each.key
  description = "Talos Linux ${each.value.role} node"
  tags        = ["terraform", "k8s", each.value.role]
  node_name   = each.value.host
  vm_id       = each.value.vm_id
  on_boot     = true
  started     = true

  bios = "ovmf"

  machine = "q35"

  efi_disk {
    datastore_id = var.pve_hosts[each.value.host].storage.disks
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
    datastore_id = var.pve_hosts[each.value.host].storage.disks
    size         = each.value.disk_gb
    interface    = "scsi0"
    file_format  = "raw"
    ssd          = true
    discard      = "on"
    cache        = "writethrough"
    file_id      = proxmox_download_file.talos_image[each.value.host].id
  }

  # Dedicated Longhorn storage disk (workers only)
  dynamic "disk" {
    for_each = each.value.longhorn_disk_gb != null ? [each.value.longhorn_disk_gb] : []
    content {
      datastore_id = var.pve_hosts[each.value.host].storage.data
      size         = disk.value
      interface    = "scsi1"
      file_format  = "raw"
      ssd          = true
      discard      = "on"
    }
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
    datastore_id = var.pve_hosts[each.value.host].storage.disks
  }

  lifecycle {
    # The file_id is only used at VM creation time (source image to clone).
    # After boot, the disk is independent and Talos upgrades itself via
    # `talosctl upgrade`, not by re-cloning. Ignore changes so that a new
    # schematic (e.g. added extensions) doesn't destroy running nodes.
    ignore_changes = [disk[0].file_id]
  }
}
