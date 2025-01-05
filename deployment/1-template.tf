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
    # interface = "ide3" # this is already the default
    # file_id = "none"
  }

  scsi_hardware = "virtio-scsi-pci"

  # boot from the CD ROM by default first then the disk (if we added an ISO image to the VM later on)
  boot_order = ["ide3", "scsi0"]

  operating_system {
    type = "l26"
  }

  agent {
    enabled = true
  }

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
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_config.id
  }
}

resource "proxmox_virtual_environment_file" "cloud_init_config" {
  datastore_id = "local"
  content_type = "snippets"
  node_name    = var.pve_hostname
  overwrite    = true

  source_raw {
    data = <<-EOF
    #cloud-config
    hostname: ubuntu-template
    user:
      name: ${var.vm_username}
      lock_passwd: true
      groups:
        - sudo
      sudo: ALL=(ALL) NOPASSWD:ALL
      shell: /bin/bash
      ssh_authorized_keys:
        - ${trimspace(file(var.vm_ssh_pub_key))}
    # runcmd:
    #     - systemctl enable qemu-guest-agent
    #     - systemctl start qemu-guest-agent
    packages:
        - qemu-guest-agent
        - net-tools
    package_update: true
    package_upgrade: true
    package_reboot_if_required: true
    disable_root: true
    ssh_pwauth: false
    EOF

    file_name = "ubuntu-cloud-user-data-cloud-config.yaml"
  }
}
