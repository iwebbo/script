#!/bin/bash

# ============================================================
# KUBE DEBUG TOOL — Post Helm Install/Upgrade Diagnostic
# ============================================================
# chmox +x kube-check-namespace.sh (execute in bash mandatory)
# Usage: ./kube-check-namespace <namespace>
# ============================================================

NS=$1

if [ -z "$NS" ]; then
  echo "❌  Usage: $0 <namespace>"
  exit 1
fi

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

print_section "1️⃣  Namespace & Services"
kubectl get ns | grep "$NS" || { echo -e "${RED}Namespace not found${NC}"; exit 1; }
kubectl get svc -n "$NS" -o wide

print_section "2️⃣  Deployments & Pods"
kubectl get deploy -n "$NS" -o wide
kubectl get pods -n "$NS" -o wide

print_section "3️⃣  Pods Detailed Status"
for pod in $(kubectl get pods -n "$NS" -o name); do
  echo -e "${YELLOW}Inspecting $pod${NC}"
  kubectl describe "$pod" -n "$NS" | grep -E "Name:|State:|Reason:|Image:|Message:" | sed 's/^/   /'
done

print_section "4️⃣  Logs (last 30 lines for each pod)"
for pod in $(kubectl get pods -n "$NS" -o name); do
  echo -e "${GREEN}Logs for $pod${NC}"
  kubectl logs "$pod" -n "$NS" --tail=30 2>/dev/null || echo "No logs available"
  echo "------------------------------------------------------------"
done

print_section "5️⃣  Endpoints & Connectivity"
kubectl get endpoints -n "$NS"
FIRST_POD=$(kubectl get pods -n "$NS" -o name | head -n 1)
if [ -n "$FIRST_POD" ]; then
  echo -e "\n${YELLOW}Running basic connectivity tests from $FIRST_POD...${NC}"
  kubectl exec -it "$FIRST_POD" -n "$NS" -- sh -c "apk add --no-cache curl bind-tools &>/dev/null; nslookup kubernetes.default.svc.cluster.local; echo; curl -s -o /dev/null -w '%{http_code}\n' http://theai-backend:8000 || true"
fi

print_section "6️⃣  Ingress & Controller Check"
kubectl get ingress -n "$NS"
kubectl describe ingress -n "$NS" 2>/dev/null | grep -E "Host:|Address:|Backend:" || echo "No ingress description available"
echo -e "\n${YELLOW}Checking ingress controllers...${NC}"
kubectl get pods -A | grep ingress || echo "No ingress controller detected"
kubectl get svc -A | grep ingress || echo "No ingress service detected"

print_section "✅  Summary"
kubectl get all -n "$NS"

echo -e "\n${GREEN}✔ Debug completed for namespace '$NS'${NC}"
