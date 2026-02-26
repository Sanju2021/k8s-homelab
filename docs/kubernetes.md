# Kubernetes Setup Guide

This guide covers the Kubernetes cluster architecture, bootstrapping, and post-install configuration.

## Architecture

### High Availability Control Plane

The cluster uses a stacked etcd topology with three control-plane nodes:

```
                   ┌─────────────────────────────────────┐
External Clients → │  HAProxy VIP: 192.168.10.10:6443    │
                   └──────────┬──────────────────────────┘
                              │ Round-robin TCP
           ┌──────────────────┼──────────────────┐
           ▼                  ▼                   ▼
  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
  │  master-01  │   │  master-02  │   │  master-03  │
  │  API Server │   │  API Server │   │  API Server │
  │  etcd       │   │  etcd       │   │  etcd       │
  │  scheduler  │   │  scheduler  │   │  scheduler  │
  │  ctrl-mgr   │   │  ctrl-mgr   │   │  ctrl-mgr   │
  └──────┬──────┘   └──────┬──────┘   └──────┬──────┘
         └──────────────── etcd cluster ──────┘
```

With stacked etcd, each master node runs a local etcd member. The three etcd members form a quorum. If one master goes down, the cluster continues functioning with two remaining members.

### Worker Nodes

Seven worker nodes schedule all workload pods. The `topologySpreadConstraints` in each Deployment/StatefulSet ensures pods are distributed evenly.

### Network — Calico CNI

Calico uses VXLANCrossSubnet mode, which uses VXLAN tunneling between nodes on different subnets and native routing for same-subnet communication. This performs well in a flat Hyper-V network.

## Manual Bootstrap Steps (if not using Ansible)

### 1. Initialize first master

```bash
# On master-01
sudo kubeadm init \
  --config /etc/kubernetes/kubeadm-init.yaml \
  --upload-certs \
  | tee /root/kubeadm-init.log

# Set up kubectl access
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install Calico
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml
kubectl apply -f /tmp/calico-custom-resources.yaml

# Wait for all system pods to be running
kubectl get pods -n kube-system --watch
```

### 2. Join additional masters

```bash
# Get join command from the init output, or run:
kubeadm token create --print-join-command

# Get certificate key:
kubeadm init phase upload-certs --upload-certs

# On master-02 and master-03:
sudo <join-command> --control-plane --certificate-key <cert-key>
```

### 3. Join worker nodes

```bash
# On each worker node:
sudo <join-command>  # (without --control-plane)
```

### 4. Label workers

```bash
# On any master:
for node in k8s-worker-{01..07}; do
  kubectl label node $node node-role.kubernetes.io/worker=worker
done
```

## Install MetalLB

```bash
# Install MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.3/config/manifests/metallb-native.yaml

# Wait for MetalLB pods
kubectl rollout status -n metallb-system deployment/controller

# Apply IP pool configuration
kubectl apply -f kubernetes/storage/metallb-config.yaml
```

## Install NGINX Ingress Controller

```bash
# Install via Helm
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer

# Verify external IP is assigned by MetalLB
kubectl get svc -n ingress-nginx
```

## Install Rook-Ceph Operator

```bash
# Add Rook Helm repo
helm repo add rook-release https://charts.rook.io/release
helm repo update

# Install operator
helm install rook-ceph rook-release/rook-ceph \
  --namespace rook-ceph \
  --create-namespace \
  --version 1.13.0

# Apply StorageClass and pools
kubectl apply -f kubernetes/storage/storageclass.yaml

# Wait for StorageClass to be ready
kubectl get sc
```

## Useful Commands

```bash
# Cluster health overview
kubectl get nodes -o wide
kubectl get pods -A

# Check control plane component status
kubectl get componentstatuses
kubectl get pods -n kube-system

# Check etcd cluster health (from any master)
etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/peer.crt \
  --key=/etc/kubernetes/pki/etcd/peer.key \
  endpoint health --cluster

# View resource usage
kubectl top nodes
kubectl top pods -A

# Watch rolling update
kubectl rollout status deployment/nginx-webserver -n webservers

# Connect to a PostgreSQL instance
kubectl exec -it postgresql-0 -n databases -- psql -U postgres
```

## Certificate Management

Kubernetes certificates expire after 1 year by default. Renew them:

```bash
# Check certificate expiry
kubeadm certs check-expiration

# Renew all certificates
sudo kubeadm certs renew all
sudo systemctl restart kubelet
```
