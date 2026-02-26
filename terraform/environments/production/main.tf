##############################################################################
# Production Environment — Kubernetes + Ceph on Hyper-V
##############################################################################

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    hyperv = {
      source  = "taliesins/hyperv"
      version = "~> 1.2"
    }
  }

  # Uncomment to use a remote backend (recommended for team use)
  # backend "s3" {
  #   bucket = "terraform-state-k8s-homelab"
  #   key    = "production/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

##############################################################################
# Provider — connects to the Hyper-V host via WinRM
##############################################################################
provider "hyperv" {
  user     = var.hyperv_username
  password = var.hyperv_password
  host     = var.hyperv_host
  port     = 5985
  https    = false
  insecure = true
  use_ntlm = true
  tls_server_name = ""
  cacert_path     = ""
  cert_path       = ""
  key_path        = ""
  script_path     = "C:/Temp/terraform_%RAND%.cmd"
  timeout         = "30s"
}

##############################################################################
# Networking
##############################################################################
module "networking" {
  source                = "../../modules/networking"
  external_switch_name  = var.external_switch_name
  physical_adapter_name = var.physical_adapter_name
}

##############################################################################
# HAProxy Load Balancer (API Server VIP)
##############################################################################
module "haproxy" {
  source          = "../../modules/hyper-v-vm"
  vm_name         = "k8s-haproxy"
  cpu_count       = 2
  memory_mb       = 4096
  os_disk_size_gb = 30
  switch_name     = module.networking.external_switch_name
  vhd_path        = var.vhd_base_path
  iso_path        = var.ubuntu_iso_path
  ip_address      = "192.168.10.10"
  ip_gateway      = var.default_gateway
  dns_servers     = var.dns_servers
  ssh_public_key  = var.ssh_public_key
}

##############################################################################
# Kubernetes Master Nodes (x3)
##############################################################################
module "k8s_masters" {
  source   = "../../modules/hyper-v-vm"
  for_each = {
    "k8s-master-01" = "192.168.10.11"
    "k8s-master-02" = "192.168.10.12"
    "k8s-master-03" = "192.168.10.13"
  }

  vm_name         = each.key
  cpu_count       = var.master_cpu
  memory_mb       = var.master_memory_mb
  os_disk_size_gb = 50
  switch_name     = module.networking.external_switch_name
  vhd_path        = var.vhd_base_path
  iso_path        = var.ubuntu_iso_path
  ip_address      = each.value
  ip_gateway      = var.default_gateway
  dns_servers     = var.dns_servers
  ssh_public_key  = var.ssh_public_key

  depends_on = [module.networking]
}

##############################################################################
# Kubernetes Worker Nodes (x7)
##############################################################################
module "k8s_workers" {
  source   = "../../modules/hyper-v-vm"
  for_each = {
    "k8s-worker-01" = "192.168.10.21"
    "k8s-worker-02" = "192.168.10.22"
    "k8s-worker-03" = "192.168.10.23"
    "k8s-worker-04" = "192.168.10.24"
    "k8s-worker-05" = "192.168.10.25"
    "k8s-worker-06" = "192.168.10.26"
    "k8s-worker-07" = "192.168.10.27"
  }

  vm_name         = each.key
  cpu_count       = var.worker_cpu
  memory_mb       = var.worker_memory_mb
  os_disk_size_gb = 50
  switch_name     = module.networking.external_switch_name
  vhd_path        = var.vhd_base_path
  iso_path        = var.ubuntu_iso_path
  ip_address      = each.value
  ip_gateway      = var.default_gateway
  dns_servers     = var.dns_servers
  ssh_public_key  = var.ssh_public_key

  depends_on = [module.networking]
}

##############################################################################
# Ceph Storage Nodes (x5) — each has a 200 GB OSD data disk
##############################################################################
module "ceph_nodes" {
  source   = "../../modules/hyper-v-vm"
  for_each = {
    "ceph-node-01" = "192.168.10.31"
    "ceph-node-02" = "192.168.10.32"
    "ceph-node-03" = "192.168.10.33"
    "ceph-node-04" = "192.168.10.34"
    "ceph-node-05" = "192.168.10.35"
  }

  vm_name           = each.key
  cpu_count         = var.ceph_cpu
  memory_mb         = var.ceph_memory_mb
  os_disk_size_gb   = 50
  data_disk_size_gb = 200  # Ceph OSD disk
  switch_name       = module.networking.external_switch_name
  vhd_path          = var.vhd_base_path
  iso_path          = var.ubuntu_iso_path
  ip_address        = each.value
  ip_gateway        = var.default_gateway
  dns_servers       = var.dns_servers
  ssh_public_key    = var.ssh_public_key

  depends_on = [module.networking]
}
