output "haproxy_ip" {
  description = "HAProxy load balancer IP (Kubernetes API VIP)"
  value       = module.haproxy.ip_address
}

output "master_ips" {
  description = "Map of master node names to IP addresses"
  value       = { for k, v in module.k8s_masters : k => v.ip_address }
}

output "worker_ips" {
  description = "Map of worker node names to IP addresses"
  value       = { for k, v in module.k8s_workers : k => v.ip_address }
}

output "ceph_ips" {
  description = "Map of Ceph node names to IP addresses"
  value       = { for k, v in module.ceph_nodes : k => v.ip_address }
}

output "ansible_inventory_hint" {
  description = "Hint for building Ansible inventory"
  value = <<-EOT
    Populate ansible/inventories/production/hosts.ini with:
    HAProxy:  ${module.haproxy.ip_address}
    Masters:  ${join(", ", [for v in module.k8s_masters : v.ip_address])}
    Workers:  ${join(", ", [for v in module.k8s_workers : v.ip_address])}
    Ceph:     ${join(", ", [for v in module.ceph_nodes : v.ip_address])}
  EOT
}
