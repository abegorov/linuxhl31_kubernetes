#!/bin/bash

export ETCDCTL_API=3
export ETCDCTL_CACERT="/etc/kubernetes/pki/etcd/ca.crt"
export ETCDCTL_CERT="/etc/kubernetes/pki/etcd/server.crt"
export ETCDCTL_KEY="/etc/kubernetes/pki/etcd/server.key"
export ETCDCTL_ENDPOINTS="https://127.0.0.1:2379"
export KUBECONFIG="/root/.kube/config"

BACKUP_DIR="{{ kubernetes_backup_dir }}/$(date -u +%Y%m%d_%H%M%SZ)"
mkdir -p "${BACKUP_DIR}"
etcdctl snapshot save "${BACKUP_DIR}/snapshot.db"

RESOURCES=$(kubectl api-resources --verbs=list --namespaced -o name)
NAMESPACES=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')

for ns in ${NAMESPACES}; do
  mkdir -p "${BACKUP_DIR}/${ns}"
  for res in ${RESOURCES}; do
    echo "Processing ${ns}/${res}"
    kubectl get "${res}" -n "${ns}" -o yaml --ignore-not-found \
      > "${BACKUP_DIR}/${ns}/${res}.yaml"
    test -s "${BACKUP_DIR}/${ns}/${res}.yaml" \
    || rm "${BACKUP_DIR}/${ns}/${res}.yaml"
  done
done
tar --remove-files -C "${BACKUP_DIR}" -cf - . | zstd -o "${BACKUP_DIR}.tar.zst"
