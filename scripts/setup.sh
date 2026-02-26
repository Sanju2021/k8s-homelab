#!/usr/bin/env bash
##############################################################################
# setup.sh — Full end-to-end deployment script
# Run this from your management machine (WSL2 or Linux)
# Usage: ./scripts/setup.sh [--skip-terraform] [--skip-ansible] [--skip-k8s]
##############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

SKIP_TERRAFORM=false
SKIP_ANSIBLE=false
SKIP_K8S=false

for arg in "$@"; do
  case $arg in
    --skip-terraform) SKIP_TERRAFORM=true ;;
    --skip-ansible)   SKIP_ANSIBLE=true ;;
    --skip-k8s)       SKIP_K8S=true ;;
  esac
done

##############################################################################
# Phase 1: Check prerequisites
##############################################################################
log_info "Checking prerequisites..."

command -v terraform >/dev/null 2>&1 || log_error "terraform not found. Install: https://developer.hashicorp.com/terraform/install"
command -v ansible   >/dev/null 2>&1 || log_error "ansible not found. Install: pip install ansible"
command -v kubectl   >/dev/null 2>&1 || log_error "kubectl not found. Install: https://kubernetes.io/docs/tasks/tools/"
command -v helm      >/dev/null 2>&1 || log_warn "helm not found. Some steps may fail. Install: https://helm.sh/docs/intro/install/"

log_success "All prerequisites found."

##############################################################################
# Phase 2: Terraform — Provision VMs
##############################################################################
if [[ "$SKIP_TERRAFORM" == "false" ]]; then
  log_info "=== PHASE 1: Provisioning infrastructure with Terraform ==="
  
  cd "$REPO_ROOT/terraform/environments/production"
  
  if [[ ! -f terraform.tfvars ]]; then
    log_error "terraform.tfvars not found! Copy terraform.tfvars.example and fill in your values."
  fi
  
  terraform init -upgrade
  terraform plan -out=tfplan
  
  echo ""
  log_warn "Review the plan above. Press ENTER to apply or CTRL+C to abort."
  read -r
  
  terraform apply tfplan
  log_success "Infrastructure provisioned."
  
  terraform output
  cd "$REPO_ROOT"
else
  log_warn "Skipping Terraform (--skip-terraform)"
fi

##############################################################################
# Phase 3: Wait for VMs to be SSH-ready
##############################################################################
log_info "=== Waiting for all VMs to be SSH-accessible ==="

MASTER_IPS=(192.168.10.11 192.168.10.12 192.168.10.13)
WORKER_IPS=(192.168.10.21 192.168.10.22 192.168.10.23 192.168.10.24 192.168.10.25 192.168.10.26 192.168.10.27)
CEPH_IPS=(192.168.10.31 192.168.10.32 192.168.10.33 192.168.10.34 192.168.10.35)
ALL_IPS=("${MASTER_IPS[@]}" "${WORKER_IPS[@]}" "${CEPH_IPS[@]}" 192.168.10.10)

for ip in "${ALL_IPS[@]}"; do
  log_info "Waiting for SSH on $ip..."
  until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
    -i ~/.ssh/k8s-homelab ubuntu@"$ip" 'echo ok' >/dev/null 2>&1; do
    sleep 10
    echo -n "."
  done
  log_success "$ip is SSH-ready"
done

##############################################################################
# Phase 4: Ansible — Configure all nodes
##############################################################################
if [[ "$SKIP_ANSIBLE" == "false" ]]; then
  log_info "=== PHASE 2: Configuring nodes with Ansible ==="
  
  cd "$REPO_ROOT/ansible"
  
  # Test connectivity
  ansible all_nodes \
    -i inventories/production/hosts.ini \
    -m ping \
    --private-key ~/.ssh/k8s-homelab \
    -u ubuntu
  
  # Run full playbook
  ansible-playbook \
    -i inventories/production/hosts.ini \
    playbooks/site.yml \
    --private-key ~/.ssh/k8s-homelab \
    -u ubuntu \
    --become \
    -v
  
  log_success "Ansible configuration complete."
  cd "$REPO_ROOT"
else
  log_warn "Skipping Ansible (--skip-ansible)"
fi

##############################################################################
# Phase 5: Deploy Kubernetes workloads
##############################################################################
if [[ "$SKIP_K8S" == "false" ]]; then
  log_info "=== PHASE 3: Deploying Kubernetes workloads ==="
  
  # Fetch kubeconfig from first master
  log_info "Fetching kubeconfig from master-01..."
  mkdir -p ~/.kube
  scp -i ~/.ssh/k8s-homelab ubuntu@192.168.10.11:/home/ubuntu/.kube/config ~/.kube/config
  
  # Wait for all nodes to be Ready
  log_info "Waiting for all nodes to be Ready..."
  kubectl wait --for=condition=Ready nodes --all --timeout=300s
  
  # Apply all manifests
  log_info "Applying Kubernetes manifests..."
  kubectl apply -f "$REPO_ROOT/kubernetes/namespaces/"
  
  # Wait a moment for namespaces
  sleep 5
  
  kubectl apply -f "$REPO_ROOT/kubernetes/storage/"
  
  # Wait for StorageClass
  sleep 30
  
  kubectl apply -f "$REPO_ROOT/kubernetes/workloads/webservers/"
  kubectl apply -f "$REPO_ROOT/kubernetes/workloads/postgresql/"
  
  log_info "Waiting for webservers to be ready..."
  kubectl rollout status deployment/nginx-webserver -n webservers --timeout=300s
  
  log_info "Waiting for PostgreSQL to be ready..."
  kubectl rollout status statefulset/postgresql -n databases --timeout=600s
  
  log_success "All workloads deployed!"
  
  echo ""
  echo "=== Cluster Summary ==="
  kubectl get nodes -o wide
  echo ""
  kubectl get pods -A | grep -E "webservers|databases"
  echo ""
  kubectl get svc -A | grep -E "webservers|databases|ingress"
else
  log_warn "Skipping K8s workload deployment (--skip-k8s)"
fi

log_success "🎉 Deployment complete!"
echo ""
echo "Access points:"
echo "  Kubernetes API:     https://192.168.10.10:6443"
echo "  HAProxy Stats:      http://192.168.10.10:8404/stats"
echo "  Ceph Dashboard:     https://192.168.10.31:8443"
echo "  NGINX Ingress:      http://webserver.homelab.local (set DNS or /etc/hosts)"
