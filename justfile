# List available recipes
default:
  @just --list --unsorted

# Prepare the environment
bootstrap:
  @echo "⚙️ Installing Python tools and packages with uv...\n"
  uv sync
  @echo "⚙️ Installing Ansible collections...\n"
  # in the Ansible directory
  ansible-galaxy collection install -r Ansible/requirements.yml

# 1. Prepare Proxmox hosts for automation
[working-directory: 'Ansible']
pve-hosts:
  @echo "⚙️ Generating SSH keys...\n"
  ansible-playbook playbooks/generate-keys.yaml
  @echo "⚙️ Preparing Proxmox hosts...\n"
  # run with --ask-pass the first time
  ansible-playbook playbooks/proxmox-hosts.yaml

# Plan resources and required changes on Proxmox hosts
[working-directory: 'Terraform-OpenTofu']
vms-plan:
  terraform plan

# Build resources on Proxmox hosts + further configuration
[working-directory: 'Terraform-OpenTofu']
vms-apply:
  terraform apply -auto-approve
