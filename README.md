# Cybercloud Kubernetes Service (CKS) — Engineering Project README

## 1. Project Overview

Cybercloud Kubernetes Service (CKS) is an enterprise-grade Kubernetes-as-a-Service (KaaS) platform, running on a Proxmox VE-based private cloud. The goal is to deliver secure, multi-tenant Kubernetes clusters with high availability, robust networking, and a foundation for advanced enterprise features.

## 2. Current State

### 2.1 Infrastructure
- **Proxmox VE Cluster:** 2 nodes, HA enabled
- **VM Topology:**
  - Node 1: pfSense firewall, K8s master, storage
  - Node 2: K8s master, workers, storage, monitoring

### 2.2 Kubernetes Cluster
- **Control Plane:** 2 masters (cks-master-1, cks-master-2)
- **Workers:** 4 nodes (cks-worker-1 to cks-worker-4)
- **Networking:** Calico CNI
- **Ingress:** NGINX (basic)
- **Service Mesh:** Istio (planned)
- **Storage:** Longhorn (planned)

### 2.3 Security & Identity
- Hostname/IP standardization
- RBAC enabled
- Provider API (in design) for tenant isolation

### 2.4 Achievements
- Multi-node, dual-master cluster on Proxmox
- HA control plane
- Secure networking and ingress

## 3. Next Steps (Roadmap)

### 3.1 Immediate
- HA API endpoint (VIP via pfSense HAProxy)
- Longhorn storage deployment
- Monitoring/alerting (Prometheus, Grafana)
- Centralized logging (Loki/EFK)
- TLS automation (cert-manager)
- Etcd backup/restore automation

### 3.2 Short-Term
- RBAC/policy hardening (Kyverno/OPA)
- Hardened ingress, deploy Istio
- Secrets management (Vault/Sealed Secrets)
- Private registry (Harbor + Trivy)
- GitOps CI/CD (ArgoCD)

### 3.3 Long-Term
- Multi-cluster federation
- Proxmox-integrated autoscaling
- Advanced billing, compliance, zero-trust networking

## 4. How to Use This Repo
- See `setup-master-1.sh`, `setup-master-join.sh`, and `setup-worker.sh` for cluster bootstrapping.
- Use `upload-cert-secret.sh` for S3-based PKI/cert distribution.
- All scripts are idempotent and safe for repeated use.
- AWS credentials are base64-encoded for git safety; decode at runtime.

## 5. Lessons Learned
- S3-based cert transfer is more robust than scp for multi-master join.
- Node naming and aggressive cleanup are critical for repeatable automation.
- Proxmox + pfSense enables true enterprise-grade network separation and HA.

## 6. Contacts & Contribution
- For issues, open a ticket or contact the platform engineering team.
- Contributions welcome: fork, branch, and PR.

---
This README is engineering-focused. For a whitepaper or executive summary, see `/docs/` (to be added).
