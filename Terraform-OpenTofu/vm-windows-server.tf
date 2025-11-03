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
    units = 1024
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
    # interface = "virtio" # maybe this is better, and let the virtio drivers handle the rest?
    interface = "scsi0"
    discard   = "on"
    iothread  = true
    ssd       = true
    size      = 200
    cache     = "writeback"
  }
  cdrom {
    file_id = proxmox_virtual_environment_download_file.windows_server_iso.id
  }
  # NOTE: the current provider doesn't support adding two CD ROMs, so the other needs
  # to be mounted manually later
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

# NOTE: couldn't find a way to set a static IP address for Windows programmatically.
# Set it manually from inside Windows to 10.20.30.42/24

# NOTE:
# 1. Before starting the VM, mount a 2nd CD ROM with the virtio drivers (in v1 of the provider, it'll be possible to mount two CDs)
# 2. During installation load the drivers in the vioscsi folder to recognise the disk
# 3. After installation, install the qemu guest agent (guest-agent directory) and drivers for unrecognised devices (point to the virtio drivers CD to search for drivers). Without those drivers there might not be any internet access.
# - Or... install everything through the installer at the root of the virtio drivers disk
# 4. Activate windows: irm https://get.activated.win | iex
# 5. Enable remote desktop
# 6. Install Windows updates then reserve the IP address of 10.20.30.42 for the machine in the router before restarting (restarting will make the machine release the old IP)
# - Or... set a static IP address in Windows settings (preferred)
# 7. Use winutil: `irm "https://christitus.com/win" | iex` to load the exported settings file. Install apps and apply teaks.
# As Admin: iex "& { $(irm https://christitus.com/win) } -Config [path-to-your-config] -Run"
