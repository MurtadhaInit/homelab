resource "proxmox_virtual_environment_download_file" "windows_server_iso" {
  content_type   = "iso"
  datastore_id   = var.pve_storage
  node_name      = var.pve_hostname
  upload_timeout = 1200

  # The ISO for the latest Windows Server 2025 - from MAS: https://massgrave.dev/windows-server-links
  url                = "https://oemsoc.download.prss.microsoft.com/dbazure/X23-81958_26100.1742.240906-0331.ge_release_svc_refresh_SERVER_OEMRET_x64FRE_en-us.iso_909fa35d-ba98-407d-9fef-8df76f75e133?t=34b8db0f-439b-497c-86ce-ec7ceb898bb7&P1=102816956391&P2=601&P3=2&P4=pG1WoVpBKlyWcmfj%2bt1gYgkTsP4At28ch8mG7vIQm%2fT4elz5v2ZQ3eKAN8%2fFjb1yaa4npBaABURtnI8YmrDv8p0VJmYpLCIUQ0FHEFR4IFiPgtvzwAAI8oNdiEl%2b2uM7MN8Gaju8BvIVgHRl%2fRxq0HFgrFoEGmvHZU4jY0RFsYAaHliUinDUzdVfT0IPwyWqNUJXZTSfguyphv8XZx8OQsBy3zwBp7tNHsKl36ZO2JdZK%2fyPY7QTpAr5ccazUPEa40ALhYRBJXxlQb1F0OeO7kHhW7DKK5D4Wpt5WbpjFn8MqcZBX3%2fQI6WAwzDSKIck7jYL7bYdl2ufoMRrFZrxxw%3d%3d"
  file_name          = "windows-server-2025.iso"
  checksum           = "854109e1f215a29fc3541188297a6ca97c8a8f0f8c4dd6236b78dfdf845bf75e"
  checksum_algorithm = "sha256"
  overwrite          = false

  lifecycle {
    enabled = false
  }
}

resource "proxmox_virtual_environment_download_file" "windows_virtio_drivers" {
  content_type   = "iso"
  datastore_id   = var.pve_storage
  node_name      = var.pve_hostname
  upload_timeout = 2700

  # See: https://pve.proxmox.com/wiki/Windows_VirtIO_Drivers and https://github.com/virtio-win/virtio-win-pkg-scripts/blob/master/README.md
  # The URL for the stable build of the virtIO drivers for Windows - version 0.1.271
  url       = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.271-1/virtio-win.iso"
  overwrite = false

  lifecycle {
    enabled = false
  }
}

resource "proxmox_virtual_environment_vm" "windows-server" {
  name        = "windows-server"
  description = "A Windows Server VM for when Windows apps are needed"
  tags        = ["terraform"]
  node_name   = var.pve_hostname
  vm_id       = 700
  on_boot     = false
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
    enabled        = false
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
