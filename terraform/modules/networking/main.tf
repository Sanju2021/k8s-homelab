##############################################################################
# Networking Module — creates Hyper-V internal/external virtual switches
##############################################################################

terraform {
  required_providers {
    hyperv = {
      source  = "taliesins/hyperv"
      version = "~> 1.2"
    }
  }
}

variable "internal_switch_name" {
  description = "Name of the internal Hyper-V switch for cluster communication"
  type        = string
  default     = "k8s-internal"
}

variable "external_switch_name" {
  description = "Name of the external Hyper-V switch bound to a physical NIC"
  type        = string
  default     = "k8s-external"
}

variable "physical_adapter_name" {
  description = "Name of the physical network adapter on the Hyper-V host"
  type        = string
  default     = "Ethernet"
}

# External switch — VMs get access to the physical network
resource "hyperv_network_switch" "external" {
  name                                    = var.external_switch_name
  notes                                   = "External switch for Kubernetes cluster — bound to ${var.physical_adapter_name}"
  allow_management_os                     = true
  enable_embedded_teaming                 = false
  enable_iov                              = false
  enable_packet_direct                    = false
  minimum_bandwidth_mode                  = "None"
  switch_type                             = "External"
  net_adapter_names                       = [var.physical_adapter_name]
  default_flow_minimum_bandwidth_absolute = 0
  default_flow_minimum_bandwidth_weight   = 0
  default_queue_vmmq_enabled              = false
  default_queue_vmmq_queue_pairs          = 16
  default_queue_vrss_enabled              = false
}

output "external_switch_name" {
  value = hyperv_network_switch.external.name
}
