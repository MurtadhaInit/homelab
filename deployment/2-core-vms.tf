resource "proxmox_virtual_environment_vm" "core_ubuntu_docker" {
  name        = "core-ubuntu-docker"
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
        address = var.vm_static_ip
        gateway = var.vm_gateway_ip
      }
    }
  }
  # timeout_start_vm = 80000
}
