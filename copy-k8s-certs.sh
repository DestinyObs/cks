#!/bin/bash

# Set permissions to allow copying as non-root
sudo chmod 644 /etc/kubernetes/admin.conf \
  /etc/kubernetes/pki/ca.key \
  /etc/kubernetes/pki/etcd/ca.key \
  /etc/kubernetes/pki/front-proxy-ca.key \
  /etc/kubernetes/pki/sa.key \
  /etc/kubernetes/pki/sa.pub

USER=k8s-master-2 # Change this to your username if needed
CONTROL_PLANE_IPS="192.168.32.8" # Update with your master IPs

for host in ${CONTROL_PLANE_IPS}; do
    ssh "${USER}"@$host "mkdir -p /home/${USER}/certs"
    scp /etc/kubernetes/pki/ca.crt "${USER}"@$host:/home/"${USER}"/certs/
    scp /etc/kubernetes/pki/ca.key "${USER}"@$host:/home/"${USER}"/certs/
    scp /etc/kubernetes/pki/sa.key "${USER}"@$host:/home/"${USER}"/certs/
    scp /etc/kubernetes/pki/sa.pub "${USER}"@$host:/home/"${USER}"/certs/
    scp /etc/kubernetes/pki/front-proxy-ca.crt "${USER}"@$host:/home/"${USER}"/certs/
    scp /etc/kubernetes/pki/front-proxy-ca.key "${USER}"@$host:/home/"${USER}"/certs/
    scp /etc/kubernetes/pki/etcd/ca.crt "${USER}"@$host:/home/"${USER}"/certs/etcd-ca.crt
    scp /etc/kubernetes/pki/etcd/ca.key "${USER}"@$host:/home/"${USER}"/certs/etcd-ca.key
    scp /etc/kubernetes/admin.conf "${USER}"@$host:/home/"${USER}"/certs/
done

# Revert permissions for security
sudo chmod 600 /etc/kubernetes/admin.conf \
  /etc/kubernetes/pki/ca.key \
  /etc/kubernetes/pki/etcd/ca.key \
  /etc/kubernetes/pki/front-proxy-ca.key \
  /etc/kubernetes/pki/sa.key \
  /etc/kubernetes/pki/sa.pub
