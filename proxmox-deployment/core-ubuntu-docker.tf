resource "proxmox_virtual_environment_vm" "core_ubuntu_docker" {
  name        = "ubuntu-docker"
  description = "Core VM configured with Docker for deploying containers"
  node_name   = var.pve_hostname
  vm_id       = 600
  started     = true
  clone {
    datastore_id = "local-lvm"
    full         = true
    vm_id        = proxmox_virtual_environment_vm.ubuntu_template.id
  }
  initialization {
    ip_config {
      ipv4 {
        address = var.ubuntu_docker_static_ip
        gateway = var.vm_gateway
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_config_automation.id
  }
  # timeout_start_vm = 80000
}

resource "proxmox_virtual_environment_file" "cloud_init_config_automation" {
  datastore_id = "local"
  content_type = "snippets"
  node_name    = var.pve_hostname
  overwrite    = true

  source_raw {
    data = <<-EOF
    #cloud-config
    hostname: ubuntu-docker
    user:
      name: ${var.vm_automation_username}
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
    package_update: true
    package_upgrade: true
    package_reboot_if_required: true
    disable_root: true
    ssh_pwauth: false
    EOF

    file_name = "automation-user-config.yaml"
  }
}
