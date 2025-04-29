resource "proxmox_virtual_environment_file" "windows_server_iso" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.pve_hostname

  # The ISO for the latest Windows Server 2025
  source_file {
    file_name = "windows-server-2025.iso"
    path      = "./files/26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"
  }
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
    host = "2-2"
  }
  network_device {
    bridge = "vmbr0"
    model  = "e1000"
  }
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    discard      = "on"
    iothread     = true
    ssd          = true
    size         = 64
    cache        = "writeback"
  }
  cdrom {
    file_id = proxmox_virtual_environment_file.windows_server_iso.id
  }
  # cdrom {
  #   file_id = proxmox_virtual_environment_download_file.windows_virtio_drivers.id
  # }
  operating_system {
    type = "win11"
  }
  scsi_hardware = "virtio-scsi-pci"
  agent {
    enabled = true
  }
}

variable "windows_server_static_ip" {
  type        = string
  description = "The static IP address for the Windows Server VM"
  default     = "10.20.30.42/24"
}
