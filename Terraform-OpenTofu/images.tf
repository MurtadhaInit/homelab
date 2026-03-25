resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "iso"
  datastore_id = var.pve_storage
  node_name    = var.pve_hostname

  # The URL for the latest Ubuntu Server LTS minimal cloud image
  url       = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  overwrite = false
}

resource "proxmox_virtual_environment_download_file" "windows_server_iso" {
  content_type   = "iso"
  datastore_id   = var.pve_storage 
  node_name      = var.pve_hostname
  upload_timeout = 1200

  # The ISO for the latest Windows Server 2025 - from MAS: https://massgrave.dev/windows-server-links
  url                = "https://oemsoc.download.prss.microsoft.com/dbazure/X23-81958_26100.1742.240906-0331.ge_release_svc_refresh_SERVER_OEMRET_x64FRE_en-us.iso_909fa35d-ba98-407d-9fef-8df76f75e133?t=34b8db0f-439b-497c-86ce-ec7ceb898bb7&P1=102816956391&P2=601&P3=2&P4=pG1WoVpBKlyWcmfj%2bt1gYgkTsP4At28ch8mG7vIQm%2fT4elz5v2ZQ3eKAN8%2fFjb1yaa4npBaABURtnI8YmrDv8p0VJmYpLCIUQ0FHEFR4IFiPgtvzwAAI8oNdiEl%2b2uM7MN8Gaju8BvIVgHRl%2fRxq0HFgrFoEGmvHZU4jY0RFsYAaHliUinDUzdVfT0IPwyWqNUJXZTSfguyphv8XZx8OQsBy3zwBp7tNHsKl36ZO2JdZK%2fyPY7QTpAr5ccazUPEa40ALhYRBJXxlQb1F0OeO7kHhW7DKK5D4Wpt5WbpjFn8MqcZBX3%2fQI6WAwzDSKIck7jYL7bYdl2ufoMRrFZrxxw%3d%3d"
  file_name          = "windows-server-2025.iso"
  checksum           = "854109e1f215a29fc3541188297a6ca97c8a8f0f8c4dd6236b78dfdf845bf75e"
  checksum_algorithm = "sha256"
  overwrite          = false
}

resource "proxmox_virtual_environment_download_file" "windows_virtio_drivers" {
  content_type   = "iso"
  datastore_id   = var.pve_storage 
  node_name      = var.pve_hostname
  upload_timeout = 1200

  # See: https://pve.proxmox.com/wiki/Windows_VirtIO_Drivers and https://github.com/virtio-win/virtio-win-pkg-scripts/blob/master/README.md
  # The URL for the stable build of the virtIO drivers for Windows
  url = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
}

resource "proxmox_virtual_environment_download_file" "nixos_lxc_proxmox_image" {
  content_type = "vztmpl"
  datastore_id = var.pve_storage 
  node_name    = var.pve_hostname

  # The latest NixOS Proxmox LXC template - Update accordingly for new releases
  url                = "https://hydra.nixos.org/build/320902448/download/1/nixos-image-lxc-proxmox-25.11pre-git-x86_64-linux.tar.xz"
  checksum           = "335a2c2425ec03f3cabd283fb7e9c094f05133b380fd7a919ee3e2e677777350"
  checksum_algorithm = "sha256"
  overwrite          = false
}
