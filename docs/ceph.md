# Ceph Storage Guide

This guide covers the Ceph cluster setup, Rook-Ceph integration, and storage management.

## Architecture

```
┌─────────────────── Ceph Cluster ────────────────────────────────────┐
│                                                                       │
│  ceph-node-01 (.31)   ceph-node-02 (.32)   ceph-node-03 (.33)       │
│  ┌─────────────┐      ┌─────────────┐      ┌─────────────┐          │
│  │  MON  MGR   │      │  MON        │      │  MON        │          │
│  │  OSD (200G) │      │  OSD (200G) │      │  OSD (200G) │          │
│  └─────────────┘      └─────────────┘      └─────────────┘          │
│                                                                       │
│  ceph-node-04 (.34)   ceph-node-05 (.35)                            │
│  ┌─────────────┐      ┌─────────────┐                               │
│  │  OSD (200G) │      │  OSD (200G) │                               │
│  └─────────────┘      └─────────────┘                               │
│                                                                       │
│  Total Raw Storage: 5 × 200 GB = 1 TB                               │
│  Usable Storage (3x replication): ~333 GB                           │
└───────────────────────────────────────────────────────────────────┘
                              │
                    Rook-Ceph Operator
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
        StorageClass     CephBlockPool   CephFilesystem
         ceph-rbd         (RBD PVCs)    (RWX PVCs)
              │
    PostgreSQL PVCs (5 × 50 GB = 250 GB)
```

## Ceph Components

| Component | Count | Role |
|-----------|-------|------|
| MON (Monitor) | 3 (nodes 01-03) | Cluster state management, quorum |
| MGR (Manager) | 2 (active+standby) | Metrics, dashboard, orchestration |
| OSD (Object Storage Daemon) | 5 | Actual data storage |
| MDS (Metadata Server) | 2 (via CephFilesystem) | CephFS metadata |

## Manual Ceph Setup (alternative to Ansible role)

### Bootstrap with cephadm

```bash
# On ceph-node-01 only
curl --silent --remote-name --location https://github.com/ceph/ceph/raw/reef/src/cephadm/cephadm
chmod +x cephadm
sudo mv cephadm /usr/local/bin/

# Bootstrap (creates first MON + MGR)
sudo cephadm bootstrap \
  --mon-ip 192.168.10.31 \
  --cluster-network 192.168.10.0/24 \
  --initial-dashboard-user admin \
  --initial-dashboard-password 'CHANGE_ME'

# Copy SSH key to other nodes
ssh-copy-id -f -i /etc/ceph/ceph.pub ubuntu@192.168.10.32
ssh-copy-id -f -i /etc/ceph/ceph.pub ubuntu@192.168.10.33
ssh-copy-id -f -i /etc/ceph/ceph.pub ubuntu@192.168.10.34
ssh-copy-id -f -i /etc/ceph/ceph.pub ubuntu@192.168.10.35

# Add remaining nodes
ceph orch host add ceph-node-02 192.168.10.32
ceph orch host add ceph-node-03 192.168.10.33
ceph orch host add ceph-node-04 192.168.10.34
ceph orch host add ceph-node-05 192.168.10.35
```

### Add OSDs

```bash
# List available devices on all nodes
ceph orch device ls

# Add OSDs from /dev/sdb on all nodes
ceph orch daemon add osd ceph-node-01:/dev/sdb
ceph orch daemon add osd ceph-node-02:/dev/sdb
ceph orch daemon add osd ceph-node-03:/dev/sdb
ceph orch daemon add osd ceph-node-04:/dev/sdb
ceph orch daemon add osd ceph-node-05:/dev/sdb

# Or, add all available/unpartitioned drives automatically
ceph orch apply osd --all-available-devices
```

### Create Kubernetes pool

```bash
# Create the pool
ceph osd pool create kubernetes 128 128
ceph osd pool application enable kubernetes rbd

# Create Kubernetes RBD client
ceph auth get-or-create client.kubernetes \
  mon 'profile rbd' \
  osd 'profile rbd pool=kubernetes' \
  mgr 'profile rbd pool=kubernetes'
```

## Monitoring Ceph Health

```bash
# Cluster health overview
ceph status
ceph health detail

# OSD tree
ceph osd tree

# Pool statistics
ceph df
ceph osd pool stats

# View active operations
ceph -s

# Watch in real-time
watch -n 2 ceph status
```

## Ceph Dashboard

The Ceph dashboard is accessible at: `https://192.168.10.31:8443`

Default credentials set during bootstrap. Access via:
```bash
# If you forget the password
ceph dashboard set-login-credentials admin NEW_PASSWORD
```

## Rook-Ceph in Kubernetes

Rook translates Kubernetes storage requests (PVCs) into Ceph operations. When a PostgreSQL pod requests a 50 GB PVC, Rook automatically:
1. Creates a Ceph RBD image in the `replicapool`
2. Maps it to the correct Kubernetes PV
3. Attaches it to the pod as a block device formatted as ext4

### Check Rook-Ceph status

```bash
# Check Rook operator
kubectl get pods -n rook-ceph

# Check CephCluster health
kubectl get cephcluster -n rook-ceph

# Check storage classes
kubectl get storageclass

# Check PVCs
kubectl get pvc -A
```

## Expanding Storage

To add more storage to the Ceph cluster, add another Hyper-V VM or expand an existing OSD disk:

```bash
# Check current capacity
ceph df

# Add a new OSD to an existing node (with a new disk)
ceph orch daemon add osd <hostname>:/dev/sdc

# Expand a pool's PG count as data grows
ceph osd pool set kubernetes pg_num 256
```
