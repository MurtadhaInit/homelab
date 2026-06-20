# Proxmox API tokens — one per node, decrypted from the same SOPS files Ansible
# consumes (created & stored by `just pve-token <host>`).
data "sops_file" "pve_host" {
  for_each    = var.pve_hosts
  source_file = "${path.module}/../ansible/inventory/host_vars/${each.value.inventory_host}/proxmox-api-token.sops.yaml"
}

locals {
  # The bpg/proxmox provider wants the full "user@realm!tokenid=secret" form; Ansible
  # composes the same from proxmox_api.user/token_id + this secret. Keyed by node name.
  pve_api_tokens = {
    for name, _ in var.pve_hosts :
    name => "root@pam!automation=${data.sops_file.pve_host[name].data["proxmox_api_token_secret"]}"
  }
}
