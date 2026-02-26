# Workloads Deployment Guide

## NGINX Web Servers

### Architecture

Five NGINX pods run across the 7 worker nodes. `topologySpreadConstraints` ensures no more than 2 pods land on the same node, providing fault tolerance.

```
Worker Node Distribution (example):
  worker-01: nginx-webserver-xxx1
  worker-02: nginx-webserver-xxx2
  worker-03: nginx-webserver-xxx3
  worker-04: nginx-webserver-xxx4
  worker-05: nginx-webserver-xxx5
  worker-06: (spare capacity / scaled pods)
  worker-07: (spare capacity / scaled pods)
```

### Deployment

```bash
# Deploy
kubectl apply -f kubernetes/workloads/webservers/nginx-deployment.yaml

# Monitor rollout
kubectl rollout status deployment/nginx-webserver -n webservers

# Check pods
kubectl get pods -n webservers -o wide

# Access via ingress (set /etc/hosts first)
echo "192.168.10.200 webserver.homelab.local" | sudo tee -a /etc/hosts
curl http://webserver.homelab.local
```

### Scaling

```bash
# Manual scale
kubectl scale deployment nginx-webserver -n webservers --replicas=8

# Check HPA status
kubectl get hpa -n webservers
kubectl describe hpa nginx-webserver-hpa -n webservers
```

### Updating the Web Content

Edit the ConfigMap to change the HTML content:

```bash
kubectl edit configmap nginx-config -n webservers
# Or apply changes:
kubectl apply -f kubernetes/workloads/webservers/nginx-deployment.yaml

# Rolling restart to pick up ConfigMap changes
kubectl rollout restart deployment/nginx-webserver -n webservers
```

---

## PostgreSQL Servers

### Architecture

Five PostgreSQL instances run as a StatefulSet. Each pod gets a stable identity (postgresql-0 through postgresql-4) and its own dedicated 50 GB Ceph RBD volume.

```
Persistent Volumes (Ceph RBD):
  postgresql-0 ──► PVC: postgresql-data-postgresql-0 (50 GB)
  postgresql-1 ──► PVC: postgresql-data-postgresql-1 (50 GB)
  postgresql-2 ──► PVC: postgresql-data-postgresql-2 (50 GB)
  postgresql-3 ──► PVC: postgresql-data-postgresql-3 (50 GB)
  postgresql-4 ──► PVC: postgresql-data-postgresql-4 (50 GB)
```

These are independent PostgreSQL instances (not a replication cluster). For production replication, consider using the Zalando PostgreSQL operator or Patroni.

### Deployment

```bash
# IMPORTANT: Change the default password first!
# Edit kubernetes/workloads/postgresql/postgresql-statefulset.yaml
# Update POSTGRES_PASSWORD under the Secret section

# Or use kubectl:
kubectl create secret generic postgresql-secret \
  --from-literal=POSTGRES_PASSWORD='YOUR_STRONG_PASSWORD' \
  --namespace databases \
  --dry-run=client -o yaml | kubectl apply -f -

# Deploy
kubectl apply -f kubernetes/workloads/postgresql/postgresql-statefulset.yaml

# Monitor StatefulSet rollout (sequential — one pod at a time)
kubectl rollout status statefulset/postgresql -n databases

# Check pods and PVCs
kubectl get pods -n databases -o wide
kubectl get pvc -n databases
```

### Connecting to PostgreSQL

```bash
# Connect to a specific instance by pod ordinal:
kubectl exec -it postgresql-0 -n databases -- psql -U postgres

# Port-forward a specific instance to localhost:
kubectl port-forward postgresql-0 5433:5432 -n databases &
psql -h 127.0.0.1 -p 5433 -U postgres

# Connect via Service (load-balanced across all 5):
kubectl port-forward svc/postgresql 5432:5432 -n databases &
psql -h 127.0.0.1 -p 5432 -U postgres

# DNS name within the cluster (from other pods):
# postgresql.databases.svc.cluster.local:5432

# Direct pod DNS (StatefulSet headless service):
# postgresql-0.postgresql-headless.databases.svc.cluster.local:5432
```

### Creating Databases and Users

```bash
kubectl exec -it postgresql-0 -n databases -- psql -U postgres << 'EOF'
-- Create a user
CREATE USER appuser WITH ENCRYPTED PASSWORD 'CHANGE_ME';

-- Create a database
CREATE DATABASE myapp OWNER appuser;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE myapp TO appuser;

\q
EOF
```

### Backup and Restore

```bash
# Backup a PostgreSQL database
kubectl exec postgresql-0 -n databases -- \
  pg_dump -U postgres homelab | gzip > homelab-backup-$(date +%Y%m%d).sql.gz

# Restore from backup
gunzip < homelab-backup-20240101.sql.gz | \
  kubectl exec -i postgresql-0 -n databases -- psql -U postgres homelab
```

### Monitoring PostgreSQL

```bash
# Check replication status (if configured)
kubectl exec -it postgresql-0 -n databases -- \
  psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Check active connections
kubectl exec -it postgresql-0 -n databases -- \
  psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;"

# Check database sizes
kubectl exec -it postgresql-0 -n databases -- \
  psql -U postgres -c "\l+"
```

---

## NetworkPolicy (optional hardening)

Apply this to restrict traffic between namespaces:

```yaml
# Allow webservers to talk to databases on port 5432
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-webservers-to-postgres
  namespace: databases
spec:
  podSelector:
    matchLabels:
      app: postgresql
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: webservers
      ports:
        - protocol: TCP
          port: 5432
```
