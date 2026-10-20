# HAOS's other images are xz-compressed, which Proxmox can't decompress on download, whereas the
# OVA is a plain tar whose disk Proxmox imports directly.
resource "proxmox_download_file" "haos_image" {
  provider     = proxmox.node["prox2"]
  content_type = "import"
  datastore_id = var.pve_hosts["prox2"].storage.files
  node_name    = "prox2"

  # Only seeds the VM's first boot (the Supervisor updates the OS from then on), so bumping this
  # only matters for a freshly created VM.
  url                = "https://github.com/home-assistant/operating-system/releases/download/18.3/haos_ova-18.3.ova"
  checksum           = "938408c5bd0f5fe3a8f10ca0a985d611f5d4e74f9ace12bda33d950a9617ca12"
  checksum_algorithm = "sha256"
  overwrite          = false
  upload_timeout     = 1800 # GitHub release downloads outlast the 10 min default
}

resource "proxmox_virtual_environment_vm" "haos" {
  provider    = proxmox.node["prox2"]
  name        = "haos"
  description = "Home Assistant OS, the Supervisor-managed home automation appliance"
  tags        = ["terraform"]
  node_name   = "prox2"
  vm_id       = 101
  on_boot     = true
  started     = true

  bios = "ovmf"

  machine = "q35"

  efi_disk {
    datastore_id      = var.pve_hosts["prox2"].storage.disks
    type              = "4m"
    pre_enrolled_keys = false # HAOS doesn't support Secure Boot
  }

  memory {
    dedicated = 2048
    floating  = 2048 # equal to dedicated: never shrinks, but the balloon device lets Proxmox see guest usage
  }

  cpu {
    cores = 2
    type  = "host"
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
    # HAOS has no cloud-init, so its address comes from a DHCP reservation on the router for this MAC
    mac_address = var.haos_mac_address
  }

  disk {
    datastore_id = var.pve_hosts["prox2"].storage.disks
    interface    = "scsi0"
    discard      = "on"
    ssd          = true
    iothread     = true
    size         = 32 # HAOS's recommended minimum
    file_format  = "raw"
    import_from  = "${proxmox_download_file.haos_image.id}/home-assistant.vmdk"
  }

  boot_order = ["scsi0"]

  scsi_hardware = "virtio-scsi-single"

  tablet_device = false # only aligns the console pointer, which headless HAOS doesn't need

  operating_system {
    type = "l26"
  }

  agent {
    enabled = true # HAOS ships with qemu-guest-agent
  }

  lifecycle {
    # The image only seeds the disk at creation; HAOS updates itself through its Supervisor.
    ignore_changes = [disk[0].import_from]
  }
}
