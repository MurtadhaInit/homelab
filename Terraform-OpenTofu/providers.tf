provider "external" {}

provider "talos" {}

provider "sops" {}

# The kubeconfig is written to disk by local_sensitive_file.kubeconfig
# during apply — the helm and kubernetes providers connect lazily when a
# resource is evaluated, by which time the file exists.
provider "helm" {
  kubernetes = {
    config_path = "${path.module}/../k8s/kubeconfig"
  }
}

provider "kubernetes" {
  config_path = "${path.module}/../k8s/kubeconfig"
}

# One provider instance per standalone node, iterated over the host map — a
# non-clustered host's API can't reach the others, so every proxmox resource has
# to pick its instance explicitly via `provider = proxmox.node["<host>"]` (paired
# with `node_name = "<host>"`).
# Provider for_each is an OpenTofu exclusive feature, requiring:
#   1. an alias
#   2. the value must be statically evaluable (e.g. var.pve_hosts comes from .tfvars ✔︎)
#   3. resources must not iterate over this same expression. This is so OpenTofu can
#      still destroy resources in a plan that also removes their provider instance.
provider "proxmox" {
  alias    = "node"
  for_each = var.pve_hosts

  endpoint  = "https://${each.value.ip}:${var.pve_host_port}/"
  api_token = local.pve_api_tokens[each.key]

  # because self-signed TLS certificate is in use
  insecure = true

  ssh {
    agent = true
    # a PAM user with password-less sudo privileges
    username    = var.pve_host_user
    private_key = file(var.pve_host_ssh_key) # when/if the SSH agent is not working
    node {
      name    = each.key
      address = each.value.ip
    }
  }

  # generate a random ID for each VM or Container when the vm_id attribute is not specified
  # this is to guarantee non-conflict of IDs
  random_vm_ids = true
}
