#!/bin/bash

# ============================================================
# KUBE STORAGECLASS CREATOR
# ============================================================
# Usage:
#   ./kube-storageclass.sh <storageclass-name> <provisioner> [reclaimPolicy] [volumeBindingMode]
#
# Example:
#   chmox +x kube-storageclass.sh (bash execution mandatory)
#   ./kube-storageclass.sh standard kubernetes.io/no-provisioner Retain WaitForFirstConsumer
# ============================================================

NAME=$1
PROVISIONER=$2
RECLAIM_POLICY=${3:-Delete}
VOLUME_BINDING=${4:-Immediate}

# ---- COLORS ----
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

# ---- CHECKS ----
if [ -z "$NAME" ] || [ -z "$PROVISIONER" ]; then
  echo -e "${RED}Usage:${NC} $0 <name> <provisioner> [reclaimPolicy] [volumeBindingMode]"
  exit 1
fi

print_section() {
  echo -e "\n${BLUE}🔹 $1${NC}"
  echo "------------------------------------------------------------"
}

print_section "1️⃣  Checking if StorageClass '$NAME' exists"
if kubectl get storageclass "$NAME" &>/dev/null; then
  echo -e "${YELLOW}StorageClass '$NAME' already exists.${NC}"
  kubectl get storageclass "$NAME" -o yaml
  exit 0
fi

print_section "2️⃣  Creating StorageClass '$NAME'"
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${NAME}
provisioner: ${PROVISIONER}
reclaimPolicy: ${RECLAIM_POLICY}
volumeBindingMode: ${VOLUME_BINDING}
EOF

if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Failed to create StorageClass.${NC}"
  exit 1
else
  echo -e "${GREEN}✔ StorageClass '${NAME}' created successfully.${NC}"
fi

print_section "3️⃣  Verifying StorageClass"
kubectl get storageclass "$NAME" -o wide

print_section "4️⃣  Marking '${NAME}' as default (optional)"
read -p "👉 Do you want to make '${NAME}' the default StorageClass? [y/N]: " choice
if [[ "$choice" =~ ^[Yy]$ ]]; then
  kubectl patch storageclass "$NAME" -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
  echo -e "${GREEN}✔ '${NAME}' is now the default StorageClass.${NC}"
else
  echo -e "${YELLOW}Skipped setting default StorageClass.${NC}"
fi

print_section "✅ Done"
kubectl get storageclass
