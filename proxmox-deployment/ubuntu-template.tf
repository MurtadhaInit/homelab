resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.pve_hostname
  url          = var.ubuntu_cloud_image
}

resource "proxmox_virtual_environment_vm" "ubuntu_template" {
  name        = "ubuntu-template"
  description = "Preconfigured template based on an Ubuntu cloud image"
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

  # for 'Console' display
  serial_device {
    device = "socket"
  }
  vga {
    type = "std"
    # type = "serial0"
    # clipboard = "vnc"
  }

  cdrom {
    enabled = true
    # interface = "ide3" # this is already the default
    # file_id = "none"
  }

  scsi_hardware = "virtio-scsi-pci"

  # boot from the CD ROM by default first then the disk
  # If we decided to add an ISO image to a cloned VM later on
  boot_order = ["ide3", "scsi0"]

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
        address = "dhcp"
      }
      ipv6 {
        address = "dhcp"
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_config_regular.id
  }
}

resource "proxmox_virtual_environment_file" "cloud_init_config_regular" {
  datastore_id = "local"
  content_type = "snippets"
  node_name    = var.pve_hostname
  overwrite    = true

  source_raw {
    data = <<-EOF
    #cloud-config
    hostname: ubuntu-vm
    users:
      - name: ${var.vm_regular_username}
        lock_passwd: false
        passwd: ${data.external.reg_password_hash.result.hash}
        groups:
          - sudo
        shell: /bin/bash
        ssh_authorized_keys:
          - ${trimspace(file(var.vm_ssh_pub_key))}
      - name: ${var.vm_automation_username}
        gecos: Automation User
        lock_passwd: true
        groups:
          - sudo
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/bash
        ssh_authorized_keys:
          - ${trimspace(file(var.vm_ssh_pub_key))}
    packages:
        - qemu-guest-agent
        - net-tools
    runcmd:
      - sudo systemctl enable qemu-guest-agent
      - sudo systemctl start qemu-guest-agent
    package_update: true
    package_upgrade: true
    package_reboot_if_required: true
    disable_root: true
    ssh_pwauth: false
    EOF

    file_name = "regular-user-config.yaml"
  }
}

data "external" "reg_password_hash" {
  # the salt is only provided to guarantee idempotency
  program = ["./utils/hash-password.py", var.vm_regular_password, var.vm_regular_pass_salt]
}
