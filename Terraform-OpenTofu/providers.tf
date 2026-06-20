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

# One provider instance per standalone node — there is intentionally NO default, so
# every proxmox resource must name its node explicitly via `provider = proxmox.<node>`
# (paired with `node_name = "<node>"`). A non-clustered host's API can't reach the others.
provider "proxmox" {
  alias     = "prox"
  endpoint  = "https://${var.pve_hosts["prox"].ip}:${var.pve_host_port}/"
  api_token = local.pve_api_tokens["prox"]

  # because self-signed TLS certificate is in use
  insecure = true

  ssh {
    agent = true
    # a PAM user with password-less sudo privileges
    username    = var.pve_host_user
    private_key = file(var.pve_host_ssh_key) # when/if the SSH agent is not working
    node {
      name    = "prox"
      address = var.pve_hosts["prox"].ip
    }
  }

  # generate a random ID for each VM or Container when the vm_id attribute is not specified
  # this is to guarantee non-conflict of IDs
  random_vm_ids = true
}

provider "proxmox" {
  alias     = "prox2"
  endpoint  = "https://${var.pve_hosts["prox2"].ip}:${var.pve_host_port}/"
  api_token = local.pve_api_tokens["prox2"]
  insecure  = true

  ssh {
    agent       = true
    username    = var.pve_host_user
    private_key = file(var.pve_host_ssh_key)
    node {
      name    = "prox2"
      address = var.pve_hosts["prox2"].ip
    }
  }

  random_vm_ids = true
}
