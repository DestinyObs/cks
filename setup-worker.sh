#!/bin/bash

set -euo pipefail

# === Set hostname for this worker ===

# Prompt for hostname and IP
if [ -z "${NODE_NAME:-}" ]; then
  read -rp "Enter desired node hostname (e.g. cks-worker-1): " NODE_NAME
fi
if [ -z "${NODE_IP:-}" ]; then
  read -rp "Enter this node's IP address (e.g. 192.168.32.9): " NODE_IP
fi
echo "Setting system hostname to $NODE_NAME..."
sudo hostnamectl set-hostname "$NODE_NAME"

# Ensure /etc/hosts has correct entry for hostname and IP
if ! grep -q "$NODE_NAME" /etc/hosts; then
  echo "$NODE_IP $NODE_NAME" | sudo tee -a /etc/hosts
fi


# # === PKI S3 Download Config ===
# AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-YOUR_AWS_ACCESS_KEY_ID}"
# AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-YOUR_AWS_SECRET_ACCESS_KEY}"
# AWS_REGION="${AWS_REGION:-us-east-1}"
# BUCKET_NAME="${BUCKET_NAME:-}" # e.g. k8s-pki-<cluster-name>
# OBJECT_NAME="${OBJECT_NAME:-k8s-pki.tar.gz}"

# # Prompt for bucket if not set
# if [ -z "$BUCKET_NAME" ]; then
#   read -p "Enter S3 bucket name for PKI assets: " BUCKET_NAME
# fi

# # === Install AWS CLI if not present ===
# if ! command -v aws >/dev/null 2>&1; then
#   echo "Installing AWS CLI..."
#   sudo apt-get update && sudo apt-get install -y awscli
# fi

# export AWS_ACCESS_KEY_ID
# export AWS_SECRET_ACCESS_KEY
# export AWS_DEFAULT_REGION="$AWS_REGION"

# # === Download and extract PKI assets ===
# echo "Downloading PKI archive from S3..."
# aws s3 cp "s3://$BUCKET_NAME/$OBJECT_NAME" /tmp/k8s-pki.tar.gz
# echo "Extracting PKI to /etc/kubernetes..."
# sudo rm -rf /etc/kubernetes/pki
# sudo mkdir -p /etc/kubernetes/pki
# sudo tar xzf /tmp/k8s-pki.tar.gz -C /etc/kubernetes
# sudo chown -R root:root /etc/kubernetes/pki
# sudo chmod -R 600 /etc/kubernetes/pki/*.key || true
# sudo chmod -R 700 /etc/kubernetes/pki/etcd || true


# Remove conflicting pause:3.8 image if present (prevents version warning)
if sudo ctr -n k8s.io images list | grep -q 'pause:3.8'; then
  echo "Removing old pause:3.8 image to avoid version conflict..."
  sudo ctr -n k8s.io images rm registry.k8s.io/pause:3.8 || true
fi
echo "Checked for and removed pause:3.8 image if present."

MASTER_IP="192.168.32.8"
K8S_PORTS="6443 10259 10257 2379 2380"

# === [0/4] Stop any running Kubernetes processes and free ports ===
echo "Stopping any running Kubernetes processes and freeing ports..."
for port in $K8S_PORTS; do
  pids=$(sudo lsof -ti :$port || true)
  if [ -n "$pids" ]; then
    echo "Killing processes on port $port: $pids"
    sudo kill -9 $pids || true
  fi
done
sudo systemctl stop kubelet || true
sudo systemctl stop containerd || true

# === [0.1/4] Clean up previous Kubernetes manifests and etcd data ===
echo "Cleaning up old Kubernetes manifests and etcd data..."
sudo rm -f /etc/kubernetes/manifests/*.yaml || true
sudo rm -rf /var/lib/etcd || true
sudo mkdir -p /var/lib/etcd

# === [0.5/4] Disable swap (required by Kubernetes) ===
echo "Disabling swap..."
sudo swapoff -a
sudo sed -i.bak '/\sswap\s/ s/^/#/' /etc/fstab

# === [1/4] Kernel modules ===
echo "=== [1/4] Kernel modules ==="
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# === [2/4] Sysctl params ===
echo "=== [2/4] Sysctl params ==="
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

# === [3/4] Containerd + K8s ===
echo "=== [3/4] Containerd + K8s ==="
# Set kubelet to use the system hostname (explicitly)
sudo sed -i '/^KUBELET_EXTRA_ARGS=/d' /etc/default/kubelet || true
echo "KUBELET_EXTRA_ARGS=--hostname-override=$(hostname)" | sudo tee -a /etc/default/kubelet
sudo apt update -y
sudo apt install -y containerd apt-transport-https ca-certificates curl gpg
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update -y
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# === [4/4] Joining as worker ===
echo "=== [4/4] Joining as worker ==="
JOIN_CMD="kubeadm join 192.168.32.8:6443 --token rjqu9e.czrli4njw33exw8x --discovery-token-ca-cert-hash sha256:b5c78b2e78f3e0d405dda0eae625ee0495d8d295fe0b0aff3d58a3142f835810"
echo "Running: $JOIN_CMD"
sudo $JOIN_CMD
