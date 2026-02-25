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

# resource "proxmox_virtual_environment_hardware_mapping_usb" "external_hdd" {
#   comment = "An attached 3.5 inch HDD enclosure through USB3"
#   name    = "external-hdd"

#   map = [
#     {
#       comment = "Inateck ASM1153E"
#       id      = "174c:55aa"
#       node    = var.pve_hostname
#     },
#   ]
# }
