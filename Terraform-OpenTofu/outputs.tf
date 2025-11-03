# === Ubuntu Docker VM ===
output "ubuntu_docker_ip" {
  description = "IP address of the ubuntu-docker VM"
  value       = proxmox_virtual_environment_vm.ubuntu_docker.initialization[0].ip_config[0].ipv4[0].address
}

output "ubuntu_docker_ssh" {
  description = "SSH connection command for ubuntu-docker VM"
  value       = "ssh automator@${trimsuffix(var.ubuntu_docker_static_ip, "/24")}"
}
