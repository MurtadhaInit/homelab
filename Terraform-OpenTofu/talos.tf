# =============================================================================
# Talos cluster configuration, bootstrap, and outputs
#
# This file takes the VMs created in vm-talos.tf and turns them into a
# functioning Kubernetes cluster. The flow is:
#
#   1. Generate cluster secrets (PKI, tokens)
#   2. Build machine configs (one per role: controlplane / worker)
#   3. Push configs to each node over the Talos API
#   4. Bootstrap etcd on one control plane node
#   5. Retrieve talosconfig and kubeconfig
#   6. Install Cilium CNI via Helm
#
# After bootstrap, nodes are NotReady (no CNI). Cilium is then installed via
# a Helm release — its pods tolerate the NotReady taint, so they start and
# establish networking. Once Cilium is running, nodes become Ready.
# =============================================================================

# === 1. Cluster secrets ===
# All PKI material for the cluster: etcd CA, Kubernetes CA, machine certs,
# bootstrap tokens, and encryption keys. Created once and stored in state.
resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

# === 2. Machine configurations ===
# The base config for each role. Think of this as the "template" —
# further per-node customizations can be applied as patches in step 3.

data "talos_machine_configuration" "controlplane" {
  talos_version      = var.talos_version
  kubernetes_version = var.k8s_version
  cluster_name       = local.talos_cluster_name
  cluster_endpoint   = local.talos_cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets

  config_patches = [
    yamlencode({
      cluster = {
        # Disable the default Flannel CNI and kube-proxy — Cilium replaces both.
        # Cilium is installed separately via Helm after bootstrap (step 6).
        network = {
          cni = { name = "none" }
        }
        proxy = { disabled = true }
      }

      # Virtual IP shared across control plane nodes for HA.
      # One CP node holds this IP; if it goes down, another takes over.
      machine = {
        network = {
          interfaces = [
            {
              deviceSelector = { busPath = "0*" }
              vip            = { ip = local.talos_cluster_vip }
            }
          ]
        }
      }
    })
  ]
}

data "talos_machine_configuration" "worker" {
  talos_version      = var.talos_version
  kubernetes_version = var.k8s_version
  cluster_name       = local.talos_cluster_name
  cluster_endpoint   = local.talos_cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets

  config_patches = [
    # Longhorn requires the kubelet to bind-mount its data directory.
    # UserVolumeConfig auto-mounts to /var/mnt/<name>, and this propagates
    # it into the kubelet's mount namespace.
    yamlencode({
      machine = {
        kubelet = {
          extraMounts = [
            {
              destination = "/var/mnt/longhorn"
              type        = "bind"
              source      = "/var/mnt/longhorn"
              options     = ["bind", "rshared", "rw"]
            }
          ]
        }
      }
    }),
    # Provision the dedicated Longhorn disk as a user volume.
    # Talos auto-formats, partitions, and mounts it at /var/mnt/longhorn.
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "UserVolumeConfig"
      name       = "longhorn"
      provisioning = {
        diskSelector = {
          match = "!system_disk && disk.transport == 'virtio'"
        }
        minSize = "1GiB"
        grow    = true
      }
    })
  ]
}

# === 3. Apply configs to each node ===

# Pushes the machine config to each node over the Talos gRPC API.
# The provider retries until the node's API becomes reachable after boot.
resource "talos_machine_configuration_apply" "this" {
  for_each = local.talos_nodes

  client_configuration = talos_machine_secrets.this.client_configuration
  machine_configuration_input = (
    each.value.role == "controlplane"
    ? data.talos_machine_configuration.controlplane.machine_configuration
    : data.talos_machine_configuration.worker.machine_configuration
  )
  node = each.value.ip

  # Hostname is set automatically by Proxmox cloud-init (from the VM name)
  # via the NoCloud datasource — no need to set it here.

  depends_on = [proxmox_virtual_environment_vm.talos]

  lifecycle {
    # Re-apply config when the VM is recreated (new ID), not on in-place
    # updates like memory/CPU changes. A new VM boots with no config even
    # though this resource's inputs haven't changed.
    replace_triggered_by = [proxmox_virtual_environment_vm.talos[each.key].id]
  }
}

