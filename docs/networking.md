# Network Architecture

## IP Address Plan

| Subnet | Range | Purpose |
|--------|-------|---------|
| Physical LAN | 192.168.1.0/24 | Hyper-V host, management |
| Cluster Network | 192.168.10.0/24 | All VMs |
| Pod CIDR | 10.244.0.0/16 | Kubernetes pods (Calico) |
| Service CIDR | 10.96.0.0/12 | Kubernetes services |
| MetalLB Pool | 192.168.10.200-220 | LoadBalancer IPs |

## VM IP Assignments

| IP | Hostname | Role |
|----|----------|------|
| 192.168.10.10 | k8s-haproxy | HAProxy (K8s API VIP) |
| 192.168.10.11 | k8s-master-01 | Control Plane (bootstrap) |
| 192.168.10.12 | k8s-master-02 | Control Plane |
| 192.168.10.13 | k8s-master-03 | Control Plane |
| 192.168.10.21-27 | k8s-worker-01..07 | Worker nodes |
| 192.168.10.31-35 | ceph-node-01..05 | Ceph storage |
| 192.168.10.200 | (MetalLB) | NGINX Ingress LB IP |

## Traffic Flow

### External → Web Application

```
User's Browser
    │
    ▼ HTTP/HTTPS
192.168.10.200 (MetalLB LB → NGINX Ingress Controller)
    │
    ▼ Routes by hostname (webserver.homelab.local)
ClusterIP Service: nginx-webserver:80
    │
    ▼ Round-robin to pods
nginx-webserver pods (5 replicas across workers)
```

### Application → PostgreSQL

```
nginx pods (namespace: webservers)
    │
    ▼ port 5432
ClusterIP Service: postgresql.databases.svc.cluster.local
    │
    ▼ Round-robin
postgresql pods (namespace: databases)
    │
    ▼ ReadWriteOnce PVC
Ceph RBD volumes (via Rook-Ceph CSI)
    │
    ▼
Ceph OSD disks on ceph-node-01..05
```

### kubectl → Kubernetes API

```
kubectl (management machine)
    │
    ▼ HTTPS:6443
192.168.10.10 (HAProxy)
    │
    ▼ TCP passthrough
master-01:6443  master-02:6443  master-03:6443
    │
    ▼
etcd cluster (distributed across all 3 masters)
```

## DNS

DNS for workloads is handled by CoreDNS running inside the cluster. Service names resolve automatically within the cluster:

- `postgresql` — resolves within `databases` namespace
- `postgresql.databases.svc.cluster.local` — resolves from any namespace
- `postgresql-0.postgresql-headless.databases.svc.cluster.local` — direct pod access

For external access, add entries to your router's DNS or `/etc/hosts`:
```
192.168.10.200  webserver.homelab.local
192.168.10.10   k8s-api.homelab.local
```

## Calico Network Policy

Calico enforces Kubernetes NetworkPolicies at the kernel level using eBPF/iptables. By default, all pods can communicate. To add network segmentation, apply NetworkPolicy resources (see workloads.md).

## Hyper-V Virtual Switch

One external virtual switch is created, bound to the physical NIC of the Dell server. All VMs connect to this switch and get IPs in the 192.168.10.x range. The Hyper-V host's management IP remains on the separate physical LAN (192.168.1.x).
