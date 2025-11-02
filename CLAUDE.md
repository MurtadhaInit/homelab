# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a homelab infrastructure-as-code repository that provisions and manages Proxmox VE virtual machines using Terraform/OpenTofu and Ansible. The workflow follows a two-phase approach: first using Ansible to bootstrap Proxmox hosts, then using Terraform to create and configure VMs.

## Architecture

### Three-Stage Workflow

1. **Local SSH Key Generation** (Ansible): Generate SSH key pairs locally for automation and regular users
2. **Proxmox Host Preparation** (Ansible): Bootstrap Proxmox hosts with users, SSH keys, and sudo configuration
3. **VM Provisioning & Configuration** (Terraform + Ansible): Create VMs using Terraform with Cloud-Init, then configure them with Ansible

### Key Design Decisions

- **Two User Pattern**: An "automation" user (passwordless sudo, for Ansible/Terraform) and a "regular" user (with password, for manual access) are created on both Proxmox hosts and VMs
- **Cloud-Init Integration**: VMs are provisioned from Ubuntu cloud images with Cloud-Init for initial setup (qemu-guest-agent, SSH keys, networking)
- **PAM Authentication**: The Terraform Proxmox provider uses PAM user authentication (not API tokens) for SSH-based provisioning
- **Ansible Directory Isolation**: The Ansible directory must be added as a separate workspace folder in VS Code for the Ansible extension to properly recognize `ansible.cfg`

## Common Commands

### Environment Setup

```bash
# Install global tools (ansible with ansible-core and ansible-lint executables)
just bootstrap

# Or manually with uv:
uv tool install ansible --with-executables-from ansible-core --with-executables-from ansible-lint
```

### Proxmox Host Bootstrapping

```bash
# Generate SSH keys + prepare Proxmox hosts (users, permissions, storage)
just pve-hosts

# Or run individually from Ansible directory:
cd Ansible
ansible-playbook playbooks/generate-keys.yaml
ansible-playbook playbooks/proxmox-hosts.yaml --ask-pass  # --ask-pass only needed first time
```

### VM Lifecycle Management

```bash
# Plan Terraform changes
just vms-plan

# Apply Terraform changes (creates/updates VMs)
just vms-apply

# Or directly from Terraform-OpenTofu directory:
cd Terraform-OpenTofu
terraform plan
terraform apply -auto-approve
```

### Post-Provisioning Configuration

```bash
# Configure Docker on ubuntu-docker VM
cd Ansible
ansible-playbook playbooks/ubuntu-docker.yaml
```

## Directory Structure

```
.
├── Ansible/
│   ├── ansible.cfg              # Ansible configuration (must be in workspace root for VS Code extension)
│   ├── inventory/hosts.ini      # Inventory defining proxmox_hosts and VM groups
│   ├── playbooks/
│   │   ├── generate-keys.yaml   # Generates SSH keys locally for automation/regular users
│   │   ├── proxmox-hosts.yaml   # Bootstraps Proxmox hosts (users, SSH, permissions, PVE setup)
│   │   ├── ubuntu-docker.yaml   # Post-provision Docker installation on VMs
│   │   └── tasks/               # Reusable task files
│   └── vars/
│       ├── secrets.yaml         # Ansible Vault encrypted secrets (passwords, email)
│       └── ssh_users.yaml       # SSH user definitions (paths to keys)
│
├── Terraform-OpenTofu/
│   ├── providers.tf             # Proxmox provider config (bpg/proxmox), uses PAM auth + SSH
│   ├── hosts.tf                 # Proxmox host-level resources (apt repos, USB hardware mappings)
│   ├── vm-variables.tf          # Shared variables for VMs (SSH keys, usernames, gateway)
│   ├── ubuntu-template.tf       # Ubuntu cloud image template (VM ID 500, template=true)
│   ├── ubuntu-docker.tf         # Docker host VM (VM ID 600, with Cloud-Init user-data)
│   ├── windows-server.tf        # Windows Server VM definitions
│   └── *.auto.tfvars            # Auto-loaded Terraform variable values (gitignored)
│
└── justfile                     # Task runner with common workflows
```

## Important Configuration Details

### Python & Dependency Management

- **Package Manager**: Uses `uv` for Python package and tool management
- **Ansible Installation**: Installed globally via `uv tool install` with executables from `ansible-core` and `ansible-lint`
- **Standalone Scripts**: Python utilities (like `hash-password.py`) use PEP 723 inline script metadata for self-contained dependency management
- **VS Code Integration**: Ansible extension configured to use system `python3` interpreter

### Ansible

- **Inventory Location**: `Ansible/inventory/hosts.ini`
- **Host Groups**: `proxmox_hosts`, `ubuntu-docker-vm`
- **Vault Secrets**: Use `ansible-vault edit Ansible/vars/secrets.yaml` to modify encrypted variables
- **Remote Users**:
  - Proxmox hosts: `root` (first run with `--ask-pass`) or automation user (subsequent runs)
  - VMs: `automator` (defined in `vm_automation_username`)

### Terraform/OpenTofu

- **Provider**: Uses `bpg/proxmox` v0.85.1
- **VM ID Ranges**: Templates use 500-599, production VMs use 600+
- **SSH Agent**: Provider is configured to use SSH agent authentication
- **Cloud-Init**: User-data snippets are stored in Proxmox local storage under `snippets` content type
- **Sensitive Variables**: Store in `*.auto.tfvars` files (gitignored) or pass via environment variables
- **Password Hashing**: `utils/hash-password.py` uses `uv` with inline script metadata (PEP 723) for dependency management - automatically installs `passlib` when executed

### Cloud-Init User Data Pattern

VMs use `proxmox_virtual_environment_file` resources with `source_raw` blocks to embed Cloud-Init YAML. Standard setup includes:

- Create automation user with SSH key, passwordless sudo
- Install and enable qemu-guest-agent
- Configure static IP via `initialization.ip_config`
- Disable root login and password authentication
- Run package updates and conditional reboots

## Testing

Run Ansible playbooks with `--check` mode to dry-run:

```bash
ansible-playbook playbooks/proxmox-hosts.yaml --check
```

Use `terraform plan` to preview infrastructure changes before applying.

## Security Notes

- SSH password authentication is disabled on Proxmox hosts after initial setup
- All remote access requires SSH keys (stored in `~/.ssh/keys/` by default)
- Secrets are managed via Ansible Vault (`Ansible/vars/secrets.yaml`)
- Terraform variable files with sensitive data (`*.auto.tfvars`) are gitignored
- Proxmox uses self-signed TLS certificates (`insecure = true` in provider config)