# === 4. Bootstrap ===
# Initializes etcd on exactly one control plane node. This is what brings the
# cluster to life. Other CP nodes join the etcd cluster automatically once
# their configs are applied. You only ever bootstrap once per cluster.
resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.talos_nodes["talos-cp-1"].ip

  depends_on = [talos_machine_configuration_apply.this]

  lifecycle {
    # Re-bootstrap only when the VM itself is rebuilt from scratch.
    # In-place config changes don't need re-bootstrap.
    replace_triggered_by = [proxmox_virtual_environment_vm.talos["talos-cp-1"]]
  }
}

# === 5. Retrieve configs ===

# talosconfig — needed for `talosctl` to authenticate against the Talos API
data "talos_client_configuration" "this" {
  cluster_name         = local.talos_cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [for name, node in local.talos_nodes : node.ip]
  endpoints            = [for name, node in local.controlplane_nodes : node.ip]
}

# kubeconfig — needed for `kubectl` (and other clients like Flux) to talk to the Kubernetes API
resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.talos_nodes["talos-cp-1"].ip

  depends_on = [talos_machine_bootstrap.this]
}

# === 5a. Write client configs to disk ===
# Automatically written on apply — no manual step needed.
# Paths match the TALOSCONFIG and KUBECONFIG env vars set in mise.toml.
resource "local_sensitive_file" "talosconfig" {
  content  = data.talos_client_configuration.this.talos_config
  filename = "${path.module}/../k8s/talosconfig"
}

resource "local_sensitive_file" "kubeconfig" {
  content  = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename = "${path.module}/../k8s/kubeconfig"
}

# === 6. Cilium CNI (installed via Helm) ===
# Installed as a Helm release after bootstrap. The kube-apiserver uses host
# networking so it's reachable even without a CNI — Helm can talk to it via
# the kubeconfig. Cilium's pods tolerate the NotReady taint, so they start
# on the CNI-less nodes and establish networking.
#
# On a fresh cluster, this resource waits for the kubeconfig to be written
# to disk before attempting to install (via depends_on).

resource "helm_release" "cilium" {
  name       = "cilium"
  namespace  = "kube-system"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = "1.19.2"

  values = [yamlencode({
    ipam = { mode = "kubernetes" }

    # Replaces kube-proxy with eBPF-based routing (we disabled kube-proxy in Talos)
    kubeProxyReplacement = true

    # Enable the Gateway API controller (CRDs installed separately via Flux)
    gatewayAPI = { enabled = true }

    # L2 announcements — respond to ARP on the LAN for LoadBalancer Service IPs,
    # so the Gateway gets a reachable address without an external LB like MetalLB.
    # Paired with CiliumL2AnnouncementPolicy + CiliumLoadBalancerIPPool CRs
    # applied via Flux under k8s/infrastructure/configs/cilium-l2.yaml.
    l2announcements = { enabled = true }
    externalIPs     = { enabled = true }

    # L2 uses leader-election leases, which amplifies API-server traffic.
    # Raise the client rate limit so cilium-agent isn't throttled under load.
    k8sClientRateLimit = { qps = 50, burst = 100 }

    # KubePrism is Talos's local API server proxy running on every node.
    # Cilium needs the API server to start, but without Cilium there's no pod
    # networking to reach it — KubePrism breaks this chicken-and-egg by providing
    # a localhost endpoint that works before the CNI is up.
    k8sServiceHost = "localhost"
    k8sServicePort = 7445

    # Talos already mounts cgroups — tell Cilium not to try
    cgroup = {
      autoMount = { enabled = false }
      hostRoot  = "/sys/fs/cgroup"
    }

    # Talos blocks SYS_MODULE (no kernel module loading from pods),
    # so we explicitly list only the capabilities Cilium actually needs
    securityContext = {
      capabilities = {
        ciliumAgent      = ["CHOWN", "KILL", "NET_ADMIN", "NET_RAW", "IPC_LOCK", "SYS_ADMIN", "SYS_RESOURCE", "DAC_OVERRIDE", "FOWNER", "SETGID", "SETUID"]
        cleanCiliumState = ["NET_ADMIN", "SYS_ADMIN", "SYS_RESOURCE"]
      }
    }
  })]

  depends_on = [local_sensitive_file.kubeconfig]
}
