resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.pve_hostname
  url          = var.ubuntu_cloud_image
}

resource "proxmox_virtual_environment_vm" "ubuntu_template" {
  name        = "ubuntu-template"
  description = "Golden template configured with Docker and essential tools"
  node_name   = var.pve_hostname
  vm_id       = 500
  on_boot     = true
  started     = false
  template    = true

  memory {
    dedicated = 2048
    floating  = 0 # disables "ballooning device"
  }

  cpu {
    cores = 2
    numa  = true
    type  = "host"
    # units = 100
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    discard      = "on"
    ssd          = true
    size         = 20
    file_id      = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    # file_format = "raw" # what will be applied anyways
    # iothread = "true"
  }

  serial_device {
    device = "socket"
  }
  vga {
    type = "serial0"
  }

  cdrom {
    enabled = true
  }

  scsi_hardware = "virtio-scsi-pci"

  boot_order = ["scsi0"]

  operating_system {
    type = "l26"
  }

  # ⚠️
  agent {
    enabled = false
  }

  # ⚠️
  initialization {
    # interface = "ide2" # the default interface
    ip_config {
      ipv4 {
        address = "dhcp"
      }
      ipv6 {
        address = "dhcp"
      }
    }
    user_account {
      keys = [trimspace(file(var.vm_ssh_pub_key))]
      # password = random_password.ubuntu_vm_password.result
      username = var.vm_username
      password = var.vm_password
    }
    # user_data_file_id = proxmox_virtual_environment_file.cloud_config.id
  }
}
