#!/bin/bash

# ============================================================
# DOCKER QUICK HEALTH CHECK — Fast Status Overview
# ============================================================
# Usage: ./docker-quick-check.sh <project_name>
# Example: ./docker-quick-check.sh ragio
# ============================================================

set -e

PROJECT=$1

if [[ -z "$PROJECT" ]]; then
  echo -e "\033[0;31m❌ Usage: $0 <project_name>\033[0m"
  echo -e "\033[1;33m   Example: $0 ragio\033[0m"
  exit 1
fi

# ---- COLORS ----
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[1;34m'
BOLD='\033[1m'
NC='\033[0m'

# Check if project exists
if ! docker ps -a --filter "label=com.docker.compose.project=$PROJECT" --format "{{.ID}}" | grep -q .; then
  echo -e "${RED}✖ Project '$PROJECT' not found${NC}"
  exit 1
fi

echo -e "${BOLD}${BLUE}"
echo "╔═══════════════════════════════════════════════════╗"
echo "║     DOCKER QUICK HEALTH CHECK: $PROJECT          "
echo "╚═══════════════════════════════════════════════════╝"
echo -e "${NC}"

# Containers status
echo -e "${YELLOW}📦 CONTAINERS STATUS${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

total=$(docker ps -a --filter "label=com.docker.compose.project=$PROJECT" --format "{{.Names}}" | wc -l)
running=$(docker ps --filter "label=com.docker.compose.project=$PROJECT" --format "{{.Names}}" | wc -l)
exited=$(docker ps -a --filter "label=com.docker.compose.project=$PROJECT" --filter "status=exited" --format "{{.Names}}" | wc -l)
restarting=$(docker ps -a --filter "label=com.docker.compose.project=$PROJECT" --filter "status=restarting" --format "{{.Names}}" | wc -l)

echo -e "Total:       ${BOLD}$total${NC}"
echo -e "Running:     ${GREEN}$running${NC}"
[[ $exited -gt 0 ]] && echo -e "Exited:      ${RED}$exited${NC}" || echo -e "Exited:      ${GREEN}0${NC}"
[[ $restarting -gt 0 ]] && echo -e "Restarting:  ${YELLOW}$restarting${NC}"

echo ""
docker ps -a --filter "label=com.docker.compose.project=$PROJECT" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Health checks
echo -e "\n${YELLOW}💚 HEALTH CHECKS${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

has_health=false
containers=($(docker ps --filter "label=com.docker.compose.project=$PROJECT" --format "{{.Names}}"))

for container in "${containers[@]}"; do
  health=$(docker inspect "$container" --format '{{.State.Health.Status}}' 2>/dev/null)
  if [[ -n "$health" && "$health" != "<no value>" ]]; then
    has_health=true
    case "$health" in
      "healthy")
        echo -e "${GREEN}✓${NC} $container: ${GREEN}$health${NC}"
        ;;
      "unhealthy")
        echo -e "${RED}✖${NC} $container: ${RED}$health${NC}"
        ;;
      "starting")
        echo -e "${YELLOW}⟳${NC} $container: ${YELLOW}$health${NC}"
        ;;
      *)
        echo -e "${YELLOW}?${NC} $container: $health"
        ;;
    esac
  fi
done

[[ "$has_health" == false ]] && echo -e "${YELLOW}No health checks configured${NC}"

# Port mappings
echo -e "\n${YELLOW}🔌 PORT MAPPINGS${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for container in "${containers[@]}"; do
  ports=$(docker port "$container" 2>/dev/null)
  if [[ -n "$ports" ]]; then
    echo -e "${GREEN}$container:${NC}"
    echo "$ports" | sed 's/^/  /'
  fi
done

# Resource usage
echo -e "\n${YELLOW}📊 RESOURCE USAGE${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" \
  $(docker ps --filter "label=com.docker.compose.project=$PROJECT" --format "{{.Names}}")

# Recent errors (last 10 lines of logs)
echo -e "\n${YELLOW}⚠️  RECENT ERRORS (last 10 log lines)${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

error_found=false
for container in "${containers[@]}"; do
  errors=$(docker logs "$container" --tail=10 2>&1 | grep -iE "error|fail|exception|fatal|panic" || true)
  if [[ -n "$errors" ]]; then
    error_found=true
    echo -e "${RED}$container:${NC}"
    echo "$errors" | sed 's/^/  /'
    echo ""
  fi
done

[[ "$error_found" == false ]] && echo -e "${GREEN}✓ No recent errors detected${NC}"

# Network connectivity
echo -e "\n${YELLOW}🌐 NETWORK CONNECTIVITY${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

networks=($(docker network ls --filter "label=com.docker.compose.project=$PROJECT" --format "{{.Name}}"))
echo -e "Networks: ${GREEN}${#networks[@]}${NC}"
for net in "${networks[@]}"; do
  count=$(docker network inspect "$net" --format '{{range $k, $v := .Containers}}{{$v.Name}} {{end}}' | wc -w)
  echo -e "  └─ $net (${GREEN}$count${NC} containers)"
done

# Volumes
echo -e "\n${YELLOW}💾 VOLUMES${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

volumes=($(docker volume ls --filter "label=com.docker.compose.project=$PROJECT" --format "{{.Name}}"))
echo -e "Volumes: ${GREEN}${#volumes[@]}${NC}"
for vol in "${volumes[@]}"; do
  mountpoint=$(docker volume inspect "$vol" --format '{{.Mountpoint}}' 2>/dev/null)
  if [[ -n "$mountpoint" ]]; then
    size=$(sudo du -sh "$mountpoint" 2>/dev/null | cut -f1 || echo "N/A")
    echo -e "  └─ $vol (${YELLOW}$size${NC})"
  else
    echo -e "  └─ $vol"
  fi
done

# Overall status
echo -e "\n${BOLD}${BLUE}"
echo "╔═══════════════════════════════════════════════════╗"
echo "║                 OVERALL STATUS                    ║"
echo "╚═══════════════════════════════════════════════════╝"
echo -e "${NC}"

if [[ $running -eq $total ]] && [[ $exited -eq 0 ]] && [[ $restarting -eq 0 ]]; then
  echo -e "${GREEN}✅ ALL SYSTEMS OPERATIONAL${NC}"
  echo -e "   All containers are running successfully"
elif [[ $exited -gt 0 ]] || [[ $restarting -gt 0 ]]; then
  echo -e "${RED}❌ ISSUES DETECTED${NC}"
  echo -e "   Some containers are not running properly"
  echo -e "   Run: ${YELLOW}./docker-check-stack.sh $PROJECT${NC} for detailed diagnostics"
else
  echo -e "${YELLOW}⚠️  PARTIAL OPERATION${NC}"
  echo -e "   System is running but may need attention"
fi

echo -e "\n${YELLOW}💡 Quick Commands:${NC}"
echo -e "   View logs:     ${BLUE}docker-compose logs -f${NC}"
echo -e "   Restart all:   ${BLUE}docker-compose restart${NC}"
echo -e "   Full check:    ${BLUE}./docker-check-stack.sh $PROJECT${NC}"
echo ""