#!/bin/bash
set -euo pipefail

# === User must fill these in (base64-encoded for git safety) ===

# === User must fill these in (raw values) ===
AWS_ACCESS_KEY_ID=""
AWS_SECRET_ACCESS_KEY=""
AWS_REGION="us-east-1"
BUCKET_NAME="mycks-k8s-pki"

# === Install AWS CLI if not present ===
if ! command -v aws >/dev/null 2>&1; then
  echo "Installing AWS CLI..."
  sudo apt-get update && sudo apt-get install -y awscli
fi

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION="$AWS_REGION"

# === Create S3 bucket if it doesn't exist ===
echo "Creating S3 bucket: $BUCKET_NAME (if not exists)"
if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  if [ "$AWS_REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION"
  else
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" --create-bucket-configuration LocationConstraint="$AWS_REGION"
  fi
fi


# === Regenerate apiserver cert with all master hostnames/IPs ===
echo "Regenerating apiserver certificate with all master hostnames and IPs..."
sudo kubeadm init phase certs apiserver \
  --apiserver-advertise-address=192.168.32.8 \
  --apiserver-cert-extra-sans=192.168.32.8,192.168.32.9,cks-master-1,cks-master-2,kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster.local

# === Archive PKI directories ===
echo "Archiving /etc/kubernetes/pki and /etc/kubernetes/pki/etcd..."
sudo tar czf /tmp/k8s-pki.tar.gz -C /etc/kubernetes pki

# === Upload to S3 (overwrite always) ===
echo "Uploading archive to S3 (overwrite if exists)..."
echo "Uploading individual certs and admin.conf to S3..."
echo "Uploading individual certs and admin.conf to S3 (with sudo -E to preserve env)..."
sudo -E aws s3 cp /etc/kubernetes/admin.conf s3://$BUCKET_NAME/admin.conf --acl bucket-owner-full-control
sudo -E aws s3 cp /etc/kubernetes/pki/ca.crt s3://$BUCKET_NAME/ca.crt --acl bucket-owner-full-control
sudo -E aws s3 cp /etc/kubernetes/pki/ca.key s3://$BUCKET_NAME/ca.key --acl bucket-owner-full-control
sudo -E aws s3 cp /etc/kubernetes/pki/sa.key s3://$BUCKET_NAME/sa.key --acl bucket-owner-full-control
sudo -E aws s3 cp /etc/kubernetes/pki/sa.pub s3://$BUCKET_NAME/sa.pub --acl bucket-owner-full-control
sudo -E aws s3 cp /etc/kubernetes/pki/front-proxy-ca.crt s3://$BUCKET_NAME/front-proxy-ca.crt --acl bucket-owner-full-control
sudo -E aws s3 cp /etc/kubernetes/pki/front-proxy-ca.key s3://$BUCKET_NAME/front-proxy-ca.key --acl bucket-owner-full-control
sudo -E aws s3 cp /etc/kubernetes/pki/etcd/ca.crt s3://$BUCKET_NAME/etcd-ca.crt --acl bucket-owner-full-control
sudo -E aws s3 cp /etc/kubernetes/pki/etcd/ca.key s3://$BUCKET_NAME/etcd-ca.key --acl bucket-owner-full-control

echo "Upload complete!"
echo "S3 bucket: $BUCKET_NAME"
echo "Object: k8s-pki.tar.gz"
