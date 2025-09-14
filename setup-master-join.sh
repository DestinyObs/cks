#!/bin/bash

set -euo pipefail

# === PKI S3 Download Config (base64-encoded for git safety) ===
# To update, run: echo -n 'YOUR_KEY' | base64
AWS_ACCESS_KEY_ID_B64="QUtJQTVETEY1TVJKU0YyNEJERlA="
AWS_SECRET_ACCESS_KEY_B64="cDMrUW56Z0E3L1d0TXJhdWNtblNRZEVvSjdwSkZlWkR4K0pjdTRLQQ=="
AWS_REGION_B64="dXMtZWFzdC0x"
BUCKET_NAME="k8s-pki-cks-master-1-1757812176"
OBJECT_NAME="k8s-pki.tar.gz"

# Decode credentials at runtime
AWS_ACCESS_KEY_ID=$(echo "$AWS_ACCESS_KEY_ID_B64" | base64 -d)
AWS_SECRET_ACCESS_KEY=$(echo "$AWS_SECRET_ACCESS_KEY_B64" | base64 -d)
AWS_REGION=$(echo "$AWS_REGION_B64" | base64 -d)

# === Install AWS CLI if not present ===
if ! command -v aws >/dev/null 2>&1; then
  echo "Installing AWS CLI..."
  sudo apt-get update && sudo apt-get install -y awscli
fi

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION="$AWS_REGION"

# === Download and extract PKI assets ===
echo "Downloading PKI archive from S3..."
aws s3 cp "s3://$BUCKET_NAME/$OBJECT_NAME" /tmp/k8s-pki.tar.gz
echo "Extracting PKI to /etc/kubernetes..."
sudo rm -rf /etc/kubernetes/pki
sudo mkdir -p /etc/kubernetes/pki
sudo tar xzf /tmp/k8s-pki.tar.gz -C /etc/kubernetes
sudo chown -R root:root /etc/kubernetes/pki
sudo chmod -R 600 /etc/kubernetes/pki/*.key || true
sudo chmod -R 700 /etc/kubernetes/pki/etcd || true

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

# === [4/4] Joining as control plane ===
echo "=== [4/4] Joining as control plane ==="
JOIN_CMD="kubeadm join 192.168.32.8:6443 --token xb1qny.kpsz0d3jo96cja1o --discovery-token-ca-cert-hash sha256:6802d95fa383320c0df78721880faa69a4af8bc8bedd28ff0b87aa9e86ba5dff --control-plane"
echo "Running: $JOIN_CMD"
sudo $JOIN_CMD
