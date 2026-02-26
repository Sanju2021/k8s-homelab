output "vm_name" {
  description = "Name of the created VM"
  value       = hyperv_machine_instance.vm.name
}

output "ip_address" {
  description = "IP address assigned to the VM"
  value       = var.ip_address
}

output "os_disk_path" {
  description = "Path to the OS VHD"
  value       = hyperv_vhd.os_disk.path
}

output "data_disk_path" {
  description = "Path to the data VHD (if created)"
  value       = var.data_disk_size_gb > 0 ? hyperv_vhd.data_disk[0].path : null
}
