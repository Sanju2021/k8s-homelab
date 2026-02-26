##############################################################################
# Production Variables
##############################################################################

# ─── Hyper-V Host Connection ───────────────────────────────────────────────
variable "hyperv_host" {
  description = "IP or hostname of the Hyper-V host (Windows Server)"
  type        = string
}

variable "hyperv_username" {
  description = "Windows username with Hyper-V administrator privileges"
  type        = string
  default     = "Administrator"
}

variable "hyperv_password" {
  description = "Password for the Hyper-V administrator account"
  type        = string
  sensitive   = true
}

# ─── Network ────────────────────────────────────────────────────────────────
variable "external_switch_name" {
  description = "Name for the Hyper-V external virtual switch"
  type        = string
  default     = "k8s-external"
}

variable "physical_adapter_name" {
  description = "Physical NIC name on the Hyper-V host to bind external switch"
  type        = string
  default     = "Ethernet"
}

variable "default_gateway" {
  description = "Default gateway for all VMs"
  type        = string
  default     = "192.168.10.1"
}

variable "dns_servers" {
  description = "DNS servers for all VMs"
  type        = list(string)
  default     = ["192.168.10.1", "8.8.8.8"]
}

# ─── Storage Paths ──────────────────────────────────────────────────────────
variable "vhd_base_path" {
  description = "Base Windows path where VHD files will be stored"
  type        = string
  default     = "C:\\HyperV\\VMs"
}

variable "ubuntu_iso_path" {
  description = "Full Windows path to the Ubuntu 24.04 LTS ISO"
  type        = string
  default     = "C:\\ISOs\\ubuntu-24.04-live-server-amd64.iso"
}

# ─── SSH ────────────────────────────────────────────────────────────────────
variable "ssh_public_key" {
  description = "SSH public key to inject into all VMs"
  type        = string
}

# ─── VM Sizing ──────────────────────────────────────────────────────────────
variable "master_cpu" {
  description = "vCPUs per Kubernetes master node"
  type        = number
  default     = 4
}

variable "master_memory_mb" {
  description = "Memory per Kubernetes master node in MB"
  type        = number
  default     = 8192
}

variable "worker_cpu" {
  description = "vCPUs per Kubernetes worker node"
  type        = number
  default     = 8
}

variable "worker_memory_mb" {
  description = "Memory per Kubernetes worker node in MB"
  type        = number
  default     = 16384
}

variable "ceph_cpu" {
  description = "vCPUs per Ceph storage node"
  type        = number
  default     = 4
}

variable "ceph_memory_mb" {
  description = "Memory per Ceph storage node in MB"
  type        = number
  default     = 8192
}
