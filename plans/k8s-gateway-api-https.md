# Kubernetes Gateway API with HTTPS via Cilium and cert-manager

Expose Kubernetes services on the LAN with trusted HTTPS certificates using
Cilium's Gateway API implementation, cert-manager with Let's Encrypt, and
Cloudflare DNS-01 validation. One Gateway IP, hostname-based routing.

## Rationale

Services in the cluster (starting with the Longhorn UI) need to be accessible
from the LAN without `kubectl port-forward`. The cluster already has Cilium
with Gateway API enabled and the Gateway API CRDs installed — what's missing is
a LoadBalancer IP mechanism, TLS certificates, and the actual Gateway/HTTPRoute
resources.

This mirrors the existing Caddy + Cloudflare DNS-01 setup on `nixos-ct`
(`home.murtadha.dev`) but lives natively in Kubernetes under a separate
subdomain: `k8s.murtadha.dev`.

## Current State

```
Cilium CNI (Gateway API controller enabled, CRDs installed)
No LoadBalancer IP allocation mechanism
No cert-manager
No Gateway or HTTPRoute resources
Longhorn UI only accessible via kubectl port-forward
```

## Target State

```
                  *.k8s.murtadha.dev
                         │
                    DNS (Cloudflare)
                    A → 10.20.30.80
                         │
              Cilium L2 announcement
              (ARP on LAN for .80)
                         │
                   ┌─────┴─────┐
                   │  Gateway   │  10.20.30.80:443
                   │  (TLS)    │  cert from Let's Encrypt
                   └─────┬─────┘
                         │
            ┌────────────┼────────────┐
            │            │            │
    longhorn.k8s.   <future>.k8s.   ...
    murtadha.dev    murtadha.dev
            │            │
    HTTPRoute →     HTTPRoute →
    longhorn-       <future>-
    frontend:80     service:port
```

## IP Addressing

| Address       | Role                                             |
|---------------|--------------------------------------------------|
| 10.20.30.80   | Gateway LoadBalancer IP (Cilium L2 announcement) |

Only one IP is needed. All services share it via hostname-based routing.
The IP pool is defined as a single address (`10.20.30.80/32`) but can be
expanded later if additional Gateways are needed.

## Components to Deploy

### 1. Cilium L2 Announcement Policy and IP Pool

These are Cilium CRDs — no new Helm chart needed. Deploy as a Flux-managed
YAML file alongside the existing `gateway-api-crds.yaml`.

**Note:** Cilium must have L2 announcements enabled. This requires adding
`l2announcements.enabled: true` and `externalIPs.enabled: true` to the Cilium
Helm values in `Terraform-OpenTofu/talos.tf`. After changing Cilium values, run
`tofu apply` — the Helm release will update Cilium in-place.

```yaml
# CiliumL2AnnouncementPolicy — tells Cilium to respond to ARP for LB IPs
apiVersion: cilium.io/v2alpha1
kind: CiliumL2AnnouncementPolicy
metadata:
  name: default-l2-policy
spec:
  # Announce from all interfaces on all nodes
  nodeSelector:
    matchLabels: {}
  interfaces:
    - ^eth[0-9]+
  externalIPs: true
  loadBalancerIPs: true
---
# CiliumLoadBalancerIPPool — the IP range Cilium can assign
apiVersion: cilium.io/v2alpha1
kind: CiliumLoadBalancerIPPool
metadata:
  name: default-pool
spec:
  blocks:
    - cidr: 10.20.30.80/32
```

**File:** `k8s/clusters/homelab/cilium-l2.yaml`

### 2. cert-manager (via Flux HelmRelease)

cert-manager handles certificate issuance and renewal from Let's Encrypt.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: cert-manager
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: jetstack
  namespace: cert-manager
spec:
  interval: 12h
  url: https://charts.jetstack.io
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: cert-manager
  namespace: cert-manager
spec:
  interval: 1h
  chart:
    spec:
      chart: cert-manager
      version: "<check latest stable>"
      sourceRef:
        kind: HelmRepository
        name: jetstack
  values:
    crds:
      enabled: true
```

**File:** `k8s/clusters/homelab/cert-manager.yaml`

### 3. Cloudflare API Token Secret

cert-manager needs the Cloudflare API token to solve DNS-01 challenges. This
is the same token type used by Caddy on `nixos-ct` (Zone:DNS:Edit permission).

**Secret management options (pick one):**

- **SOPS with Flux** (recommended) — Flux has native SOPS decryption support.
  Encrypt the secret with age or GPG, commit the encrypted YAML to the repo,
  and Flux decrypts it on apply. This keeps everything in Git.
- **Sealed Secrets** — similar concept, uses a cluster-side controller.
- **Manual creation** — `kubectl create secret` outside of Git. Simplest to
  start, but not GitOps.

Regardless of method, the resulting Secret must look like:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token
  namespace: cert-manager
type: Opaque
stringData:
  api-token: "<cloudflare-api-token>"
```

### 4. ClusterIssuer for Let's Encrypt

A cluster-wide issuer that any Gateway/Certificate can reference.

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: "<email>"
    privateKeySecretRef:
      name: letsencrypt-account-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: api-token
```

**Note:** The `apiTokenSecretRef` must be in the same namespace as
cert-manager (`cert-manager`). The ClusterIssuer is cluster-scoped but
reads secrets from the cert-manager namespace by default.

**File:** `k8s/clusters/homelab/cluster-issuer.yaml` (after the secret
is in place and cert-manager is running)

### 5. Gateway

A single shared Gateway that terminates TLS for all `*.k8s.murtadha.dev`
services. Uses a wildcard certificate.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: homelab
  namespace: default
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
spec:
  gatewayClassName: cilium
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
      hostname: "*.k8s.murtadha.dev"
      tls:
        mode: Terminate
        certificateRefs:
          - name: k8s-murtadha-dev-tls
      allowedRoutes:
        namespaces:
          from: All
```

