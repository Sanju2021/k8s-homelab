variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
}

variable "cpu_count" {
  description = "Number of virtual CPUs"
  type        = number
  default     = 4
}

variable "memory_mb" {
  description = "Memory in megabytes"
  type        = number
  default     = 8192
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB"
  type        = number
  default     = 50
}

variable "data_disk_size_gb" {
  description = "Additional data disk size in GB (0 = no data disk)"
  type        = number
  default     = 0
}

variable "switch_name" {
  description = "Hyper-V virtual switch name"
  type        = string
}

variable "vhd_path" {
  description = "Base path to store VHD files"
  type        = string
}

variable "iso_path" {
  description = "Path to Ubuntu 24.04 ISO on the Hyper-V host"
  type        = string
}

variable "ip_address" {
  description = "Static IP address for the VM"
  type        = string
}

variable "ip_gateway" {
  description = "Default gateway IP"
  type        = string
}

variable "dns_servers" {
  description = "List of DNS servers"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "subnet_prefix" {
  description = "Subnet prefix length (e.g. 24 for /24)"
  type        = number
  default     = 24
}

variable "ssh_public_key" {
  description = "SSH public key content for cloud-init"
  type        = string
}

variable "cloud_init_path" {
  description = "Path to cloud-init user-data file"
  type        = string
  default     = ""
}

variable "generation" {
  description = "Hyper-V VM generation (1 or 2)"
  type        = number
  default     = 2
}

variable "enable_secure_boot" {
  description = "Enable Secure Boot (Generation 2 only)"
  type        = bool
  default     = false
}
