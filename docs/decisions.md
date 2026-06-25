# Technical Project Decisions

## Current Technologies

| Name | Reason for adoption | Trade-offs |
|---|---|---|
| **Proxmox VE** | Free, stable, well-known & popular in the self-hosting space (lots of learning resources), based on Debian (easily automated) | An extra abstraction layer with its own upkeep, the Web UI looks outdated |
| **Talos Linux** | Security, convenience, and low maintenance: immutable, API-driven (no SSH or shell), minimal OS (smaller attack surface, less bloat) purpose-built for k8s. Also reproducible (config defined in code) | New-ish paradigm: traditional debugging methods not applicable, everything flows through the machine config, learning a new API |
| **NixOS** | Reproducible and *truly* declarative (not just the deployed services and their configurations, but also the system itself and its configuration), custom modules are reusable across different host types | Steep learning curve; functional, non-intuitive, niche language; building Linux derivations on macOS needs a separate Linux builder; longer deployments; poor documentation, tooling, and learning resources |
| **Kubernetes** | Industry-standard orchestration that aligns the homelab with enterprise infrastructure setups; HA, scalability, and a large learning payoff | Real operational complexity for a home setting, probably not required for common self-hosted apps |
| **Docker** | The most prevalent & well-known deployment platform/paradigm for containerised workloads (which are already the industry standard); useful for experimentation and quick deployments (before moving to k8s and codifying with manifests) | |
| **Ansible** | Very suitable for configuring vanilla Debian hosts (like Proxmox nodes) and other typical Linux distributions, playbooks serve as excellent self-documentation, mature & well-maintained | Slow, procedural rather than truly declarative, not quite idempotent (e.g. doesn't uninstall what once added), requires Python |
| **OpenTofu (Terraform)** | Declarative IaC with many providers, most suitable for provisioning Proxmox VMs/LXCs, widely-used & industry-standard | Managing sate is a concern, secrets (like Talos/k8s PKI) end up in state and hence state encryption is needed, limitations of the bpg/proxmox provider & the Proxmox API itself, and lifecycle management can become hard to maintain (e.g. Talos provisioning) |
| **Flux + Flux Operator** | GitOps paradigm (declarative, tracked, continuous deployment), reconciles repo state with the cluster much like how k8s controllers reconcile the cluster state with `etcd`, self-managing via its own `FluxInstance` | |
| **Longhorn** | Gaining experience with native (distributed) k8s storage, data replication across nodes (HA persistent volumes for stateful workloads), less demanding than Ceph (Rook) | Higher complexity, learning & management overhead, extra resource consumption (CPU/RAM), more disk capacity requirements |
| **cert-manager** | Automated in-cluster certificate issuance/renewal for my Gateway (TLS termination), a widely-used cloud-native solution, integrates seamlessly with Let's Encrypt and the Cloudflare API (for DNS-01) | |
| **Cloudflare** | At-cost domain name registrar, fast & reliable network for authoritative DNS (external DNS solution), DNS-01 challenge provider for TLS-termination across my reverse proxies | |
| **Tailscale** | WireGuard mesh VPN for remote access, polished clients, generous free-tier, ability to designate a "subnet router" client (i.e. the NixOS LXC) for advertising LAN to other clients | Close source coordination server, some config (tags, nameserver) lives in the web console |
| **Cilium** | Complete k8s networking solution: CNI, kube-proxy replacement, in-cluster reverse proxy (Gateway API through Envoy), and L2 announcements and LB IPAM to expose services on the LAN; eBPF for easier in-depth observability; enterprise-grade | Steep learning curve, eBPF capabilities are yet to be explored/taken advantage of |
| **Helm** | Standard k8s deployment tool, documented (official) installation method for most cluster infra tools like Cilium, Longhorn, and cert-manager | Available `values` to customise a chart can be quite massive |
| **SOPS + age** | Committing encrypted secrets keeps the setup more encapsulated in the repo & self-contained, secrets are Git-tracked in one place and easy to rotate, cloud-native, integrates well with Ansible & Terraform | age-key distribution to manage: e.g. private key should be in the cluster so Flux can decrypt SOPS-encrypted k8s Secrets, the danger of comitting a decrypted secret by mistake |
| **agenix + age** | Same age key pair reused for secrets on the Nix side (single key for entire homelab); like SOPS, encrypted secrets are Git-tracked; decryption is baked into deploys so many services are bought-up with one command, similar mental-model to SOPS | |
| **Caddy** | "Easier" & well documented, its main downside (plugins are awkward & require a recompile) is mitigated in a NixOS module: the Cloudflare plugin used for DNS-01 challenges to auto-renew TLS certificates is simply defined using `pkgs.caddy.withPlugins`, more of a set-it-and-forget-it | |
| **AdGuard Home** | Reliable local DNS solution with block lists and DNS rewrites, can be fully declared in a NixOS module (with login credentials) | Single DNS point of failure (redundancy on the roadmap) |
| **kube-prometheus-stack** | Industry-standard k8s observability stack, mature | Resource-hungry, time-consuming to master and expertly manage |
| **deploy-rs** | Easy NixOS config deployments (and to multiple targets), automatic rollback to the last good revision on failure, well-designed & documented, still actively maintained | |
| **mise + just** | `mise` pins core project dependencies & CLI tools, cross-platform, reliable & easy to use; `just` is a great makefile replacement: task runner for ordered/ad-hoc (utility) commands & Bash recipes, readable and intuitive file, a launching pad for the project | |

## Retired Technologies

| Name | Reason for retirement |
|---|---|
| **Ansible Vault** | Unified secrets management in the repo under SOPS for easier maintenance and lower friction |

## Log

A timestamped log (list) of major decisions taken over the lifetime of the project.
