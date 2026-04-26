# Home Infrastructure

## Goals (_the what_)

This is essentially a collection of various IaC scripts and definitions whose primary goal is declaratively defining all my home servers and services, as well as providing the ability to bootstrap everything from scratch if needed in the least amount of time and with minimal manual setup.

Another goal is flexibility. E.g., one would ask, why not deploy k8s on bare metal and skip the abstraction layer (and the extra maintenance that comes with it) of the hypervisor with Proxmox? The simple answer is flexibility: what if I want to run a VM? or try/deploy something quickly? or play with Docker/Podman? or even use Windows Server for some reason (I have a VM definition ready).

## Motivation (_the why_)

I aim for this homelab to be a learning and experimentation playground, where I can try different tools (for evaluation) or services (to see if they add value to my life). I also get the benefit of privacy, digital sovereignty, and data ownership. Plus homelabbing and self-hosting are simply fun, they can turn into an addictive hobby on their own.

The reason I'm using what some would call "overkill" technologies and platforms (like k8s) in a home setup is that I also want my own infrastrcture to be as closely aligned as possible to industry standards and enterprise tooling and tech stacks.

## Implementation (_the how_)

This is an ever-evolving design and the approaches and technologies being employed here are constantly changing. Some of these technologies include:

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

**Architectural Overview**

![](./docs/architecture.gif)

I try to have a solid foundation to build upon which is why my Hypervisor layer (Proxmox) is intentionally minimal: there is little configurations or changes from the default apart from the baseline hardening, SSH, and storage setup done through Ansible.