cert-manager watches Gateway resources with the `cert-manager.io/cluster-issuer`
annotation and automatically creates a Certificate resource for the hostname.
The resulting TLS cert is stored in the `k8s-murtadha-dev-tls` Secret.

**File:** `k8s/clusters/homelab/gateway.yaml`

### 6. HTTPRoute for Longhorn

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: longhorn
  namespace: longhorn-system
spec:
  parentRefs:
    - name: homelab
      namespace: default
  hostnames:
    - longhorn.k8s.murtadha.dev
  rules:
    - backendRefs:
        - name: longhorn-frontend
          port: 80
```

Future services follow the same pattern — add an HTTPRoute in the service's
namespace with the appropriate hostname and backendRef.

**File:** `k8s/clusters/homelab/longhorn.yaml` (append to existing file,
or create `k8s/clusters/homelab/routes/longhorn.yaml` if preferred)

### 7. DNS Record

Add a wildcard A record in Cloudflare:

| Type | Name                 | Value        | Proxy |
|------|----------------------|--------------|-------|
| A    | *.k8s.murtadha.dev  | 10.20.30.80  | Off   |

Proxy must be **off** (DNS only) since this is a private IP. The record
points all `*.k8s.murtadha.dev` lookups to the Gateway's LoadBalancer IP.

This can be done manually in the Cloudflare dashboard or via the Cloudflare
API / Terraform provider.

## Implementation Order

### Phase 1: Cilium L2 Announcements

1. Add `l2announcements.enabled: true` and `externalIPs.enabled: true` to
   the Cilium Helm values in `talos.tf`
2. `tofu apply` to update Cilium
3. Deploy `cilium-l2.yaml` (L2 policy + IP pool)
4. Verify: create a test LoadBalancer Service and confirm it gets IP `.80`
   and is reachable from the LAN

### Phase 2: cert-manager

1. Deploy `cert-manager.yaml` via Flux
2. Wait for cert-manager pods to be ready
3. Create the Cloudflare API token Secret (method TBD — manual for now,
   SOPS later)
4. Deploy the ClusterIssuer
5. Verify: check `kubectl get clusterissuer letsencrypt` shows Ready

### Phase 3: Gateway + DNS

1. Add the `*.k8s.murtadha.dev` wildcard A record in Cloudflare → `10.20.30.80`
2. Deploy the Gateway resource
3. Verify: cert-manager issues the wildcard certificate, Gateway shows
   Programmed/Accepted status
4. Check `kubectl get certificate -A` — the cert should be Ready

### Phase 4: HTTPRoutes

1. Add the Longhorn HTTPRoute
2. Verify: `https://longhorn.k8s.murtadha.dev` loads the Longhorn UI with
   a valid Let's Encrypt certificate
3. Add routes for future services as needed

## Cilium Helm Values Change

The following values need to be added to the Cilium Helm release in
`Terraform-OpenTofu/talos.tf`:

```hcl
l2announcements = { enabled = true }
externalIPs     = { enabled = true }
```

These go inside the existing `values = [yamlencode({ ... })]` block alongside
`kubeProxyReplacement`, `gatewayAPI`, etc.

## File Summary

| File | Contents |
|------|----------|
| `Terraform-OpenTofu/talos.tf` | Cilium Helm values update (L2 announcements) |
| `k8s/clusters/homelab/cilium-l2.yaml` | CiliumL2AnnouncementPolicy + CiliumLoadBalancerIPPool |
| `k8s/clusters/homelab/cert-manager.yaml` | Namespace + HelmRepository + HelmRelease |
| `k8s/clusters/homelab/cluster-issuer.yaml` | ClusterIssuer (Let's Encrypt + Cloudflare DNS-01) |
| `k8s/clusters/homelab/gateway.yaml` | Gateway with TLS wildcard |
| `k8s/clusters/homelab/longhorn.yaml` | Updated with HTTPRoute (or separate routes file) |

## Open Questions

- [ ] **Secret management**: Manual secret creation to start, or set up SOPS
      with Flux from the beginning? SOPS is cleaner long-term but adds
      initial setup complexity (age key generation, Flux SOPS configuration)
- [ ] **HTTP → HTTPS redirect**: Should the Gateway also listen on port 80
      and redirect to 443? Cilium's Gateway API implementation may handle
      this automatically or may need a second listener
- [ ] **Gateway namespace**: The Gateway is placed in `default` for
      simplicity. It could live in its own namespace (e.g. `gateway-system`)
      if preferred — the HTTPRoutes use `parentRefs` with an explicit
      namespace to reference it regardless
- [ ] **AdGuard DNS rewrite**: Should `*.k8s.murtadha.dev` also be added
      as a DNS rewrite in AdGuard Home (→ `10.20.30.80`) so LAN clients
      resolve it locally without hitting Cloudflare DNS? This would speed
      up resolution on the LAN. The Cloudflare record is still needed for
      cert-manager's DNS-01 challenge
- [ ] **Wildcard vs per-service certs**: The plan uses a single wildcard
      cert (`*.k8s.murtadha.dev`). Alternative: each HTTPRoute triggers its
      own cert. Wildcard is simpler and avoids rate limit concerns
