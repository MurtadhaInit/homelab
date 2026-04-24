# Network & ingress consolidation plan

Consolidation of the homelab's ingress story into a single edge (the Cilium
Gateway), and a re-think of the domain/DNS layout around *who* is meant to
reach a service rather than *where it happens to run*.

## Critique of the current layout

Today services are split across two wildcards:

- `*.k8s.murtadha.dev` → Kubernetes-hosted services (Longhorn, etc.)
- `*.home.murtadha.dev` → NixOS LXC-hosted services (AdGuard, Grafana, etc.)

That split is *platform-based*. The URL leaks implementation detail, which
creates a few problems:

- **URLs become load-bearing history.** When a service migrates from the LXC
  container to the cluster (or back), its public name has to change. Every
  bookmark, SSO redirect URI, API integration, and user's muscle memory
  breaks. The hostname should be stable across refactors.
- **No signal about access intent.** A viewer of the URL cannot tell whether
  `grafana.home.murtadha.dev` is supposed to be reachable from the public
  internet or only from the LAN. The DNS zone answers "what platform is this
  on?" when the question that actually matters operationally is "who is
  supposed to see this?".
- **Two separate edges to manage.** Caddy on the LXC container and Cilium
  Gateway in the cluster both terminate TLS, both need cert renewal, both
  need their own upstream config. Every new service decision includes a
  "which edge?" choice that does not add value.

## Recommended direction: audience-tier domains, single edge

Split the zones by *who the audience is* instead of *where the workload
runs*:

- `*.home.murtadha.dev` → **internal tier.** Resolves only on the LAN (via
  AdGuard). Not published to Cloudflare. This is where admin UIs live —
  Longhorn, Grafana, AdGuard itself, Proxmox, router, etc.
- `*.public.murtadha.dev` → **public tier.** Resolves publicly via
  Cloudflare. This is where anything intended for friends, family, or the
  wider internet lives. Everything on this tier sits behind zero-trust auth
  by default.

Properties this gives:

- **Hostnames survive platform migrations.** Moving Grafana from the LXC
  container into the cluster keeps it at `grafana.home.murtadha.dev`.
- **The zone is the policy.** "It's on `public.`" carries meaning: it was a
  conscious choice to expose it, and it gets the public-tier treatment
  (auth, rate limiting, WAF, public TLS cert, external DNS).
- **One edge, one cert issuance path, one set of routes.** Cilium Gateway
  terminates TLS for both tiers; both wildcards are issued by cert-manager
  via the same Cloudflare DNS-01 flow.

### Keeping the single edge honest: bridging non-cluster workloads

