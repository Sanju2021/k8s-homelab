# Terraform Infrastructure Guide

This document explains how Terraform provisions all virtual machines on Windows Hyper-V for the Kubernetes homelab.

## Prerequisites

### On the Windows Hyper-V Host

1. **Enable Hyper-V** (if not already active):
   ```powershell
   # Run as Administrator
   Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
   ```

2. **Enable WinRM** (required for Terraform Hyper-V provider):
   ```powershell
   winrm quickconfig -q
   winrm set winrm/config/service/auth '@{Basic="true"}'
   winrm set winrm/config/service '@{AllowUnencrypted="true"}'
   winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="1024"}'
   Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value true
   Set-Item WSMan:\localhost\Service\Auth\Basic -Value true
   ```

3. **Create the VHD storage directory**:
   ```powershell
   New-Item -ItemType Directory -Path "D:\HyperV\VMs" -Force
   New-Item -ItemType Directory -Path "D:\ISOs" -Force
   New-Item -ItemType Directory -Path "C:\Temp" -Force
   ```

4. **Download Ubuntu 24.04 ISO**:
   ```powershell
   # Download Ubuntu 24.04 LTS Server ISO
   $url = "https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso"
   Invoke-WebRequest -Uri $url -OutFile "D:\ISOs\ubuntu-24.04-live-server-amd64.iso"
   ```

5. **Check physical NIC name** (you'll need this for `terraform.tfvars`):
   ```powershell
   Get-NetAdapter | Select-Object Name, InterfaceDescription, Status
   ```

### On your management machine (WSL2 or Linux)

```bash
# Install Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Generate SSH key pair
ssh-keygen -t ed25519 -C "k8s-homelab" -f ~/.ssh/k8s-homelab
cat ~/.ssh/k8s-homelab.pub  # Copy this into terraform.tfvars
```

## Configuration

Copy the example vars file and fill in your values:

```bash
cd terraform/environments/production
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
```

Key settings to configure:

| Variable | Description | Example |
|----------|-------------|---------|
| `hyperv_host` | IP of your Dell server | `192.168.1.50` |
| `hyperv_password` | Windows admin password | (use a strong password) |
| `physical_adapter_name` | NIC name from `Get-NetAdapter` | `Ethernet` |
| `vhd_base_path` | Where to store VHDs | `D:\HyperV\VMs` |
| `ssh_public_key` | Your public key content | `ssh-ed25519 AAAA...` |

## Deployment

```bash
cd terraform/environments/production

# Download providers
terraform init

# Preview changes
terraform plan

# Apply (creates all VMs — takes 10-20 minutes)
terraform apply

# View outputs (IPs for Ansible inventory)
terraform output
```

## VM Inventory Summary

After `terraform apply`, you'll have 16 VMs:

| VM | IP | Role | CPU | RAM |
|----|-----|------|-----|-----|
| k8s-haproxy | 192.168.10.10 | Load Balancer | 2 | 4 GB |
| k8s-master-01 | 192.168.10.11 | Control Plane | 4 | 8 GB |
| k8s-master-02 | 192.168.10.12 | Control Plane | 4 | 8 GB |
| k8s-master-03 | 192.168.10.13 | Control Plane | 4 | 8 GB |
| k8s-worker-01 to 07 | 192.168.10.21-27 | Worker | 8 | 16 GB |
| ceph-node-01 to 05 | 192.168.10.31-35 | Storage | 4 | 8 GB |

## Destroying Infrastructure

```bash
# Destroy ALL VMs (destructive — all data will be lost!)
terraform destroy
```

## Troubleshooting

**WinRM Connection Refused**: Ensure the Windows Firewall allows WinRM:
```powershell
netsh advfirewall firewall add rule name="WinRM-HTTP" dir=in localport=5985 protocol=TCP action=allow
```

**VHD Path Errors**: Ensure the directory exists and the Hyper-V service account has write permissions to it.

**VM Boot Issues**: Verify the Ubuntu ISO path is correct and accessible. Generation 2 VMs require UEFI-compatible ISOs; Ubuntu 24.04 supports this natively.
