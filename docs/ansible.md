# Ansible Configuration Guide

Ansible handles all OS-level configuration after Terraform provisions the VMs.

## Prerequisites

Install Ansible in WSL2 or Linux:

```bash
# Install Ansible and required collections
pip install ansible ansible-lint
cd ansible/
ansible-galaxy collection install -r requirements.yml
```

## Secrets Management with Ansible Vault

Never store passwords in plain text. Use Ansible Vault:

```bash
# Create vault password file (don't commit this!)
echo "YOUR_VAULT_PASSWORD" > ansible/.vault_pass
chmod 600 ansible/.vault_pass
echo "ansible/.vault_pass" >> .gitignore

# Create encrypted vault file
ansible-vault create ansible/inventories/production/group_vars/all_vault.yml \
  --vault-password-file ansible/.vault_pass

# Add these variables to the vault file:
# vault_ceph_dashboard_password: "STRONG_PASSWORD"
# vault_haproxy_stats_password: "STRONG_PASSWORD"
# vault_k8s_bootstrap_token: ""  # Filled automatically

# Edit vault file
ansible-vault edit ansible/inventories/production/group_vars/all_vault.yml \
  --vault-password-file ansible/.vault_pass

# View encrypted content
ansible-vault view ansible/inventories/production/group_vars/all_vault.yml \
  --vault-password-file ansible/.vault_pass
```

## Running Playbooks

```bash
cd ansible/

# Test connectivity first
ansible all_nodes -m ping --vault-password-file .vault_pass

# Run everything (full deployment)
ansible-playbook playbooks/site.yml --vault-password-file .vault_pass

# Run only specific phases using tags
ansible-playbook playbooks/site.yml --tags phase1,phase2 --vault-password-file .vault_pass
ansible-playbook playbooks/site.yml --tags kubernetes --vault-password-file .vault_pass
ansible-playbook playbooks/site.yml --tags ceph --vault-password-file .vault_pass
ansible-playbook playbooks/site.yml --tags workloads --vault-password-file .vault_pass

# Limit to specific hosts
ansible-playbook playbooks/site.yml --limit k8s_masters --vault-password-file .vault_pass
ansible-playbook playbooks/site.yml --limit 192.168.10.21 --vault-password-file .vault_pass

# Dry-run (check mode)
ansible-playbook playbooks/site.yml --check --diff --vault-password-file .vault_pass

# Verbose output for debugging
ansible-playbook playbooks/site.yml -vvv --vault-password-file .vault_pass
```

## Role Descriptions

| Role | Hosts | Description |
|------|-------|-------------|
| `common` | all | Package updates, kernel tuning, swap off, UFW, SSH hardening |
| `kubernetes-master` | k8s_masters | containerd, kubeadm init/join, Calico CNI |
| `kubernetes-worker` | k8s_workers | containerd, kubeadm join, node labeling |
| `ceph` | ceph_nodes | cephadm bootstrap, OSD deployment, K8s pool |
| `rook-ceph-operator` | k8s_masters[0] | Helm install Rook, StorageClass apply |
| `metallb` | k8s_masters[0] | MetalLB install + IP pool config |
| `ingress-nginx` | k8s_masters[0] | NGINX Ingress Controller via Helm |
| `deploy-workloads` | k8s_masters[0] | Apply all K8s manifests |

## Ad-hoc Commands

```bash
# Reboot all workers simultaneously
ansible k8s_workers -m reboot --vault-password-file .vault_pass

# Check disk space on all nodes
ansible all_nodes -m command -a "df -h" --vault-password-file .vault_pass

# Run an arbitrary command
ansible ceph_nodes -m shell -a "ceph status" --vault-password-file .vault_pass

# Copy a file to all masters
ansible k8s_masters -m copy -a "src=myfile dest=/tmp/myfile"

# Gather facts from all nodes
ansible all_nodes -m setup --vault-password-file .vault_pass
```
