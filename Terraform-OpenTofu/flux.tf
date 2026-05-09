# =============================================================================
# Flux Operator bootstrap
#
# Installs the flux-operator chart and applies the FluxInstance via an ephemeral
# in-cluster Job. Once Flux is up it self-reconciles flux-instance.yaml from the
# repo, so the operator and FluxInstance are GitOps-managed end-to-end.
#
# The sops-age Secret is seeded through managed_resources.secrets_yaml — the
# bootstrap Job applies it server-side; nothing here lands in git. The key value
# is read from disk at apply time and ends up in tofu state.
#
# Re-bootstrap by bumping `flux_bootstrap_revision` (forces the Job to re-run).
# =============================================================================

module "flux_operator_bootstrap" {
  source  = "controlplaneio-fluxcd/flux-operator-bootstrap/kubernetes"
  version = "0.5.0"

  revision = var.flux_bootstrap_revision

  gitops_resources = {
    instance_yaml = file("${path.module}/../k8s/clusters/homelab/flux-system/flux-instance.yaml")
  }

  managed_resources = {
    secrets_yaml = yamlencode({
      apiVersion = "v1"
      kind       = "Secret"
      metadata = {
        name      = "sops-age"
        namespace = "flux-system"
      }
      type = "Opaque"
      data = {
        "sops-age.agekey" = base64encode(file(pathexpand(var.sops_age_key_path)))
      }
    })
  }

  depends_on = [
    helm_release.cilium,
    local_sensitive_file.kubeconfig,
  ]
}
