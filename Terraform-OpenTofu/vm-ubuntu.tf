resource "proxmox_virtual_environment_vm" "ubuntu_vm" {
  name        = "ubuntu-vm"
  description = "An Ubuntu cloud image configured with Cloud Init for containers deployment"
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
    cores = 2
    type  = "host"
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  disk {
    datastore_id = var.pve_storage
    interface    = "scsi0"
    discard      = "on"
    ssd          = true
    iothread     = true
    size         = 10
    file_format  = "qcow2"
    file_id      = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
  }

  scsi_hardware = "virtio-scsi-single"

  machine = "q35"

  bios = "ovmf"

  efi_disk {
    datastore_id = var.pve_storage
    type         = "4m"
  }

  operating_system {
    type = "l26"
  }

  agent {
    # when enabled, qemu-guest-agent needs to be installed and running inside the VM first
    enabled = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = var.ubuntu_vm_static_ip
        gateway = var.vm_gateway
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.user_data_cloud_config.id
    datastore_id      = var.pve_storage
  }
}

resource "proxmox_virtual_environment_file" "user_data_cloud_config" {
  content_type = "snippets"
  datastore_id = var.pve_storage
  node_name    = var.pve_hostname
  overwrite    = true

  source_raw {
    data = <<-EOF
    #cloud-config
    hostname: ubuntu-vm
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
        - podman
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

    file_name = "user-data-cloud-config.yaml"
  }
}

output "ubuntu_vm_ip" {
  description = "IP address of the ubuntu-vm VM"
  value       = proxmox_virtual_environment_vm.ubuntu_vm.initialization[0].ip_config[0].ipv4[0].address
}

output "ubuntu_vm_ssh" {
  description = "SSH connection command for ubuntu-vm VM"
  value       = "ssh -i ~/.ssh/keys/proxmox-vms ${var.vm_regular_username}@${trimsuffix(var.ubuntu_vm_static_ip, "/24")}"
}
