provider "external" {}

provider "proxmox" {
  endpoint  = "https://${var.pve_host_ip}:${var.pve_host_port}/"
  api_token = var.pve_host_api_token

  # because self-signed TLS certificate is in use
  insecure = true

  # a directory with enough space when using proxmox_virtual_environment_file
  tmp_dir = "../.tmp/"

  ssh {
    agent = true
    # a PAM user with password-less sudo privileges
    username = var.pve_host_user
    node {
      name    = var.pve_hostname
      address = var.pve_host_ip
    }
    # additional nodes can be added below the same way
  }

  # generate a random ID for each VM or Container when the vm_id attribute is not specified
  # this is to guarantee non-conflict of IDs
  random_vm_ids = true
}
