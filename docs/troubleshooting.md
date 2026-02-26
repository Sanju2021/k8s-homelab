# Troubleshooting Guide

## Terraform / Hyper-V Issues

### WinRM Connection Errors

**Symptom**: `Error: dial tcp x.x.x.x:5985: connect: connection refused`

**Fix**:
```powershell
# On Windows host, run as Administrator:
Enable-PSRemoting -Force
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'

# Test the connection from WSL:
curl -s -o /dev/null -w "%{http_code}" http://HYPER-V-IP:5985/wsman
# Should return 200
```

### VM Won't Boot

**Symptom**: VM created but shows no network connectivity

**Fix**: Verify Secure Boot is disabled for Generation 2 Ubuntu VMs:
```powershell
Set-VMFirmware -VMName "k8s-master-01" -EnableSecureBoot Off
```

### Cloud-Init Not Running

If the VM boots but isn't configured (wrong hostname, no SSH key):
```bash
# Check cloud-init status
sudo cloud-init status --long
sudo cat /var/log/cloud-init.log | grep -E "ERROR|WARN"
sudo cloud-init clean --reboot
```

---

## Ansible Issues

### SSH Connection Refused

```bash
# Verify the VM is up and SSH is accessible
ssh -i ~/.ssh/k8s-homelab ubuntu@192.168.10.11

# If connection times out, check if VM got the correct IP:
# Open Hyper-V Manager → connect to VM console
# Run: ip addr show
```

### Ansible Facts Not Gathered

```bash
# Test connectivity and fact gathering
ansible all_nodes -i inventories/production/hosts.ini -m ping
ansible all_nodes -i inventories/production/hosts.ini -m setup
```

### Play Fails at kubeadm init

If the kubeadm init step fails, check the full error:
```bash
# On the master node:
sudo journalctl -xe -u kubelet
sudo kubeadm init --config /etc/kubernetes/kubeadm-init.yaml -v=5
```

Common causes:
- Swap not disabled: `sudo swapoff -a`
- Wrong container runtime socket: verify `/var/run/containerd/containerd.sock` exists
- Port conflicts: `sudo ss -tulpn | grep 6443`

---

## Kubernetes Issues

### Nodes Not Ready

```bash
kubectl describe node <node-name>
# Look for: "container runtime network not ready" or "NetworkPluginNotReady"

# Check CNI installation
kubectl get pods -n calico-system
kubectl get pods -n tigera-operator

# Restart kubelet if needed
sudo systemctl restart kubelet
```

### Pods Stuck in Pending

```bash
kubectl describe pod <pod-name> -n <namespace>

# Common causes:
# 1. No PVC bound — check storage
kubectl get pvc -n <namespace>
kubectl describe pvc <pvc-name> -n <namespace>

# 2. No schedulable nodes
kubectl get nodes
kubectl describe node <node> | grep Taints

# 3. Resource constraints
kubectl describe pod <pod-name> | grep -A 5 "Insufficient"
```

### etcd Issues

```bash
# Check etcd cluster health
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/peer.crt \
  --key=/etc/kubernetes/pki/etcd/peer.key \
  endpoint health --cluster

# If one etcd member is unhealthy, remove and re-add:
etcdctl member list
etcdctl member remove <member-id>

# Rejoin by running kubeadm on the failed master
```

### HAProxy Stats Show Masters as Down

```bash
# Check HAProxy status page: http://192.168.10.10:8404/stats

# Verify API servers are running on masters
curl -k https://192.168.10.11:6443/healthz
curl -k https://192.168.10.12:6443/healthz
curl -k https://192.168.10.13:6443/healthz

# If a master is down, SSH to it and restart kube-apiserver pod
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get pods -n kube-system
```

---

## Ceph Issues

### Ceph Cluster Shows HEALTH_WARN

```bash
# Get detailed health status
ceph health detail
ceph status

# Common warnings and fixes:
# - "too few PGs per OSD" → increase PG count:
ceph osd pool set kubernetes pg_num 256

# - "clock skew detected" → fix NTP on affected node
sudo chronyc tracking
sudo systemctl restart chrony

# - "1 nearfull osd" → Ceph OSD is filling up, add storage
ceph df
```

### PVC Stuck in Pending (Ceph StorageClass)

```bash
# Check Rook-Ceph provisioner
kubectl get pods -n rook-ceph | grep provisioner

# Check Rook-Ceph operator logs
kubectl logs -n rook-ceph -l app=rook-ceph-operator --tail=50

# Check CephCluster status
kubectl describe cephcluster -n rook-ceph

# Verify the Ceph pool exists
ceph osd pool ls
```

### OSD Not Appearing

```bash
# On the Ceph node, check if the disk is usable
lsblk
ceph-volume lvm list

# The disk must have NO partitions and NO filesystem
# Wipe it if needed (WARNING: destructive!)
sudo wipefs -a /dev/sdb
sudo dd if=/dev/zero of=/dev/sdb bs=1M count=100
```

---

## PostgreSQL Issues

### Pod in CrashLoopBackOff

```bash
kubectl logs postgresql-0 -n databases
kubectl logs postgresql-0 -n databases --previous

# Common cause: permission issues on PVC mount
# The initContainer should fix this, but if not:
kubectl exec -it postgresql-0 -n databases -- bash
ls -la /var/lib/postgresql/data/
```

### Cannot Connect to PostgreSQL

```bash
# Port-forward to test locally
kubectl port-forward svc/postgresql 5432:5432 -n databases &
psql -h 127.0.0.1 -U postgres -d homelab

# Check service endpoints
kubectl get endpoints postgresql -n databases
```

---

## General Debug Commands

```bash
# Cluster-wide resource usage
kubectl top nodes
kubectl top pods -A --sort-by=memory

# All non-running pods
kubectl get pods -A | grep -v Running | grep -v Completed

# Recent cluster events
kubectl get events -A --sort-by=lastTimestamp | tail -30

# Full cluster dump (for sharing/debugging)
kubectl cluster-info dump > /tmp/cluster-dump.txt
```
