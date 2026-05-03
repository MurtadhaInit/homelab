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

# 3. Prepare Proxmox hosts
[working-directory('ansible')]
pve-hosts:
    @echo "\n⚙️ Configuring Proxmox hosts..."
    uv run ansible-playbook playbooks/proxmox-hosts.yaml
    uv run ansible-playbook playbooks/proxmox-fs.yaml
    uv run ansible-playbook playbooks/proxmox-node-exporter.yaml

# Plan resources and required changes on Proxmox hosts
[working-directory('Terraform-OpenTofu')]
vms-plan:
    tofu plan

# Build resources on Proxmox hosts + further configuration
[working-directory('Terraform-OpenTofu')]
vms-apply:
    tofu apply -auto-approve

# 1. Supply the Age private key to the cluster to allow Flux to decrypt SOPS-encrypted Secret resources
[working-directory('k8s')]
seed-sops-secret:
    kubectl create namespace flux-system
    cat ~/.ssh/keys/sops-age.txt | kubectl create secret generic sops-age --namespace=flux-system --from-file=sops-age.agekey=/dev/stdin

# 2. Bootstrap the cluster with Flux (install Flux controllers and every other resource defined in the repo)
[working-directory('k8s')]
flux-bootstrap:
    flux bootstrap github --owner=$GITHUB_USER --repository=homelab --branch=main --personal --path=k8s/clusters/homelab

# TODO: create recipes for sops (one for encrypting and one for decryption) that does this following some naming convention for all secrets
# and consider eliminating Ansible Vault in favour of SOPS.
