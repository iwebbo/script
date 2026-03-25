#!/usr/bin/env bash
set -e

# ============================================================
# KUBE NAMESPACE DELETE TOOL
# ============================================================
# Usage:
#   ./kube-delete-namespace.sh <namespace> [--force]
#
# Example:
#   ./kube-delete-namespace.sh theai
#   ./kube-delete-namespace.sh theai --force
# ============================================================

NS=$1
FORCE=$2

# ---- COLORS ----
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

print_section() {
  echo -e "\n${BLUE}🔹 $1${NC}"
  echo "------------------------------------------------------------"
}

if [ -z "$NS" ]; then
  echo -e "${RED}❌ Usage:${NC} $0 <namespace> [--force]"
  exit 1
fi

# ---- Check existence ----
print_section "1️⃣ Checking namespace '$NS'"
if ! kubectl get ns "$NS" &>/dev/null; then
  echo -e "${RED}Namespace '$NS' not found.${NC}"
  exit 0
fi

echo -e "${YELLOW}Namespace found:${NC}"
kubectl get ns "$NS"

# ---- Confirmation ----
print_section "2️⃣ Deletion confirmation"
read -p "⚠️  Are you sure you want to delete namespace '$NS'? [y/N]: " choice
if [[ ! "$choice" =~ ^[Yy]$ ]]; then
  echo -e "${YELLOW}Deletion cancelled.${NC}"
  exit 0
fi

# ---- Delete namespace ----
print_section "3️⃣ Deleting namespace '$NS'"
kubectl delete ns "$NS" || true

# ---- Check if stuck ----
echo -e "\n${YELLOW}⏳ Waiting for namespace to terminate...${NC}"
for i in {1..10}; do
  if ! kubectl get ns "$NS" &>/dev/null; then
    echo -e "${GREEN}✔ Namespace '$NS' successfully deleted.${NC}"
    exit 0
  fi
  sleep 2
done

# ---- Force deletion if requested ----
if [ "$FORCE" == "--force" ]; then
  print_section "⚠️  Force deleting stuck namespace '$NS'"
  echo -e "${YELLOW}Removing finalizers manually...${NC}"

  kubectl get ns "$NS" -o json | jq '
    del(.spec.finalizers)
  ' | kubectl replace --raw "/api/v1/namespaces/$NS/finalize" -f - >/dev/null 2>&1 || true

  if ! kubectl get ns "$NS" &>/dev/null; then
    echo -e "${GREEN}✔ Namespace '$NS' force-deleted.${NC}"
  else
    echo -e "${RED}❌ Namespace '$NS' still present, manual check required.${NC}"
  fi
else
  echo -e "${YELLOW}Namespace '$NS' still terminating. Use:$NC $0 $NS --force"
fi
