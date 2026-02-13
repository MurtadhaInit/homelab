# === Ubuntu Docker VM ===
output "ubuntu_docker_ip" {
  description = "IP address of the ubuntu-docker VM"
  value       = proxmox_virtual_environment_vm.ubuntu_docker.initialization[0].ip_config[0].ipv4[0].address
}

output "ubuntu_docker_ssh" {
  description = "SSH connection command for ubuntu-docker VM"
  value       = "ssh automator@${trimsuffix(var.ubuntu_docker_static_ip, "/24")}"
}

# === NixOS LXC Container ===
output "nixos_ct_ip" {
  description = "IP address of the nixos LXC container"
  value       = proxmox_virtual_environment_container.nixos.initialization[0].ip_config[0].ipv4[0].address
}

output "nixos_ct_ssh" {
  description = "SSH connection command for nixos LXC container"
  value       = "ssh -i ~/.ssh/keys/proxmox-vms root@${trimsuffix(var.nixos_static_ip, "/24")}"
}
