resource "proxmox_virtual_environment_apt_standard_repository" "no_sub_repo" {
  handle = "no-subscription"
  node   = var.pve_hostname
}

resource "proxmox_virtual_environment_apt_repository" "no_sub_repo" {
  enabled   = true
  file_path = proxmox_virtual_environment_apt_standard_repository.no_sub_repo.file_path
  index     = proxmox_virtual_environment_apt_standard_repository.no_sub_repo.index
  node      = proxmox_virtual_environment_apt_standard_repository.no_sub_repo.node
}
