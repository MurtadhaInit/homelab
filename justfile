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

# 2. Install the generated public SSH key on Proxmox hosts (root password prompt on first run only)
[working-directory('ansible')]
copy-keys:
    #!/usr/bin/env bash
    set -euo pipefail
    uv run ansible-inventory --list \
      | jq -r '.proxmox_hosts.hosts[] as $h | ._meta.hostvars[$h].ansible_host' \
      | while read -r host; do
            ssh-copy-id -i ~/.ssh/keys/proxmox-hosts.pub "root@$host"
        done

# TODO: add recipes to SSH, generate a token, and store it in secret TF / Ansible files

# 3. Prepare Proxmox hosts
[working-directory('ansible')]
pve-hosts:
    @echo "\n⚙️ Configuring Proxmox hosts..."
    uv run ansible-playbook playbooks/proxmox-hosts.yaml
    uv run ansible-playbook playbooks/proxmox-fs.yaml
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

# Deploy Nix configuration to targets
[group('nix')]
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
# and consider eliminating Ansible Vault in favour of SOPS.
