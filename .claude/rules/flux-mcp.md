---
description: Guidelines for using the flux-operator-mcp tools to analyze and troubleshoot GitOps pipelines
globs:
  - "k8s/**"
---

# Flux MCP Server Usage

When working with Flux or Kubernetes resources, use the `flux-operator-mcp` MCP tools.

## General rules

- Check Flux installation status with `get_flux_instance`.
- Never assume the `apiVersion` of a resource -- call `get_kubernetes_api_versions` first.
- To determine if a resource is Flux-managed, look for `fluxcd` labels in metadata.
- Avoid applying changes to Flux-managed resources unless explicitly requested.
- Use `search_flux_docs` for Flux CRD schemas rather than relying on training data.

## Kubernetes logs analysis

1. Get the Deployment via `get_kubernetes_resources` to find `matchLabels` and container name.
2. List pods using those `matchLabels`.
3. Fetch logs with `get_kubernetes_logs` using the pod name and container name.

## HelmRelease troubleshooting

1. `get_flux_instance` -- check helm-controller status.
2. `get_kubernetes_resources` -- get the HelmRelease, analyze spec/status/inventory/events.
3. Check which Flux object manages it (annotations: Kustomization or ResourceSet).
4. If `valuesFrom` exists, get referenced ConfigMaps/Secrets.
5. Identify the source from `chartRef` or `sourceRef`, get and analyze it.
6. If failing, walk the inventory for failed managed resources and pull their logs.
7. Produce a root cause analysis report.

## Kustomization troubleshooting

1. `get_flux_instance` -- check kustomize-controller status.
2. `get_kubernetes_resources` -- get the Kustomization, analyze spec/status/inventory/events.
3. Check which Flux object manages it (annotations).
4. If `substituteFrom` exists, get referenced ConfigMaps/Secrets.
5. Identify the source from `sourceRef`, get and analyze it.
6. If failing, walk the inventory for failed managed resources and pull their logs.
7. Produce a root cause analysis report.
