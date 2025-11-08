#!/bin/bash

# ============================================================
# KUBE DEBUG TOOL — Post Helm Install/Upgrade Diagnostic
# ============================================================
# Usage: ./kube-check-namespace.sh <namespace>
# ============================================================

set -e

NS=$1

if [[ -z "$NS" ]]; then
  echo -e "\033[0;31m❌ Usage: $0 <namespace>\033[0m"
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

kubectl_ns_exists() {
  kubectl get ns "$NS" &>/dev/null
}

kubectl_check_command() {
  local cmd=("$@")
  if ! "${cmd[@]}" &>/dev/null; then
    echo -e "${RED}✖ Command failed:${NC} ${cmd[*]}"
  fi
}

print_section "1️⃣ Namespace & Basic Info"
if kubectl_ns_exists; then
  kubectl get ns "$NS" -o wide
else
  echo -e "${RED}Namespace '$NS' does not exist.${NC}"
  exit 1
fi

print_section "2️⃣ Services in Namespace"
kubectl get svc -n "$NS" -o wide || echo -e "${YELLOW}No services found or unable to fetch services${NC}"

print_section "3️⃣ Deployments & Pods"
kubectl get deploy -n "$NS" -o wide || echo -e "${YELLOW}No deployments found or unable to fetch deployments${NC}"
kubectl get pods -n "$NS" -o wide || echo -e "${YELLOW}No pods found or unable to fetch pods${NC}"

print_section "4️⃣.b️⃣ Detailed Describe for Problematic Pods"

# Récupérer les pods en état problématique (CrashLoopBackOff, Pending, etc.)
problematic_pods=($(kubectl get pods -n "$NS" --field-selector=status.phase!=Running -o jsonpath='{.items[*].metadata.name}'))

if [[ ${#problematic_pods[@]} -eq 0 ]]; then
  echo -e "${GREEN}No problematic pods detected in namespace '$NS'.${NC}"
else
  for pod in "${problematic_pods[@]}"; do
    echo -e "${RED}--- Describing problematic pod: $pod${NC}"
    kubectl describe pod "$pod" -n "$NS" || echo -e "${YELLOW}Unable to describe pod $pod${NC}"
    echo
  done
fi

print_section "4️⃣ Pods Detailed Status"
pods=($(kubectl get pods -n "$NS" -o jsonpath='{.items[*].metadata.name}'))
if [[ ${#pods[@]} -eq 0 ]]; then
  echo -e "${YELLOW}No pods to describe in namespace '$NS'.${NC}"
else
  for pod in "${pods[@]}"; do
    echo -e "${YELLOW}--- Inspecting pod: $pod${NC}"
    kubectl describe pod "$pod" -n "$NS" | grep -E "Name:|State:|Reason:|Message:|Containers:|Image:" | sed 's/^/   /'
    echo
  done
fi

print_section "5️⃣ PersistentVolumeClaims (PVCs)"
pvcs=($(kubectl get pvc -n "$NS" -o jsonpath='{.items[*].metadata.name}'))
if [[ ${#pvcs[@]} -eq 0 ]]; then
  echo -e "${YELLOW}No PVCs found in namespace '$NS'.${NC}"
else
  for pvc in "${pvcs[@]}"; do
    echo -e "${YELLOW}--- Describe PVC: $pvc${NC}"
    kubectl describe pvc "$pvc" -n "$NS"
    echo
  done
fi

print_section "6️⃣ PersistentVolumes (PV) related"
for pvc in "${pvcs[@]}"; do
  volume=$(kubectl get pvc "$pvc" -n "$NS" -o jsonpath='{.spec.volumeName}')
  if [[ -n "$volume" ]]; then
    echo -e "${YELLOW}--- Describe PV: $volume (for PVC $pvc)${NC}"
    kubectl describe pv "$volume" || echo -e "${YELLOW}Unable to describe PV $volume${NC}"
    echo
  else
    echo -e "${YELLOW}PVC $pvc is not yet bound to a PV.${NC}"
  fi
done

print_section "7️⃣ Events in Namespace (last 50)"
kubectl get events -n "$NS" --sort-by='.lastTimestamp' | tail -50 || echo -e "${YELLOW}No events or unable to fetch events${NC}"

print_section "8️⃣ Logs (last 30 lines for each pod)"
for pod in "${pods[@]}"; do
  echo -e "${GREEN}--- Logs for pod: $pod${NC}"
  kubectl logs "$pod" -n "$NS" --tail=30 || echo "No logs available"
  echo "------------------------------------------------------------"
done

print_section "9️⃣ Endpoints & Connectivity"
kubectl get endpoints -n "$NS" || echo -e "${YELLOW}No endpoints found${NC}"

ready_pod=""
for pod in "${pods[@]}"; do
  ready_status=$(kubectl get pod "$pod" -n "$NS" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  if [[ "$ready_status" == "True" ]]; then
    ready_pod="$pod"
    break
  fi
done

if [[ -n "$ready_pod" ]]; then
  echo -e "${YELLOW}Running connectivity tests from ready pod: $ready_pod${NC}"
  kubectl exec "$ready_pod" -n "$NS" -- sh -c "timeout 5 sh -c 'apk add --no-cache curl bind-tools >/dev/null 2>&1 || true'; nslookup kubernetes.default.svc.cluster.local || echo 'nslookup failed'; echo; curl -s -o /dev/null -w '%{http_code}\n' http://theai-backend:8000 || echo 'curl failed'"
else
  echo -e "${YELLOW}No Ready pod found for connectivity tests.${NC}"
fi

print_section "🔟 Ingress & Controller Check"
kubectl get ingress -n "$NS" || echo -e "${YELLOW}No ingress resources found${NC}"
kubectl describe ingress -n "$NS" 2>/dev/null | grep -E "Host:|Address:|Backend:" || echo "No ingress description available"

echo -e "\n${YELLOW}Checking ingress controllers in all namespaces...${NC}"
kubectl get pods -A | grep ingress || echo "No ingress controller detected"
kubectl get svc -A | grep ingress || echo "No ingress service detected"

print_section "⓫ Node Status Summary"
kubectl get nodes -o wide || echo -e "${YELLOW}Unable to fetch nodes status${NC}"

print_section "✅ Summary of all resources in namespace"
kubectl get all -n "$NS" || echo -e "${YELLOW}Unable to fetch all resources${NC}"

echo -e "\n${GREEN}✔ Debug completed for namespace '$NS'${NC}"
