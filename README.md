# Home Infrastructure

## Goals (_the what_)

This is essentially a collection of various IaC scripts and definitions whose primary goal is declaratively defining all my home servers and services, as well as providing the ability to bootstrap everything from scratch in the least amount of time and with minimal manual setup. The observability stack gradually introduced aims to keep infrastructure and services continuously reliable.

Another goal is flexibility. E.g., one would ask, why not deploy k8s on bare metal and skip the abstraction layer (and the accompanying maintenance overhead) of the Proxmox hypervisor? The simple answer is flexibility: what if I want to run other VMs? or to quickly deploy and experiment with some new technology? or to play with Docker/Podman? or even to use Windows Server for some reason (I have a VM definition ready)?

This flexible setup also allows me to make use of two different approaches for deploying and configuring applications, and without much hassle: declarative `systemd` services as NixOS modules vs. containerised applications running on a platform like Docker or k8s.

## Motivation (_the why_)

I aim for this homelab to be a learning and experimentation playground, where I can try different tools (for evaluation) or services (to see if they add value to my life). I also gain the benefit of privacy, digital sovereignty, and data ownership. Plus homelabbing and self-hosting are just fun; they quickly turned into an addictive hobby on their own.

The reason I'm using what some would consider "overkill" technologies and platforms (like k8s) for a homelab setup is that I also want my own infrastructure to be as closely aligned as possible to industry standards and to enterprise tooling and tech stacks.

## Implementation (_the how_)

This is an ever-evolving design which has gone through major changes over time. The approaches and technologies employed here are constantly changing. Some of these technologies include:

<p>
  <img height="40" alt="Proxmox" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/proxmox.svg"/>
  <img height="40" alt="Talos" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/talos.svg"/>
  <img height="40" alt="NixOS" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/nixos.svg"/>
  <img height="40" alt="Docker" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/docker.svg"/>
  <img height="40" alt="Kubernetes" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/kubernetes.svg"/>
  <img height="40" alt="Cilium" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/cilium.svg"/>
  <img height="40" alt="Flux" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/flux-cd.svg"/>
  <img height="40" alt="Helm" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/helm.svg"/>
  <img height="40" alt="cert-manager" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/cert-manager.svg"/>
  <img height="40" alt="Longhorn" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/longhorn.svg"/>
  <img height="40" alt="OpenTofu" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/opentofu.svg"/>
  <img height="40" alt="Ansible" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/ansible.svg"/>
  <img height="40" alt="AdGuard Home" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/adguard-home.svg"/>
  <img height="40" alt="Grafana" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/grafana.svg"/>
  <img height="40" alt="Prometheus" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/prometheus.svg"/>
  <img height="40" alt="Loki" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/loki.svg"/>
  <img height="40" alt="Uptime Kuma" src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/uptime-kuma.svg"/>
  <img height="40" alt="Cloudflare" src="https://cdn.jsdelivr.net/gh/selfhst/icons@main/svg/cloudflare.svg"/>
</p>

I generally try to establish a stable foundation to build upon, which is why my Hypervisor layer (Proxmox) is intentionally minimal in terms of adjustments: I don't use HA or Ceph storage, and there are only a few configurations applied to Proxmox hosts, mainly focusing on baseline hardening, SSH access, and storage setup.

Some of the services I self-host are installed directly on a NixOS LXC container running privileged on the Proxmox host, and others are containerised and running on my k8s cluster.

The reason for this split is that certain services I want to be "just working", without the management and upkeep overhead that comes with k8s or even with containerised deployments in general. However, this also comes down to the availability of high quality NixOS modules (which I'm then wrapping with my own custom ones), the number of options they expose, and the reliability at which configurations are deterministically applied.

For instance, with my local DNS solution (AdGuard Home), it's easier to define all the configurations, including DNS re-writes, filtering lists, and even login credentials (using `agenix`) in one hand-crafted NixOS module file that wraps the AdGuard service and can be toggled on or off. And the "off" here means the service is gone, binaries are unlinked, and even the firewall ports previously open are now closed.

This idempotency can be contrasted with a tool like Ansible, which is not _truly_ declarative nor idempotent out of the box: removing a task to install a service from a playbook and re-running that playbook against the same target machine doesn't actually remove that service. You have to manually SSH and uninstall the service.

This NixOS setup is made easier because of `deploy-rs` and its included niceties, like reverting to the previous (working) build right away if a deployment fails, preventing downtime and service disruption.

For everything else, I prefer the GitOps approach to declaratively define and continuously deploy my k8s workloads using Flux with Helm releases or handwritten manifests.

### Architectural Overview

![architecture](./docs/architecture.gif)

### Workflow

1. Ansible
