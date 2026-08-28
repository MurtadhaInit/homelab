resource "proxmox_download_file" "ubuntu_cloud_image" {
  provider     = proxmox.node["prox2"]
  content_type = "iso"
  datastore_id = var.pve_hosts["prox2"].storage.files
  node_name    = "prox2"

  # The URL for the latest Ubuntu Server LTS cloud image
  url       = "https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64v3.img"
  overwrite = false
}

resource "proxmox_virtual_environment_vm" "ubuntu_vm" {
  provider    = proxmox.node["prox2"]
  name        = "ubuntu-vm"
  description = "A general-purpose Ubuntu VM from a cloud image for container deployments, remote development, and ad-hoc tasks"
  tags        = ["terraform"]
  node_name   = "prox2"
  vm_id       = 100
  on_boot     = true
  started     = true

  memory {
    dedicated = 6144
    floating  = 2048
  }

  cpu {
    cores = 4
    type  = "host"
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
    # pinned so the cloud-init network config can match on it across rebuilds
    mac_address = var.ubuntu_vm_mac_address
  }

  disk {
    datastore_id = var.pve_hosts["prox2"].storage.disks
    interface    = "scsi0"
    discard      = "on"
    ssd          = true
    iothread     = true
    size         = 40
    file_format  = "raw"
    file_id      = proxmox_download_file.ubuntu_cloud_image.id
  }

  scsi_hardware = "virtio-scsi-single"

  machine = "q35"

  bios = "ovmf"

  efi_disk {
    datastore_id = var.pve_hosts["prox2"].storage.disks
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
    network_data_file_id = proxmox_virtual_environment_file.network_data_cloud_config.id
    user_data_file_id    = proxmox_virtual_environment_file.user_data_cloud_config.id
    datastore_id         = var.pve_hosts["prox2"].storage.disks
  }
}

resource "proxmox_virtual_environment_file" "network_data_cloud_config" {
  provider     = proxmox.node["prox2"]
  content_type = "snippets"
  datastore_id = var.pve_hosts["prox2"].storage.files
  node_name    = "prox2"
  overwrite    = true

  source_raw {
    data = <<-EOF
    network:
      version: 2
      ethernets:
        primary:
          match:
            macaddress: ${lower(var.ubuntu_vm_mac_address)}
          addresses:
            - ${var.ubuntu_vm_static_ip}
          routes:
            - to: default
              via: ${var.vm_gateway}
          nameservers:
            addresses:
              - ${var.vm_gateway}
    EOF

    file_name = "network-data-cloud-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "user_data_cloud_config" {
  provider     = proxmox.node["prox2"]
  content_type = "snippets"
  datastore_id = var.pve_hosts["prox2"].storage.files
  node_name    = "prox2"
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
    # Neither the host nor Ubuntu cloud images carry swap. A swapfile keeps
    # the guest OOM killer off long-lived processes during memory spikes;
    # low swappiness keeps it as just a cushion.
    swap:
      filename: /swapfile
      size: 4G
      maxsize: 4G
    write_files:
      - path: /etc/sysctl.d/99-swappiness.conf
        content: |
          vm.swappiness=10
    runcmd:
      - sysctl --system
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
  value       = var.ubuntu_vm_static_ip
}

output "ubuntu_vm_ssh" {
  description = "SSH connection command for ubuntu-vm VM"
  value       = "ssh -i ${trimsuffix(var.vm_ssh_public_key, ".pub")} ${var.vm_regular_username}@${trimsuffix(var.ubuntu_vm_static_ip, "/24")}"
}
