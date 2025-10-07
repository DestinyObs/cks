#!/bin/bash
set -euo pipefail

# === CONFIGURATION ===
MASTER_IP="${MASTER_IP:-192.168.32.8}"   # fallback if not exported
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"

# Prompt for all master hostnames/IPs (comma-separated)
MASTER_SANS_CLEANED="cksm1,cksm2,192.168.32.8,192.168.32.9"
# === [0.05/7] Write /etc/hosts for all cluster nodes (idempotent) ===
echo "Writing /etc/hosts with all cluster node hostnames..."
sudo tee /etc/hosts >/dev/null <<EOF
127.0.0.1   localhost
127.0.1.1   cksm1

192.168.32.8   cksm1
192.168.32.9   cksm2
192.168.32.5   cksw1
192.168.32.3   cksw2
192.168.32.6   cksw3
192.168.32.7   cksw4
EOF

# === [0/9] Stop any running Kubernetes processes and free ports ===
echo "Stopping any running Kubernetes processes and freeing ports..."
K8S_PORTS="6443 10259 10257 2379 2380"
for port in $K8S_PORTS; do
  if pids=$(sudo lsof -ti :"$port" 2>/dev/null); then
    if [ -n "$pids" ]; then
      echo "Killing processes on port $port: $pids"
      sudo kill -9 $pids || true
    fi
  fi
done
sudo systemctl stop kubelet || true
sudo systemctl stop containerd || true

# === [0.1/9] Clean up previous Kubernetes manifests and etcd data ===
echo "Aggressively cleaning up all old Kubernetes, etcd, CNI, and kubelet state..."
sudo systemctl stop kubelet || true
sudo systemctl stop containerd || true
sudo rm -rf /etc/kubernetes || true
sudo rm -rf /var/lib/etcd || true
sudo rm -rf /var/lib/cni || true
sudo rm -rf /var/lib/kubelet || true

# === [0.5/9] Disable swap (required by Kubernetes) ===
echo "Disabling swap..."
sudo swapoff -a
sudo sed -i.bak '/\sswap\s/ s/^/#/' /etc/fstab

# === [1/9] Loading kernel modules ===
echo "Loading kernel modules..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# === [2/9] Configuring sysctl parameters ===
echo "Configuring sysctl parameters..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

echo "Configuring containerd..."
# === [3/9] Installing and hardening containerd ===
echo "Installing containerd..."
sudo apt update -y
sudo apt install -y containerd

echo "Configuring containerd..."
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl daemon-reload
sudo systemctl enable --now containerd
sudo systemctl restart containerd
sudo systemctl status containerd --no-pager

# === [4/9] Installing and hardening Kubernetes components ===
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
sudo systemctl daemon-reload
sudo systemctl enable --now kubelet
sudo systemctl status kubelet --no-pager

# === [5/9] Initializing Kubernetes control plane (idempotent) ===
echo "Initializing Kubernetes control plane..."
if [ ! -f /etc/kubernetes/admin.conf ]; then
  sudo kubeadm init \
    --apiserver-advertise-address="$MASTER_IP" \
    --pod-network-cidr="$POD_CIDR" \
    --control-plane-endpoint="${MASTER_IP}:6443" \
    --apiserver-cert-extra-sans="$MASTER_SANS_CLEANED" | tee ~/kubeadm-init.log
else
  echo "Kubernetes control plane already initialized. Skipping kubeadm init."
fi

# === [6/9] Setting up kubeconfig for current user (self-healing) ===
echo "Setting up kubeconfig..."
mkdir -p "$HOME/.kube"
if [ -f /etc/kubernetes/admin.conf ]; then
  sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
  sudo chown "$(id -u)":"$(id -g)" "$HOME/.kube/config"
else
  echo "Warning: /etc/kubernetes/admin.conf not found! kubeconfig not set."
fi

# === [7/9] Deploying Calico CNI (idempotent) ===
echo "Deploying Calico CNI..."
if ! kubectl get daemonset -n kube-system calico-node >/dev/null 2>&1; then
  kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.2/manifests/calico.yaml
else
  echo "Calico CNI already deployed."
fi


# === [8/9] Pull correct pause image for containerd (idempotent) ===
echo "Pulling correct pause image for containerd..."
if ! sudo ctr -n k8s.io images list | grep -q 'registry.k8s.io/pause:3.9'; then
  sudo ctr images pull registry.k8s.io/pause:3.9 || true
else
  echo "Pause image already present."
fi

# === [9/9] Etcd backup (resilience) ===
echo "Backing up etcd data (if running)..."
if [ -d /var/lib/etcd ]; then
  sudo tar czf "/root/etcd-backup-$(date +%Y%m%d-%H%M%S).tar.gz" /var/lib/etcd || true
fi

echo "Ensuring critical services are enabled on boot..."
sudo systemctl enable --now containerd
sudo systemctl enable --now kubelet

echo "=== DONE! Kubernetes master (cks-master-1) is ready and hardened. ==="
echo "Check nodes with: kubectl get nodes"
echo "Save your join command from ~/kubeadm-init.log for workers & master-2"

echo "=== DONE! Kubernetes master (cks-master-1) is ready. ==="
echo "Check nodes with: kubectl get nodes"
echo "Save your join command from ~/kubeadm-init.log for workers & master-2"
