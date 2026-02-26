##############################################################################
# Hyper-V VM Module
# Creates a single Ubuntu 24.04 VM on Windows Hyper-V with cloud-init support
##############################################################################

terraform {
  required_providers {
    hyperv = {
      source  = "taliesins/hyperv"
      version = "~> 1.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

# ─────────────────────────────────────────────
# Cloud-Init user-data (meta-data + user-data)
# ─────────────────────────────────────────────
locals {
  hostname = var.vm_name

  # cloud-init network config
  network_config = <<-EOT
    version: 2
    ethernets:
      eth0:
        dhcp4: false
        addresses:
          - ${var.ip_address}/${var.subnet_prefix}
        gateway4: ${var.ip_gateway}
        nameservers:
          addresses: ${jsonencode(var.dns_servers)}
  EOT

  # cloud-init user-data
  user_data = <<-EOT
    #cloud-config
    hostname: ${local.hostname}
    fqdn: ${local.hostname}.local
    manage_etc_hosts: true

    users:
      - name: ubuntu
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/bash
        ssh_authorized_keys:
          - ${var.ssh_public_key}
        lock_passwd: false

    package_update: true
    package_upgrade: true
    packages:
      - qemu-guest-agent
      - curl
      - wget
      - vim
      - git
      - net-tools
      - ntp
      - open-vm-tools

    runcmd:
      - systemctl enable qemu-guest-agent
      - systemctl start qemu-guest-agent
      - sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
      - systemctl restart sshd

    power_state:
      mode: reboot
      condition: True
  EOT
}

# Write cloud-init ISO files locally for pickup by Hyper-V
resource "local_file" "user_data" {
  content  = local.user_data
  filename = "${path.module}/../../tmp/${var.vm_name}-user-data"
}

resource "local_file" "network_config" {
  content  = local.network_config
  filename = "${path.module}/../../tmp/${var.vm_name}-network-config"
}

# ─────────────────────────────────────────────
# OS VHD (copied from base Ubuntu image)
# ─────────────────────────────────────────────
resource "hyperv_vhd" "os_disk" {
  path = "${var.vhd_path}\\${var.vm_name}\\os.vhdx"
  size = var.os_disk_size_gb * 1024 * 1024 * 1024  # bytes

  lifecycle {
    ignore_changes = [size]
  }
}

# ─────────────────────────────────────────────
# Optional data disk (for Ceph OSD nodes)
# ─────────────────────────────────────────────
resource "hyperv_vhd" "data_disk" {
  count = var.data_disk_size_gb > 0 ? 1 : 0
  path  = "${var.vhd_path}\\${var.vm_name}\\data.vhdx"
  size  = var.data_disk_size_gb * 1024 * 1024 * 1024

  lifecycle {
    ignore_changes = [size]
  }
}

# ─────────────────────────────────────────────
# Virtual Machine
# ─────────────────────────────────────────────
resource "hyperv_machine_instance" "vm" {
  name                 = var.vm_name
  generation           = var.generation
  processor_count      = var.cpu_count
  static_memory        = true
  memory_startup_bytes = var.memory_mb * 1024 * 1024

  wait_for_state_timeout  = 10
  wait_for_ips_timeout    = 10

  vm_firmware {
    enable_secure_boot = var.enable_secure_boot
    boot_order {
      boot_type           = "HardDiskDrive"
      controller_number   = 0
      controller_location = 0
    }
  }

  vm_processor {
    count                        = var.cpu_count
    expose_virtualization_extensions = false
  }

  network_adaptors {
    name        = "Network Adapter"
    switch_name = var.switch_name
  }

  hard_disk_drives {
    controller_type     = "Scsi"
    controller_number   = 0
    controller_location = 0
    path                = hyperv_vhd.os_disk.path
  }

  dynamic "hard_disk_drives" {
    for_each = var.data_disk_size_gb > 0 ? [1] : []
    content {
      controller_type     = "Scsi"
      controller_number   = 0
      controller_location = 1
      path                = hyperv_vhd.data_disk[0].path
    }
  }

  depends_on = [
    hyperv_vhd.os_disk,
    hyperv_vhd.data_disk,
  ]
}
