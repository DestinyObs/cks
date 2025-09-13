#!/bin/bash
set -euo pipefail

MASTER_IP="192.168.32.8"
POD_CIDR="10.244.0.0/16"

# === [0/7] Stop any running Kubernetes processes and free ports ===
echo "Stopping any running Kubernetes processes and freeing ports..."
K8S_PORTS="6443 10259 10257 2379 2380"
for port in $K8S_PORTS; do
  pids=$(sudo lsof -ti :$port || true)
  if [ -n "$pids" ]; then
    echo "Killing processes on port $port: $pids"
    sudo kill -9 $pids || true
  fi
done
# Also try to stop kubelet and containerd if running
sudo systemctl stop kubelet || true
sudo systemctl stop containerd || true

# === [0.5/7] Disable swap (required by Kubernetes) ===
echo "Disabling swap..."
sudo swapoff -a
sudo sed -i.bak '/\sswap\s/ s/^/#/' /etc/fstab

# === [1/7] Loading kernel modules ===
echo "Loading kernel modules..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# === [2/7] Configuring sysctl parameters ===
echo "Configuring sysctl parameters..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

# === [3/7] Installing containerd ===
echo "Installing containerd..."
sudo apt update -y
sudo apt install -y containerd

echo "Configuring containerd..."
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# === [4/7] Installing Kubernetes components (kubeadm, kubelet, kubectl) ===
echo "Installing Kubernetes components..."
sudo apt update -y
sudo apt install -y apt-transport-https ca-certificates curl gpg
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update -y
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# === [5/7] Initializing Kubernetes control plane ===
echo "Initializing Kubernetes control plane..."
sudo kubeadm init \
  --apiserver-advertise-address=${MASTER_IP} \
  --pod-network-cidr=${POD_CIDR} \
  --control-plane-endpoint=${MASTER_IP}:6443 | tee ~/kubeadm-init.log

# === [6/7] Setting up kubeconfig for current user ===
echo "Setting up kubeconfig..."
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# === [7/7] Deploying Calico CNI ===
echo "Deploying Calico CNI..."
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.2/manifests/calico.yaml

# === [8/7] Pull correct pause image for containerd ===
echo "Pulling correct pause image for containerd..."
sudo ctr images pull registry.k8s.io/pause:3.9 || true

echo "=== DONE! Kubernetes master (cks-master-1) is ready. ==="
echo "Check nodes with: kubectl get nodes"
echo "Save your join command from ~/kubeadm-init.log for workers & master-2"
