#!/bin/bash
set -euo pipefail

# === User must fill these in (base64-encoded for git safety) ===
# To update, run: echo -n 'YOUR_KEY' | base64
AWS_ACCESS_KEY_ID_B64="QUtJQTVETEY1TVJKU0YyNEJERlA="
AWS_SECRET_ACCESS_KEY_B64="cDMrUW56Z0E3L1d0TXJhdWNtblNRZEVvSjdwSkZlWkR4K0pjdTRLQQ=="
AWS_REGION_B64="dXMtZWFzdC0x"
BUCKET_NAME="k8s-pki-$(hostname | tr '[:upper:]' '[:lower:]')-$(date +%s)"

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
aws s3 cp /tmp/k8s-pki.tar.gz s3://$BUCKET_NAME/k8s-pki.tar.gz --acl bucket-owner-full-control

echo "Upload complete!"
echo "S3 bucket: $BUCKET_NAME"
echo "Object: k8s-pki.tar.gz"
