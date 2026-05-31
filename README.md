# Home Infrastructure

> A declarative, GitOps-driven homelab on Proxmox, Talos Linux, NixOS, and Kubernetes.

[![Last commit](https://img.shields.io/github/last-commit/MurtadhaInit/homelab?style=flat-square&logo=git&logoColor=white)](https://github.com/MurtadhaInit/homelab/commits/main)
[![Repo size](https://img.shields.io/github/repo-size/MurtadhaInit/homelab?style=flat-square)](https://github.com/MurtadhaInit/homelab)
[![Stars](https://img.shields.io/github/stars/MurtadhaInit/homelab?style=flat-square&logo=github)](https://github.com/MurtadhaInit/homelab/stargazers)

This repo is primarily intended to give you inspiration and ideas on how to deploy
applications and services in your homelab using either the Nix or Kubernetes ecosystem,
while also showcasing various explorations into self-hosting technologies and approaches.

<p align="center">
  <img src="./docs/architecture.gif" alt="Architecture diagram"/>
</p>

## Table of Contents

- [Home Infrastructure](#home-infrastructure)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Quick Start](#quick-start)
  - [Implementation](#implementation)
    - [Workflow](#workflow)
    - [Nix](#nix)
    - [Kubernetes](#kubernetes)
    - [Networking](#networking)
    - [Observability](#observability)
    - [Agentic GitOps](#agentic-gitops)
  - [Services](#services)
  - [Roadmap](#roadmap)
  - [Acknowledgements](#acknowledgements)
  - [License](#license)

## Overview

This is essentially a collection of various IaC scripts and definitions whose
primary goal is declaratively defining and documenting all my home servers and
services, as well as providing the ability to bootstrap everything from scratch
in the least amount of time and with minimal manual setup. The observability stack
gradually introduced aims to keep infrastructure and services continuously reliable.

I aim for this homelab to be a learning and experimentation playground, where I
can try different tools (for evaluation) or services (to see if they add value to
my life). I also gain the benefit of privacy, digital sovereignty, and data ownership.
Plus homelabbing and self-hosting are just fun; they quickly turned into an addictive
hobby on their own.

The reason I'm using what some would consider "overkill" technologies and platforms
(like k8s) for a homelab setup is that I also want my own home infrastructure to
be as closely aligned as possible to industry standards and to enterprise tooling
and tech stacks.

Flexibility is another goal. E.g., one would ask, why not deploy k8s on bare metal
and skip the Proxmox abstraction layer entirely (along with its maintenance
overhead)? The simple answer is flexibility: what if I want to run other
VMs? or to quickly deploy and experiment with some new technology? or to play with
Docker/Podman? or even to use Windows Server for some reason (I have a VM definition
ready)?

This flexible setup also allows me to make use of two different approaches for deploying
and configuring applications, and without much hassle: declarative `systemd` services
in the form of NixOS modules, and containerised applications running on a platform
like Docker or k8s. This is arguably the best of both worlds: combining the enterprise
scalability of a robust, widely-adopted platform like k8s and the relative
"simplicity" or straightforwardness of declarative NixOS services.

## Quick Start

To get started you need `mise` and `just` installed. Then executing the `just` command
anywhere inside the repo will show all the available recipes. This includes a
step-by-step numbered sequence for getting the infrastructure up and running. E.g.,
`just bootstrap` will take care of installing all the required CLIs locally through
`mise`.

Common utility commands for deployment (which are likely to be triggered more frequently)
are grouped together per the respective platform (e.g., Kubernetes vs. Nix).

## Implementation

This is an ever-evolving design which has gone through major changes over time.
The approaches and technologies employed here are constantly changing. Some of these
technologies include:

<table>
  <tr>
    <td align="center" width="110"><img height="40" alt="Proxmox" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/proxmox.svg"/><br/><sub>Proxmox</sub></td>
    <td align="center" width="110"><img height="40" alt="Talos" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/talos.svg"/><br/><sub>Talos</sub></td>
    <td align="center" width="110"><img height="40" alt="NixOS" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/nixos.svg"/><br/><sub>NixOS</sub></td>
    <td align="center" width="110"><img height="40" alt="Docker" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/docker.svg"/><br/><sub>Docker</sub></td>
    <td align="center" width="110"><img height="40" alt="Kubernetes" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/kubernetes.svg"/><br/><sub>Kubernetes</sub></td>
    <td align="center" width="110"><img height="40" alt="Cilium" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/cilium.svg"/><br/><sub>Cilium</sub></td>
  </tr>
  <tr>
    <td align="center" width="110"><img height="40" alt="Flux" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/flux-cd.svg"/><br/><sub>Flux</sub></td>
    <td align="center" width="110"><img height="40" alt="Helm" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/helm.svg"/><br/><sub>Helm</sub></td>
    <td align="center" width="110"><img height="40" alt="cert-manager" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/cert-manager.svg"/><br/><sub>cert-manager</sub></td>
    <td align="center" width="110"><img height="40" alt="Longhorn" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/longhorn.svg"/><br/><sub>Longhorn</sub></td>
    <td align="center" width="110"><img height="40" alt="OpenTofu" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/opentofu.svg"/><br/><sub>OpenTofu</sub></td>
    <td align="center" width="110"><img height="40" alt="Ansible" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/ansible.svg"/><br/><sub>Ansible</sub></td>
  </tr>
  <tr>
    <td align="center" width="110"><img height="40" alt="AdGuard Home" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/adguard-home.svg"/><br/><sub>AdGuard Home</sub></td>
    <td align="center" width="110"><img height="40" alt="Grafana" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/grafana.svg"/><br/><sub>Grafana</sub></td>
    <td align="center" width="110"><img height="40" alt="Prometheus" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/prometheus.svg"/><br/><sub>Prometheus</sub></td>
    <td align="center" width="110"><img height="40" alt="Loki" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/loki.svg"/><br/><sub>Loki</sub></td>
    <td align="center" width="110"><img height="40" alt="Uptime Kuma" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/uptime-kuma.svg"/><br/><sub>Uptime Kuma</sub></td>
    <td align="center" width="110"><img height="40" alt="Cloudflare" src="https://cdn.jsdelivr.net/gh/selfhst/icons@main/svg/cloudflare.svg"/><br/><sub>Cloudflare</sub></td>
  </tr>
</table>

My general approach is to establish a stable foundation to build upon, which is
why my Hypervisor layer (Proxmox) is intentionally minimal in terms of adjustments:
I don't use HA or Ceph storage, and there are only a few configurations applied
to Proxmox hosts, mainly focusing on baseline hardening, SSH access, and storage
setup. I defer things like HA further up the stack, into my k8s cluster.

Some of the services I self-host are installed on a NixOS LXC container running
privileged on the Proxmox host, and others are containerised and running on my
k8s cluster.

The reason for this split is that certain services I want to be "just working"
(i.e., to set-it-and-forget-it), without the management overhead and general
upkeep that comes with k8s. However, this also comes down to the availability of
high quality NixOS modules (which I'm then wrapping with my own custom ones), the
number of options they expose, and the reliability at which configurations are
deterministically applied.

For instance, with my local DNS solution (AdGuard Home), it's easier to define all
the configurations, including DNS re-writes, filtering lists, and even login credentials
(using `agenix`) in one hand-crafted NixOS module file that wraps the AdGuard service
and which can be selectively toggled on or off for any machine. Additionally, the
"off" here means the service is gone, binaries are unlinked, and even the firewall
ports previously open are now closed.

This idempotency can be contrasted with a tool like Ansible, which is not _truly_
declarative _nor_ idempotent out of the box: removing a task to install a service
from a playbook and re-running that playbook against the same target machine doesn't
actually remove that service. You have to manually SSH and uninstall it yourself.

This NixOS setup is made easier because of `deploy-rs` and its many niceties,
like reverting to the previous (working) revision right away if a deployment fails,
preventing downtime and service disruption.

For everything else, I prefer the GitOps approach to declaratively define and continuously
deploy my k8s workloads using Flux with Helm releases and handwritten manifests.

> [!NOTE]
> But why not Docker? the simple and honest answer: it's a bit too easy and less
  interesting (I already am familiar with Docker); plus there isn't as large of
  a learning opportunity compared to k8s. Though I do have a Docker deployment
  on the Ubuntu VM (installed and configured with Ansible) which I'm also
  exploring and playing with.

### Workflow

```mermaid
flowchart TD
    A[Install Proxmox<br/>on bare metal] --> B[Generate SSH keys<br/>+ bootstrap Proxmox access]
    B --> C[Configure Proxmox hosts<br/>with Ansible playbooks]
    C --> D[Provision VMs/LXCs<br/>+ Talos cluster<br/>via OpenTofu]
    D --> E[Baseline-configure<br/>VMs/LXCs with Ansible]
    E --> F1[Nix path:<br/>deploy-rs + Flake]
    E --> F2[Kubernetes path:<br/>Flux + Helm/manifests]
```

<details>
<summary><strong>Detailed steps</strong></summary>

1. After installing Proxmox on bare metal, we start first by generating an SSH key
   pair on the current workstation and then supplying the public key to the Proxmox
   root user. This prepares the Proxmox hosts for configuration management tools
   by bootstrapping access to the hypervisor layer.
   - Everything is done through consecutive `justfile` recipes.
   - A particular location for the generated keys is assumed (see the `justfile`).
2. We can then configure Proxmox hosts with Ansible playbooks.
   - One general playbook will perform basic hardening and preparation like
     disabling SSH password access, creating a regular user, giving it sudo
     access... etc.
   - Another playbook will configure storage on the Proxmox node, which is specific
     to my particular layout for this particular host (and only for this current
     Proxmox installation).
   - These playbooks also rely on the Proxmox API, and hence a token needs to be
     generated first (e.g. from the host console in the Proxmox Web GUI).
   - For now, the secrets solution for encrypting the token and the
     regular user credentials is Ansible Vault, using a password file whose default
     location is set in `ansible.cfg`.
   - And finally, another playbook will install Prometheus `node_exporter` to
     expose metrics from the Proxmox nodes for scraping and subsequent alerting
     and monitoring.
3. We deploy resources primarily with OpenTofu (Terraform can also be used)
   , and we provision most VMs with static IP addresses (and/or other initialisation
   steps) using CloudInit, either as templates or as the minimal equivalent
   initialisation block from Proxmox.
   - The `bpg/proxmox` provider is used to create VMs and LXC containers. We supply
     it with a similar (or the same) Proxmox API token to the one we used with Ansible.
     We also provide it with SSH credentials (the key generated earlier) to be able
     to perform other tasks not ordinarily possible with the API access alone, as
     per the provider docs.
   - A `proxmox-hosts.auto.tfvars` file should be created, providing secret values
     for `pve_host_ip`, `pve_host_port`, `pve_host_user`, `pve_host_api_token`,
     and `pve_hostname`.
   - We use the official `talos` provider to provision the Talos cluster after
     creating the worker and controlplane VMs (generate secrets, define machine
     config, bootstrap `etcd`... etc).
4. Once VMs / LXC containers are created, baseline/further configurations are
   performed using Ansible playbooks as well.
   - We deploy NixOS as a privileged LXC container (unprivileged has caused various
     file permission issues), and hence we require additional steps after creating
     the container since token-based Proxmox API access cannot perform those steps.
     This applies to both the Terraform/OpenTofu provider as well as the
     Ansible collection. So instead we use an Ansible playbook with imperative commands
     for that purpose.
   - We use a playbook to install and configure Docker and Portainer on the newly
     created Ubuntu VM.
5. At this point, VMs and containers have the required baseline configuration, and
   each can be managed going forward with the specialised tools and technologies
   suitable for each platform. This is also where services and applications are
   deployed. See the [Nix](#nix) and [Kubernetes](#kubernetes) sections below.

</details>

### Nix

I write custom modules that wrap the official NixOS ones to add further configurations
and to customise the exposed settings, so that these modules can be readily included
and toggled for any NixOS target. E.g., if I switch to a VM instead of an LXC
container, or if I split apps into separate containers, the same modules can be
reused.

`deploy-rs` is then used to deploy NixOS configurations to target machines (for
now, just the LXC container). See the relevant `justfile` recipe under the `nix`
group.

`agenix` takes care of deploying secret files that I have stored encrypted in this
repo. So with login credentials already in my password manager, this makes many
services a truly one-command-deploy. See the `modules` directory for available services.

> [!IMPORTANT]
> Building Linux derivations on macOS requires a linux builder, and for this I'm
  currently using the Determinate Nix distribution of Nix on my macOS machine.

### Kubernetes

The current cluster deployment goes like this:

Once we hit `tofu apply -auto-approve` OpenTofu will start deploying VMs and
create other resources on Proxmox. This includes the download of an appropriate
Talos image from the Talos Image Factory (embedding the required system extensions)
and using it to create 5 VMs: 3 controlplane + 2 workers nodes. Those are defined
(along with cluster information) in `vm-talos.tf`.

OpenTofu will take care of generating cluster secrets (PKI), machine configurations
per role (controlplane vs. worker), push those configurations to the newly
created VMs, bootstrap `etcd` (once), retrieve `talosconfig` and `kubeconfig`
and save them to disk, and finally install the minimally-necessary infrastructure
software on the cluster for it to be ready. This includes Cilium, a CNI and network
solution, installed through the Helm provider. All of this takes place in `talos.tf`.

The Flux Operator (along with Flux itself) are then bootstrapped into the cluster
by the official [`flux-operator-bootstrap`][flux-operator-bootstrap] Terraform module.
It installs the Flux Operator chart, applies the `FluxInstance` manifest
from `k8s/clusters/homelab/flux-system/flux-instance.yaml`, and seeds
the SOPS age key as `Secret/sops-age` in the `flux-system` namespace. All of
this is done via an ephemeral in-cluster `Job`. This is defined in `flux.tf`.

And since the `FluxInstance` defines a `sync` configuration to deploy resources
from this Git repo, once Flux is up, it will start automatically reconciling
everything defined in `k8s/clusters/homelab` by pulling this repo and applying
these resources in a GitOps manner. Flux will also self-reconcile the same `FluxInstance`
from the repo, closing the GitOps loop on its own configuration (changing that
manifest will cause the operator to change Flux itself).

Going forward, changes made to resources inside the `./k8s` directory are automatically
reconciled by Flux controllers with the current state of the cluster, otherwise
alerts are sent in the case of failure.

This workflow essentially means (assuming nothing goes wrong) the entire cluster
and everything installed on it can be bootstrapped from scratch using OpenTofu
and Flux with one `just deploy-apply` command. Adding or removing k8s-deployed
applications is simply writing or removing manifests in `./k8s/apps`, comitting,
and pushing.

> [!IMPORTANT]
> Before running `just deploy-apply`, the SOPS age private key must exist at
> `~/.ssh/keys/sops-age.txt` (overridable via `-var sops_age_key_path=...`).
> The file is read at plan time; missing it fails fast before the cluster is
> touched.

[flux-operator-bootstrap]: https://github.com/controlplaneio-fluxcd/terraform-kubernetes-flux-operator-bootstrap

### Networking

At the moment, I'm using two reverse proxies simultaneously: the first is Caddy,
deployed on my NixOS LXC container and is proxying to my Nix services on the
same container as well as to services on other VMs/LXCs and to
the Proxmox Web UI (the Proxmox host IP + port). The second is Cilium Envoy through
the Gateway API on my k8s cluster. The future plan is to consolidate onto one reverse
proxy (Cilium), and to retire Caddy (disabling the Nix module) but keeping it as
an emergency backup.

My local DNS solution is currently AdGuard Home. In addition to block lists, I
have two DNS rewrites configured:

1. The first is a wildcard for all subdomains of `home.murtadha.dev`. It points
   at `10.20.30.50` (the LXC container's static IP) where my Caddy reverse proxy
   listens for web traffic (port `80`/`443`) and routes it based on the subdomain
   to the appropriate backend (likely a NixOS service on the same container —`localhost`).
2. The second is a wildcard for subdomains of `k8s.murtadha.dev`, pointing at
   `10.20.30.80`. That IP isn't bound to any physical interface — instead, Cilium's
   LB IPAM allocates it (from a `CiliumLoadBalancerIPPool`) to the `LoadBalancer`
   Service backing the `homelab` Gateway, and the worker nodes make it reachable
   on the LAN by answering ARP requests for it (`CiliumL2AnnouncementPolicy`).
   Once a connection lands on a worker, Cilium's managed Envoy forwards the request
   to the right in-cluster Service based on the matching `HTTPRoute` (hostname/path).

Obviously, the existence of two domain names is unnecessary, especially with one
revealing underlying implementation details (`*.k8s`) for no reason. So in the
future, only the first will be used, pointing at the k8s gateway. The gateway should
also proxy to services outside the cluster, like those deployed on the NixOS container.

Cloudflare is my external DNS solution. Both web servers are terminating client
connections with TLS using DNS-01 type of challenge through Let's Encrypt. They
both use the Cloudflare API to automatically create and tear down DNS records to
satisfy the challenge when obtaining/renewing certificates.

Nix makes it easy to bake a Caddy plugin into the compiled Caddy binary, avoiding
one of the main downsides of Caddy. The token is injected into Caddy's environment
and is stored encrypted in this repo using `agenix`. Similarly, a token is provided
to `cert-manager` inside the k8s cluster in the form of a k8s `Secret` deployed
with Flux (and it's also stored encrypted in this repo but this time using `SOPS`).
`cert-manager` takes care of creating certificate signing requests and renewing
certificates before expiration. Signed certificates are in turn used by the annotated
`Gateway` resource for TLS encryption.

For remote access I use [Tailscale](https://tailscale.com/) (a mesh VPN built on
WireGuard) to reach my self-hosted services from anywhere and _without_
exposing anything publicly. This means no port forwarding and no services on a
public IP, just an authenticated, fine-controlled, end-to-end encrypted overlay
mesh network (a "tailnet") between peers.

Rather than installing Tailscale on every host, the NixOS LXC container runs as
a **subnet router**: it sits on both the tailnet and the LAN, and advertises the
`10.20.30.0/24` route. That single node then forwards traffic from any tailnet peer
onto the LAN, so remote clients can reach things like the k8s Gateway at
`10.20.30.80` or Caddy at `10.20.30.50` as if they were on the home network.

AdGuard Home is registered as the tailnet's _global_ nameserver with _Override
DNS servers_ enabled, so every DNS query from a connected device is resolved by
AdGuard whether I'm home or away (rather than split DNS that would only forward
the homelab domain, e.g. `home.murtadha.dev`). The internal names still
resolve to the same LAN IPs and route through the subnet router, plus the same
block lists and filtering follow me off the network as a bonus.

See the end-to-end [setup guide](docs/tailscale-setup.md).

### Observability

> [!NOTE]
> Work in progress — see [Roadmap](#roadmap) for the next observability milestones.

The current setup involves Prometheus (metrics), Alertmanager (alerts),
and Grafana (visualisations) deployed in Kubernetes through the `kube-prometheus-stack`
Helm chart. The Proxmox host has a `node_exporter` installed through an Ansible
playbook and hence it's being scraped along with other k8s nodes (VMs) and components/services.

I installed Uptime Kuma through hand-written manifests, translating the Docker
Compose example they have in the docs into k8s resources.

### Agentic GitOps

The [Flux Operator MCP Server](https://fluxoperator.dev/docs/mcp/prompting/)
is configured in this repo (`.mcp.json`) and automatically installed as a CLI
through `mise` along with the other tools. This gives any MCP-compatible AI
assistant (Claude Code, Cursor, Codex, etc.) direct access to the Kubernetes cluster
and its Flux resources. The assistant can be prompteed to inspect Flux installations,
query resource status and events, search up-to-date Flux documentation, analyze
pod logs and metrics, trigger reconciliations, and perform structured root cause
analysis on failing HelmReleases or Kustomizations.

Troubleshooting guidelines from the upstream project can be included as agent
[instructions](https://fluxoperator.dev/docs/mcp/instructions/) and modified based
on the unique cluster properties to guide assistants into following the recommended
analysis workflows (e.g., walking the dependency chain from a Kustomization
through its source and inventory before pulling pod logs).

## Services

| Service | Description | Platform | Status |
|---|---|---|:---:|
| **Syncthing** | File sync between MacBook and homelab (as a hub); stable device IDs via Nix mean both ends pair automatically with shared ignore patterns, suitable versioning, and pre-defined shared folders | NixOS module | ![Deployed](https://img.shields.io/badge/-deployed-success?style=flat-square) |
| **Jellyfin** | Home media server, accessed primarily via Infuse on Apple TV (Swiftfin/Moonfin are solid alternative clients) | NixOS module | ![Deployed](https://img.shields.io/badge/-deployed-success?style=flat-square) |

More services to come.

## Roadmap

- [X] **Flux Operator**: migrate from vanilla Flux (see `plans/flux-operator-migration.md`)
- [ ] **Logging stack**: deploy Loki and Alloy to complete the LGTM observability rollout
- [ ] **Reverse proxy consolidation**: route everything through the k8s Gateway API; keep Caddy disabled but available as a fallback
- [ ] **Single domain**: drop `*.k8s.murtadha.dev` and route all traffic via `home.murtadha.dev`
- [ ] **DNS**: evaluate Technitium as a potential AdGuard Home replacement
- [ ] **Remote Linux Nix builder**: build NixOS derivations on a Linux machine inside my infra (avoiding macOS build issues)
- [ ] **Too many secret solutions**: attempt to eliminate some and simplify this aspect
- [ ] **Split LXC containers** to minimise potential downtime if things go wrong with one NixOS service / deployment
- [ ] **Make use of VLANs** for network isolation and security
- [ ] **DNS redundancy** to avoid network issues if the local DNS server goes down
- [X] **Integrate Tailscale** for remote access (subnet router on the NixOS LXC, AdGuard as the tailnet nameserver)
- [ ] **Replace Portainer with Dockerhand** for improved Docker environment management
- [ ] **More services** to self-host
- [ ] **Adopt Renovate** to update images
- [ ] **Adopt Kyverno** to refuse to run an image not carrying valid provenance attestation from my pipeline (for the e-store deployment)

## Acknowledgements

_To be added._

## License

This project is licensed under the [MIT License](LICENSE).
