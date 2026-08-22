# List available recipes
default:
    @just --list --unsorted

# 0. Install dependencies
bootstrap:
    @echo "⚙️ Installing CLI tools..."
    mise install
    @echo "\n⚙️ Installing Python tools and packages with uv..."
    uv sync
    @echo "\n⚙️ Installing Ansible collections..."
    uv run ansible-galaxy collection install --upgrade -r ansible/requirements.yml
    @echo "\n⚙️ Installing Terraform/OpenTofu provider plugins..."
    tofu -chdir=Terraform-OpenTofu init -input=false

# 1. Generate SSH key pairs locally for the management of Proxmox hosts and VMs
generate-keys:
    #!/usr/bin/env bash
    set -euo pipefail
    for key in proxmox-hosts proxmox-vms; do
        [ -f ~/.ssh/keys/$key ] && continue
        echo "Generating SSH key pair..."
        ssh-keygen -a 100 -t ed25519 -f ~/.ssh/keys/$key -C "generated on $(hostname)"
        if [[ "$(uname)" == "Darwin" ]]; then
            echo "Adding key to ssh-agent and storing passphrase in keychain (macOS)..."
            ssh-add --apple-use-keychain ~/.ssh/keys/$key
        else
            echo "Adding key to ssh-agent..."
            ssh-add ~/.ssh/keys/$key
        fi
    done

# (internal) Print the ansible_host IP of an inventory host; no arg = all proxmox_hosts
[working-directory('ansible')]
_pve-ip host='':
    @uv run ansible-inventory --list | jq -r --arg h '{{ host }}' \
      '._meta.hostvars as $hv | (if $h == "" then .proxmox_hosts.hosts[] else $h end) | $hv[.].ansible_host // empty'

# 2. Install the generated public SSH key on Proxmox hosts (root password prompt on first run only)
[working-directory('ansible')]
copy-keys:
    #!/usr/bin/env bash
    set -euo pipefail
    just _pve-ip | while read -r host; do
        ssh-copy-id -i ~/.ssh/keys/proxmox-hosts.pub "root@$host"
    done

# NOTE: Set the IPs of Proxmox nodes in Ansible inventory (hosts.ini) under the proxmox_hosts group.
# The name given to the node there is the one passed to this recipe.
# 2.5 (Re)create a Proxmox API token on a host and store it SOPS-encrypted for Ansible & OpenTofu.
[working-directory('ansible')]
pve-token host:
    #!/usr/bin/env bash
    set -euo pipefail
    ip=$(just _pve-ip {{ host }})
    [ -n "$ip" ] || { echo "❌ Host '{{ host }}' not found in the inventory." >&2; exit 1; }
    echo "⚙️ (Re)creating the root@pam!automation token on {{ host }} ($ip)..."
    # Remove-then-add makes this re-runnable; the secret is only shown once, at creation.
    secret=$(ssh -i ~/.ssh/keys/proxmox-hosts "root@$ip" '
        pveum user token remove root@pam automation >/dev/null 2>&1 || true
        pveum user token add root@pam automation --privsep 0 --output-format json' \
      | jq -r '.value // empty')
    [ -n "$secret" ] || { echo "❌ Token creation returned no secret." >&2; exit 1; }
    f="inventory/host_vars/{{ host }}/proxmox-api-token.sops.yaml"
    mkdir -p "$(dirname "$f")"
    # Encrypt straight from stdin so the plaintext secret never lands on disk.
    # We don't write encrypted result straight to $f so a failed run doesn't clobber a good existing file.
    tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
    printf 'proxmox_api_token_secret: %s\n' "$secret" \
      | sops encrypt --filename-override "$f" /dev/stdin > "$tmp"
    mv "$tmp" "$f"
    echo "✅ Wrote $f — read by both Ansible and OpenTofu."

# 3. Prepare Proxmox hosts
[working-directory('ansible')]
pve-hosts:
    @echo "\n⚙️ Configuring Proxmox hosts..."
    uv run ansible-playbook playbooks/proxmox-hosts.yaml
    uv run ansible-playbook playbooks/proxmox-fs-host-1.yaml
    uv run ansible-playbook playbooks/proxmox-fs-host-2.yaml
    uv run ansible-playbook playbooks/proxmox-node-exporter.yaml

# 4.a Plan resource deployment
[working-directory('Terraform-OpenTofu')]
deploy-plan:
    tofu plan

# 4.b Build/provision resources
[working-directory('Terraform-OpenTofu')]
deploy-apply:
    tofu apply -auto-approve

# 5. Configure VMs / LXC containers (baseline)
[working-directory('ansible')]
pve-postconfig:
    @echo "\n⚙️ Configuring Proxmox VMs / LXC containers..."
    uv run ansible-playbook playbooks/ubuntu-docker.yaml
    uv run ansible-playbook playbooks/proxmox-nixos-ct.yaml

# Building a NixOS toplevel on macOS using Determinate Nix's native Linux builder needs BOTH:
#   1. a case-sensitive /nix volume:
#        curl -fsSL https://install.determinate.systems/nix | sh -s -- install macos --determinate --case-sensitive
#        Then request access to the native linux builder feature after logging in to FlakeHub.
#   2. `use-case-hack = false` in /etc/nix/nix.custom.conf
# Why? Because by default, macOS's /nix is case-insensitive and so it can't build a NixOS toplevel
# as buildEnv mangles the symlinks it merges.
#
# However, building on macOS using Determinate Nix is still riddled with other issues, hence the
# macOS-scoped recipe that skips flake checks and builds on the remote host. This works on any
# macOS + any Nix distro combination.

# Deploy Nix configuration to targets
[group('nix')]
[macos]
[working-directory('Nix')]
nix-deploy:
    nix run github:serokell/deploy-rs . -- --skip-checks --remote-build

# Deploy Nix configuration to targets
[group('nix')]
[linux]
[working-directory('Nix')]
nix-deploy:
    nix run github:serokell/deploy-rs .

# Update the Flake inputs
[group('nix')]
[working-directory('Nix')]
nix-update:
    nix flake update

# List all deployed resources (Helm releases and Flux resources)
[group('k8s')]
[working-directory('k8s')]
k8s-status:
    helm ls -A
    flux get all -A

# Show the latest cluster events
[group('k8s')]
[working-directory('k8s')]
k8s-events:
    kubectl get events -A --sort-by=.lastTimestamp

# Store the Grafana service-account token (for the Grafana MCP) in the OS keyring
[group('k8s')]
grafana-mcp-token:
    #!/usr/bin/env bash
    set -euo pipefail
    # Read silently so the token never lands in shell history
    read -rsp "Paste the Grafana service-account token: " tok
    echo
    [ -n "$tok" ] || { echo "No token provided." >&2; exit 1; }
    if [[ "$(uname)" == "Darwin" ]]; then
        security add-generic-password -a "$USER" -s grafana-mcp-token -U -w "$tok"
    elif command -v secret-tool >/dev/null 2>&1; then
        printf '%s' "$tok" | secret-tool store --label='Grafana MCP' service grafana-mcp-token
    else
        echo "No keyring found (need macOS 'security' or Linux 'secret-tool')." >&2
        echo "Install libsecret-tools, or store the token with 'pass'." >&2
        exit 1
    fi
    echo "✅ Stored in the OS keyring. Reload the Grafana MCP server in your AI assistant."

# TODO: add 'nix' recipes for 'agenix' to edit secrets or the like

# TODO: create recipes for sops (one for encrypting and one for decryption) that does this following some naming convention for all secrets
