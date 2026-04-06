# List available recipes
default:
    @just --list --unsorted

# Prepare the environment
bootstrap:
    mise install
    @echo "⚙️ Installing Python tools and packages with uv...\n"
    uv sync
    @echo "⚙️ Installing Ansible collections...\n"
    # in the Ansible directory
    ansible-galaxy collection install -r Ansible/requirements.yml

# Generate SSH key pairs locally for the management of Proxmox hosts and VMs
generate-keys:
    #!/usr/bin/env bash
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

# 1. Prepare Proxmox hosts for automation
[working-directory('Ansible')]
pve-hosts:
    @echo "⚙️ Generating SSH keys...\n"
    ansible-playbook playbooks/generate-keys.yaml
    @echo "⚙️ Preparing Proxmox hosts...\n"
    # run with --ask-pass the first time
    ansible-playbook playbooks/proxmox-hosts.yaml

# Plan resources and required changes on Proxmox hosts
[working-directory('Terraform-OpenTofu')]
vms-plan:
    tofu plan

# Build resources on Proxmox hosts + further configuration
[working-directory('Terraform-OpenTofu')]
vms-apply:
    tofu apply -auto-approve