The LXC container keeps running services (AdGuard is the obvious one —
can't move the DNS resolver *into* the thing it resolves for). To still
route them through the Cilium Gateway, use a **Service without a selector +
manually-managed EndpointSlice** pointing at the LXC's LAN IP:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: adguard
  namespace: external-bridges
spec:
  ports:
    - name: http
      port: 80
      targetPort: 3080
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: adguard
  namespace: external-bridges
  labels:
    kubernetes.io/service-name: adguard
addressType: IPv4
ports:
  - name: http
    port: 3080
endpoints:
  - addresses:
      - 10.20.30.50
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: adguard
  namespace: external-bridges
spec:
  parentRefs:
    - name: homelab
      namespace: gateway-system
      sectionName: https
  hostnames:
    - adguard.home.murtadha.dev
  rules:
    - backendRefs:
        - name: adguard
          port: 80
```

**Why this over `Service: ExternalName`:** ExternalName is a DNS CNAME
wrapper. It's attractive for its brevity, but it interacts poorly with
Gateway API backend resolution in several controllers (Cilium included has
had sharp edges here historically) and doesn't let you change the target
port. The selector-less Service + manual EndpointSlice is the canonical
"kubernetes-native handle for a non-kubernetes workload" pattern — static,
debuggable, and a first-class backendRef everywhere.

### TLS strategy for bridged backends

- **LAN-internal (`home.`)**: terminate at the Gateway with a real cert,
  speak plain HTTP to the LXC backend. Encrypting the LAN hop adds
  configuration surface with no realistic threat it mitigates in a
  single-VLAN home network.
- **Public (`public.`)**: still terminate at the Gateway. If a specific
  backend needs end-to-end TLS (e.g. a service that already has its own
  cert you don't want to drop), add a `BackendTLSPolicy` rather than making
  it the default.

This lets Caddy's reverse-proxy role be retired **incrementally** — one
HTTPRoute at a time — rather than as a big-bang cutover. Caddy can keep
serving anything not yet migrated.

## Concrete sequenced changes

Ordered so each step leaves the homelab in a working state.

### 1. Rename the Kubernetes wildcard → tier-based wildcards

- Rename the Gateway listener hostname from `*.k8s.murtadha.dev` to
  `*.home.murtadha.dev`.
- Update the AdGuard rewrite entry accordingly in
  `Nix/modules/adguardhome.nix` (the `clusterDomain` option is already
  nullable-generic, so just pass `"home.murtadha.dev"` from the host
  config).
- Update the Longhorn HTTPRoute hostname to
  `longhorn.home.murtadha.dev`.
- cert-manager will reissue a new `home-murtadha-dev-tls` wildcard cert via
  the existing DNS-01 flow. Leave the old `k8s-murtadha-dev-tls` Secret in
  place until the move lands, then delete it.
- Add a second listener on the same Gateway for `*.public.murtadha.dev`
  with its own Certificate Secret. Keep it empty of HTTPRoutes until
  External-DNS is in (step 2).

### 2. External-DNS for the public tier

- Deploy `external-dns` (HelmRelease) configured with:
  - provider: `cloudflare`
  - source: `gateway-httproute`
  - domain-filter: `public.murtadha.dev`
  - policy: `sync` (so deletions propagate)
- Reuse the existing Cloudflare API token Secret (scoped to `Zone:Edit`).
- Result: publishing a public service becomes *just* creating an HTTPRoute
  at `something.public.murtadha.dev` — the A record appears in Cloudflare
  automatically.

### 3. Zero-trust auth in front of public-tier admin UIs

Install **Authelia** or **Pomerium** (pick one) and wire it to an IdP
(GitHub OAuth is the low-friction option for a homelab; self-hosted
Keycloak is the learn-more option).

- Any HTTPRoute on the `public.` listener goes through the auth proxy by
  default, enforced via an HTTPRoute filter or a Cilium `CiliumNetworkPolicy`
  matching the Gateway's identity.
- MFA enforced at the IdP level; service-level RBAC stays where it belongs
  (inside each app).
- Public-tier certs are still publicly-trusted LE certs, so browsers don't
  complain and mobile devices don't need a CA roll-out.

### 4. Remote admin access: Headscale on a small VPS

For getting onto `home.` from outside the LAN without making `home.` itself
public:

- Rent a small VPS (Hetzner CX11-class is plenty).
- Run **Headscale** (self-hosted Tailscale control plane) on it.
- Run a Tailscale node inside the cluster (subnet-router mode, advertising
  the LAN CIDR) and one on the nixos-ct LXC.
- Laptop/phone joins the tailnet; `home.murtadha.dev` resolves and routes
  normally.
- This gives the "enterprise VPN to the corp network" mental model without
  exposing `home.` at all, and without the single-vendor lock-in of
  Cloudflare Tunnel.

### 5. Service catalog

- Deploy **Homepage** (gethomepage.dev) on the cluster at
  `home.murtadha.dev` (the apex).
- Auto-discovers services via annotations on HTTPRoutes. Becomes the
  single bookmark anyone needs.

### 6. Incrementally bridge / migrate LXC services

For each service currently on `*.home.murtadha.dev` via Caddy:

1. Create the Service + EndpointSlice + HTTPRoute (pattern above).
2. Verify it resolves and works through the Gateway.
3. Remove the Caddy vhost for that service.

Priority order (easiest wins first): Grafana, Prometheus, Loki → AdGuard
UI → anything Proxmox/router-adjacent. AdGuard's DNS port (:53) stays on
the LXC directly; only the web UI routes through the Gateway.

Once Caddy has no vhosts left, retire it entirely (keep the LXC running
just for AdGuard and anything else that has to live outside k8s).

## What to skip (explicitly)

Not every enterprise pattern earns its weight in a homelab:

- **Service mesh (Istio / full Linkerd).** Cilium already does
  identity-aware L7 policy. A mesh on top is operational cost with no
  corresponding threat model in a single-cluster homelab.
- **External Secrets Operator.** SOPS + age is already working, fits
  GitOps, and has a trivial mental model. ESO makes sense when you have a
  real secrets backend (Vault, AWS SM, 1Password Connect); introducing one
  just to justify ESO is backwards.
- **Multi-cluster / federation.** One cluster, one region, one admin. Not
  a problem that exists here.
- **Cloudflare Tunnel as the primary edge.** Vendor lock-in plus it hides
  the very networking concepts the homelab exists to teach. Use Headscale
  instead; keep Cloudflare for DNS only.

## Summary

Move from platform-coded zones (`k8s.` / `home.`) to audience-coded zones
(`home.` internal / `public.` external), run a single Cilium Gateway as the
one edge, bridge non-cluster workloads through selector-less Services with
manually-managed EndpointSlices, add External-DNS + zero-trust auth for the
public tier, and use Headscale on a small VPS for remote admin. Caddy's
reverse-proxy role retires incrementally; AdGuard stays on the LXC for DNS
but its UI moves behind the Gateway.
