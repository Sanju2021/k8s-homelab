# 🚀 Kubernetes Homelab on Hyper-V

A fully automated, production-grade Kubernetes cluster deployed on Dell Server with Windows Hyper-V, using Terraform for infrastructure provisioning and Ansible for configuration management.

## 📐 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Dell Server (Windows Hyper-V)                 │
│                                                                  │
│  ┌─────────────────── Kubernetes Cluster ──────────────────┐    │
│  │                                                          │    │
│  │  Control Plane (HAProxy VIP: 192.168.10.100)            │    │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────┐          │    │
│  │  │  master-01 │ │  master-02 │ │  master-03 │          │    │
│  │  │ .10.11     │ │ .10.12     │ │ .10.13     │          │    │
│  │  └────────────┘ └────────────┘ └────────────┘          │    │
│  │                                                          │    │
│  │  Worker Nodes                                           │    │
│  │  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐        │    │
│  │  │ w-01 │ │ w-02 │ │ w-03 │ │ w-04 │ │ w-05 │        │    │
│  │  │ .21  │ │ .22  │ │ .23  │ │ .24  │ │ .25  │        │    │
│  │  └──────┘ └──────┘ └──────┘ └──────┘ └──────┘        │    │
│  │  ┌──────┐ ┌──────┐                                     │    │
│  │  │ w-06 │ │ w-07 │                                     │    │
│  │  │ .26  │ │ .27  │                                     │    │
│  │  └──────┘ └──────┘                                     │    │
│  └──────────────────────────────────────────────────────┘ │    │
│                                                              │    │
│  ┌─────────────────── Ceph Cluster ────────────────────┐   │    │
│  │  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐     │   │    │
│  │  │ceph-1│ │ceph-2│ │ceph-3│ │ceph-4│ │ceph-5│     │   │    │
│  │  │ .31  │ │ .32  │ │ .33  │ │ .34  │ │ .35  │     │   │    │
│  │  └──────┘ └──────┘ └──────┘ └──────┘ └──────┘     │   │    │
│  └──────────────────────────────────────────────────┘ │   │    │
│                                                              │    │
└─────────────────────────────────────────────────────────────────┘
```

## 🖥️ Infrastructure Specification

| Role | Count | vCPU | RAM | OS Disk | Data Disk | IP Range |
|------|-------|------|-----|---------|-----------|----------|
| Kubernetes Master | 3 | 4 | 8 GB | 50 GB | — | 192.168.10.11-13 |
| Kubernetes Worker | 7 | 8 | 16 GB | 50 GB | — | 192.168.10.21-27 |
| Ceph Node | 5 | 4 | 8 GB | 50 GB | 200 GB (OSD) | 192.168.10.31-35 |
| HAProxy LB | 1 | 2 | 4 GB | 30 GB | — | 192.168.10.10 |

**Total Resources:** 64 vCPU | 164 GB RAM | ~2.28 TB Storage

## 📦 Deployed Workloads

| Application | Replicas | Storage | Namespace |
|-------------|----------|---------|-----------|
| NGINX Web Server | 5 | — | `webservers` |
| PostgreSQL | 5 | Ceph RBD (50 GB each) | `databases` |

## 🛠️ Technology Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| Hypervisor | Windows Hyper-V | 2022 |
| OS | Ubuntu Server | 24.04 LTS |
| IaC | Terraform | >= 1.7 |
| Config Mgmt | Ansible | >= 9.0 |
| Container Runtime | containerd | >= 1.7 |
| Kubernetes | kubeadm/k8s | 1.29 |
| CNI | Calico | >= 3.27 |
| Storage | Ceph / Rook | Reef (18.x) |
| Load Balancer | MetalLB | >= 0.14 |
| Ingress | NGINX Ingress | >= 1.10 |

## 📁 Repository Structure

```
k8s-homelab/
├── terraform/                    # Infrastructure provisioning
│   ├── modules/
│   │   ├── hyper-v-vm/           # Reusable VM module
│   │   └── networking/           # Virtual switch / network
│   └── environments/
│       └── production/           # Production environment config
├── ansible/                      # Configuration management
│   ├── inventories/production/   # Host inventory + group vars
│   ├── roles/
│   │   ├── common/               # Base OS hardening & packages
│   │   ├── kubernetes-master/    # Control plane setup
│   │   ├── kubernetes-worker/    # Worker node setup
│   │   ├── ceph/                 # Ceph cluster setup
│   │   ├── webserver/            # NGINX configuration
│   │   └── postgresql/           # PostgreSQL configuration
│   └── playbooks/                # Orchestration playbooks
├── kubernetes/                   # K8s manifests
│   ├── namespaces/
│   ├── storage/                  # StorageClass, PV, PVC
│   └── workloads/
│       ├── webservers/
│       └── postgresql/
├── docs/                         # Detailed documentation
└── scripts/                      # Helper scripts
```

## 🚀 Quick Start

### Prerequisites

1. **Windows Host Requirements:**
   - Windows Server 2022 or Windows 11 Pro/Enterprise
   - Hyper-V role enabled
   - At least 192 GB RAM, 64 CPU cores, 3 TB storage
   - [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.7
   - [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) >= 9.0 (via WSL2)
   - [kubectl](https://kubernetes.io/docs/tasks/tools/)

2. **WSL2 Setup** (required for Ansible):
   ```powershell
   wsl --install -d Ubuntu-24.04
   ```

3. **Terraform Hyper-V Provider** (run in PowerShell as Administrator):
   ```powershell
   # Enable WinRM for Terraform Hyper-V provider
   winrm quickconfig
   winrm set winrm/config/service/auth '@{Basic="true"}'
   winrm set winrm/config/service '@{AllowUnencrypted="true"}'
   ```

### Deployment Steps

```bash
# 1. Clone repository
git clone https://github.com/YOUR_USERNAME/k8s-homelab.git
cd k8s-homelab

# 2. Copy and edit configuration
cp terraform/environments/production/terraform.tfvars.example \
   terraform/environments/production/terraform.tfvars
# Edit terraform.tfvars with your settings

# 3. Provision VMs with Terraform
cd terraform/environments/production
terraform init
terraform plan
terraform apply

# 4. Run Ansible to configure all nodes
cd ../../../ansible
# Update inventories/production/hosts.ini with actual IPs
ansible-playbook playbooks/site.yml

# 5. Deploy Kubernetes workloads
kubectl apply -f kubernetes/namespaces/
kubectl apply -f kubernetes/storage/
kubectl apply -f kubernetes/workloads/
```

## 📖 Detailed Documentation

- [Terraform Infrastructure Guide](docs/terraform.md)
- [Ansible Configuration Guide](docs/ansible.md)
- [Kubernetes Setup Guide](docs/kubernetes.md)
- [Ceph Storage Guide](docs/ceph.md)
- [Workloads Deployment Guide](docs/workloads.md)
- [Network Architecture](docs/networking.md)
- [Troubleshooting Guide](docs/troubleshooting.md)

## 🔒 Security Notes

- All passwords and secrets should be stored in **Ansible Vault** — never in plaintext
- SSH key-based authentication enforced; password auth disabled
- UFW firewall configured on all nodes
- Kubernetes RBAC enabled
- Network policies enforced between namespaces

## 📄 License

MIT License — see [LICENSE](LICENSE)
