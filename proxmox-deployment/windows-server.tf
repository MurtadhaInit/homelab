# resource "proxmox_virtual_environment_file" "windows_server_iso" {
#   content_type = "iso"
#   datastore_id = "local"
#   node_name    = var.pve_hostname

#   # The ISO for the latest Windows Server 2025
#   source_file {
#     file_name = "windows-server-2025.iso"
#     path      = "./files/26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"
#   }
# }

resource "proxmox_virtual_environment_download_file" "windows_server_iso" {
  content_type   = "iso"
  datastore_id   = "local"
  node_name      = var.pve_hostname
  upload_timeout = 1200

  # The ISO for the latest Windows Server 2025 - from MAS: https://massgrave.dev/windows_server_links
  url                = "https://oemsoc.download.prss.microsoft.com/dbazure/X23-81958_26100.1742.240906-0331.ge_release_svc_refresh_SERVER_OEMRET_x64FRE_en-us.iso_909fa35d-ba98-407d-9fef-8df76f75e133?t=34b8db0f-439b-497c-86ce-ec7ceb898bb7&P1=102816956391&P2=601&P3=2&P4=pG1WoVpBKlyWcmfj%2bt1gYgkTsP4At28ch8mG7vIQm%2fT4elz5v2ZQ3eKAN8%2fFjb1yaa4npBaABURtnI8YmrDv8p0VJmYpLCIUQ0FHEFR4IFiPgtvzwAAI8oNdiEl%2b2uM7MN8Gaju8BvIVgHRl%2fRxq0HFgrFoEGmvHZU4jY0RFsYAaHliUinDUzdVfT0IPwyWqNUJXZTSfguyphv8XZx8OQsBy3zwBp7tNHsKl36ZO2JdZK%2fyPY7QTpAr5ccazUPEa40ALhYRBJXxlQb1F0OeO7kHhW7DKK5D4Wpt5WbpjFn8MqcZBX3%2fQI6WAwzDSKIck7jYL7bYdl2ufoMRrFZrxxw%3d%3d"
  file_name          = "X23-81958_26100.1742.240906-0331.ge_release_svc_refresh_SERVER_OEMRET_x64FRE_en-us.iso"
  checksum           = "854109E1F215A29FC3541188297A6CA97C8A8F0F8C4DD6236B78DFDF845BF75E"
  checksum_algorithm = "sha256"
  overwrite          = false
}

resource "proxmox_virtual_environment_download_file" "windows_virtio_drivers" {
  content_type   = "iso"
  datastore_id   = "local"
  node_name      = var.pve_hostname
  upload_timeout = 1200

  # The URL for the most recent build of the virtIO drivers for Windows
  url = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso"
}

resource "proxmox_virtual_environment_vm" "windows-server" {
  name        = "windows-server"
  description = "A Windows Server VM for easy GUI management"
  tags        = ["terraform"]
  node_name   = var.pve_hostname
  vm_id       = 700
  on_boot     = true
  started     = false

  memory {
    dedicated = 4096
  }
  cpu {
    cores = 4
    numa  = true
    type  = "host"
  }
  usb {
    usb3 = true
    # host = "2-2"
    mapping = proxmox_virtual_environment_hardware_mapping_usb.external_hdd.id
  }
  network_device {
    bridge = "vmbr0"
    model  = "virtio"
    # model  = "e1000"
  }
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    discard      = "on"
    iothread     = true
    ssd          = true
    size         = 200
    cache        = "writeback"
  }
  cdrom {
    file_id = proxmox_virtual_environment_download_file.windows_server_iso.id
  }
  # cdrom {
  #   file_id = proxmox_virtual_environment_download_file.windows_virtio_drivers.id
  # }
  # TODO: research why machine type is changed to this (causing a change if unset or "pc")
  machine = "pc-i440fx-9.0"
  operating_system {
    type = "win11"
  }
  scsi_hardware = "virtio-scsi-pci"
  agent {
    enabled = true
  }

  lifecycle {
    ignore_changes = [started]
  }
}

# to use in the initialisation block - but there is no cloudinit for windows, right?
variable "windows_server_static_ip" {
  type        = string
  description = "The static IP address for the Windows Server VM"
  default     = "10.20.30.42/24"
}

# NOTE:
# 1. Before starting the VM, mount a 2nd CD ROM with the virtio drivers (in v1 of the provider, it'll be possible to mount two CDs)
# 2. During installation load the drivers in the vioscsi folder to recognise the disk
# 3. After installation, install the qemu guest agent (guest-agent directory) and drivers for unrecognised devices (point to the virtio drivers CD to search for drivers). Without those drivers there might not be any internet access.
# 4. Activate windows: irm https://get.activated.win | iex
# 5. Enable remote desktop
