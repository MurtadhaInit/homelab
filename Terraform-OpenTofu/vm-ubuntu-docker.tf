resource "proxmox_virtual_environment_vm" "ubuntu_docker" {
  name        = "ubuntu-docker"
  description = "A VM generated from an Ubuntu cloud image configured with Cloud Init for Docker containers deployment"
  tags        = ["terraform"]
  node_name   = var.pve_hostname
  vm_id       = 600
  on_boot     = true
  started     = true

  memory {
    dedicated = 2048
    floating  = 0 # disables "ballooning device"
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
    datastore_id = "local-lvm"
    interface    = "scsi0"
    discard      = "on"
    iothread     = true
    ssd          = true
    size         = 40
    file_id      = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    # file_format = "raw" # what will be applied anyways
  }

  # for 'Console' display
  serial_device {
    device = "socket"
  }
  vga {
    type = "std"
    # type = "serial0"
    # clipboard = "vnc"
  }

  # cdrom {
  # enabled = true
  # interface = "ide3" # this is already the default
  # file_id = "none"
  # }

  scsi_hardware = "virtio-scsi-single"

  # boot from the CD ROM by default first then the disk
  # boot_order = ["ide3", "scsi0"]

  operating_system {
    type = "l26"
  }

  agent {
    # The qemu-guest-agent needs to be installed and running inside the VM
    enabled = true
  }

  initialization {
    # interface = "ide2" # the default interface
    ip_config {
      ipv4 {
        address = var.ubuntu_docker_static_ip
        gateway = var.vm_gateway
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.user_data_cloud_config_docker_vm.id
  }
}

resource "proxmox_virtual_environment_file" "user_data_cloud_config_docker_vm" {
  content_type = "snippets"
  datastore_id = var.pve_storage
  node_name    = var.pve_hostname
  overwrite    = true

  source_raw {
    data = <<-EOF
    #cloud-config
    hostname: ubuntu-docker
    user:
      name: ${var.vm_regular_username}
      gecos: Primary User
      lock_passwd: true
      groups:
        - sudo
      sudo: ALL=(ALL) NOPASSWD:ALL
      shell: /bin/bash
      ssh_authorized_keys:
        - ${trimspace(file(var.vm_ssh_public_key))}
    packages:
        - qemu-guest-agent
    runcmd:
      - systemctl enable qemu-guest-agent
      - systemctl start qemu-guest-agent
      - echo "done" > /tmp/cloud-config.done
    package_update: true
    package_upgrade: true
    package_reboot_if_required: true
    disable_root: true
    ssh_pwauth: false
    EOF

    file_name = "user-data-cloud-config-docker-vm.yaml"
  }
}
