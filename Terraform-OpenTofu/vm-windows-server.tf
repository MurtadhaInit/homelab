resource "proxmox_virtual_environment_vm" "windows-server" {
  name        = "windows-server"
  description = "A Windows Server VM for when Windows apps are needed"
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
  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }
  disk {
    datastore_id = var.pve_storage
    interface    = "scsi0"
    discard      = "on"
    iothread     = true
    size         = 20 # min required 20GB for Windows updates
  }
  scsi_hardware = "virtio-scsi-single"
  cdrom {
    file_id = proxmox_virtual_environment_download_file.windows_server_iso.id
    interface = "ide0"
  }
  # NOTE: the current provider doesn't support adding two CD ROMs, so the other needs
  # to be mounted manually after VM creation
  # cdrom {
  #   file_id = proxmox_virtual_environment_download_file.windows_virtio_drivers.id
  # }
  machine = "pc-q35-9.0"
  bios = "ovmf"
  efi_disk {
    datastore_id = var.pve_storage
    type = "4m"
  }
  tpm_state {
    datastore_id = var.pve_storage
    version      = "v2.0"
  }
  operating_system {
    type = "win11"
  }
  agent {
    enabled = true
  }
  stop_on_destroy = true

  lifecycle {
    # enabled        = false
    ignore_changes = [started]
  }
}

# NOTE:
# 1. Before starting the VM, mount a 2nd CD ROM with the virtio drivers (in v1 of the provider, it'll be possible to mount two CDs)
# 2. During installation, load the following drivers from the virtio CD:
#    - Disk:    vioscsi\2k25\amd64  (Red Hat VirtIO SCSI pass-through controller)
#    - Network: NetKVM\2k25\amd64   (Red Hat VirtIO Ethernet Adapter)
# 3. After installation, install the qemu guest agent (guest-agent\qemu-ga-x86_64.msi)
#    and VirtIO guest tools (virtio-win-gt-x64.msi) from the driver CD. Restart after.
#    - This installs all remaining drivers (Balloon, etc.).
# 4. Activate windows: irm https://get.activated.win | iex
# 5. Enable remote desktop
# 6. Install Windows updates then reserve the IP address of 10.20.30.42 for the machine in the router before restarting (restarting will make the machine release the old IP)
#    - Or set a static IP address in Windows settings (preferred)
# 7. Use winutil: `irm "https://christitus.com/win" | iex` to load the exported settings file. Install apps and apply tweaks.
# As Admin: iex "& { $(irm https://christitus.com/win) } -Config [path-to-your-config] -Run"
