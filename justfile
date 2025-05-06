
global_python_deps := "ansible ansible-lint passlib"
# pyenv_python_interpreter := `pyenv which python`

# List available recipes
default:
  @just --list --unsorted

# Prepare the local environment
bootstrap:
  @echo "⚙️ Installing/upgrading global Python dependencies: {{global_python_deps}}\n"
  pyenv exec pip install --upgrade pip {{global_python_deps}}

# Prepare Proxmox hosts for automation
[working-directory: 'Ansible']
pve-hosts:
  @echo "⚙️ Generating SSH keys...\n"
  ansible-playbook playbooks/generate-keys.yaml
  @echo "⚙️ Preparing Proxmox hosts...\n"
  ansible-playbook playbooks/proxmox-hosts.yaml

# Plan resources and required changed on Proxmox hosts
[working-directory: 'Terraform-OpenTofu']
vms-plan:
  terraform plan

# Build resources on Proxmox hosts + further configuration
[working-directory: 'Terraform-OpenTofu']
vms-apply:
  terraform apply -auto-approve