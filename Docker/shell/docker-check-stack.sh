#!/bin/bash

# ============================================================
# DOCKER DEBUG TOOL — Post Docker Compose Deploy Diagnostic
# ============================================================
# Usage: ./docker-check-stack.sh <project_name> [compose_file]
# Example: ./docker-check-stack.sh ragio
# Example: ./docker-check-stack.sh ragio ./docker-compose.yml
# ============================================================

set -e

PROJECT=$1
COMPOSE_FILE=${2:-"docker-compose.yml"}

if [[ -z "$PROJECT" ]]; then
  echo -e "\033[0;31m❌ Usage: $0 <project_name> [compose_file]\033[0m"
  echo -e "\033[1;33m   Example: $0 ragio\033[0m"
  echo -e "\033[1;33m   Example: $0 ragio ./docker-compose.yml\033[0m"
  exit 1
fi

# ---- COLORS ----
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_section() {
  echo -e "\n${BLUE}🔹 $1${NC}"
  echo "------------------------------------------------------------"
}

print_subsection() {
  echo -e "\n${CYAN}   ➜ $1${NC}"
}

docker_check_command() {
  local cmd=("$@")
  if ! "${cmd[@]}" &>/dev/null; then
    echo -e "${RED}✖ Command failed:${NC} ${cmd[*]}"
    return 1
  fi
  return 0
}

project_exists() {
  docker ps -a --filter "label=com.docker.compose.project=$PROJECT" --format "{{.ID}}" | grep -q .
}

print_section "0️⃣ Environment Check"
echo -e "${YELLOW}Docker Version:${NC}"
docker --version || echo -e "${RED}Docker not found${NC}"
echo -e "\n${YELLOW}Docker Compose Version:${NC}"
docker-compose --version || docker compose version || echo -e "${RED}Docker Compose not found${NC}"

if [[ -f "$COMPOSE_FILE" ]]; then
  echo -e "\n${GREEN}✓ Compose file found: $COMPOSE_FILE${NC}"
else
  echo -e "\n${YELLOW}⚠ Compose file not found at: $COMPOSE_FILE${NC}"
fi

print_section "1️⃣ Project & Containers Overview"
if project_exists; then
  echo -e "${GREEN}✓ Project '$PROJECT' exists${NC}\n"
  docker ps -a --filter "label=com.docker.compose.project=$PROJECT" --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}"
else
  echo -e "${RED}✖ No containers found for project '$PROJECT'${NC}"
  echo -e "${YELLOW}Tip: Check if docker-compose is running or project name is correct${NC}"
  exit 1
fi

print_section "2️⃣ Services Status (from docker-compose)"
if [[ -f "$COMPOSE_FILE" ]]; then
  docker-compose -f "$COMPOSE_FILE" -p "$PROJECT" ps || echo -e "${YELLOW}Unable to get services status${NC}"
else
  echo -e "${YELLOW}Compose file not available, using docker ps...${NC}"
  docker ps -a --filter "label=com.docker.compose.project=$PROJECT"
fi

print_section "3️⃣ Containers Detailed Inspection"
containers=($(docker ps -a --filter "label=com.docker.compose.project=$PROJECT" --format "{{.Names}}"))

if [[ ${#containers[@]} -eq 0 ]]; then
  echo -e "${YELLOW}No containers found for project '$PROJECT'${NC}"
else
  for container in "${containers[@]}"; do
    print_subsection "Container: $container"
    
    # Basic info
    echo -e "${YELLOW}Status:${NC}"
    docker inspect "$container" --format '   State: {{.State.Status}}
   Running: {{.State.Running}}
   ExitCode: {{.State.ExitCode}}
   StartedAt: {{.State.StartedAt}}
   FinishedAt: {{.State.FinishedAt}}' || echo -e "${RED}Unable to inspect $container${NC}"
    
    # Health check
    health=$(docker inspect "$container" --format '{{.State.Health.Status}}' 2>/dev/null)
    if [[ -n "$health" && "$health" != "<no value>" ]]; then
      echo -e "\n${YELLOW}Health:${NC}"
      docker inspect "$container" --format '   Status: {{.State.Health.Status}}
   FailingStreak: {{.State.Health.FailingStreak}}' || true
    fi
    
    # Restart info
    echo -e "\n${YELLOW}Restart:${NC}"
    docker inspect "$container" --format '   Policy: {{.HostConfig.RestartPolicy.Name}}
   RestartCount: {{.RestartCount}}' || true
    
    # Image
    echo -e "\n${YELLOW}Image:${NC}"
    docker inspect "$container" --format '   {{.Config.Image}}' || true
    
    echo ""
  done
fi

print_section "4️⃣ Problematic Containers (Exited/Unhealthy)"
problematic=($(docker ps -a --filter "label=com.docker.compose.project=$PROJECT" --filter "status=exited" --format "{{.Names}}"))
unhealthy=($(docker ps --filter "label=com.docker.compose.project=$PROJECT" --filter "health=unhealthy" --format "{{.Names}}"))

all_problematic=("${problematic[@]}" "${unhealthy[@]}")

if [[ ${#all_problematic[@]} -eq 0 ]]; then
  echo -e "${GREEN}✓ No problematic containers detected${NC}"
else
  for container in "${all_problematic[@]}"; do
    echo -e "${RED}--- Detailed inspection: $container${NC}"
    docker inspect "$container" --format 'Name: {{.Name}}
State: {{.State.Status}}
ExitCode: {{.State.ExitCode}}
Error: {{.State.Error}}
OOMKilled: {{.State.OOMKilled}}
FinishedAt: {{.State.FinishedAt}}
RestartPolicy: {{.HostConfig.RestartPolicy.Name}}
RestartCount: {{.RestartCount}}' || echo -e "${YELLOW}Unable to inspect $container${NC}"
    echo ""
  done
fi

print_section "5️⃣ Networks"
networks=($(docker network ls --filter "label=com.docker.compose.project=$PROJECT" --format "{{.Name}}"))

if [[ ${#networks[@]} -eq 0 ]]; then
  echo -e "${YELLOW}No networks found for project '$PROJECT'${NC}"
else
  for network in "${networks[@]}"; do
    print_subsection "Network: $network"
    docker network inspect "$network" --format 'Driver: {{.Driver}}
Scope: {{.Scope}}
Subnet: {{range .IPAM.Config}}{{.Subnet}}{{end}}
Gateway: {{range .IPAM.Config}}{{.Gateway}}{{end}}

Connected Containers:{{range $k, $v := .Containers}}
  - {{$v.Name}} ({{$v.IPv4Address}}){{end}}' || echo -e "${RED}Unable to inspect network $network${NC}"
    echo ""
  done
fi

print_section "6️⃣ Volumes"
volumes=($(docker volume ls --filter "label=com.docker.compose.project=$PROJECT" --format "{{.Name}}"))

if [[ ${#volumes[@]} -eq 0 ]]; then
  echo -e "${YELLOW}No volumes found for project '$PROJECT'${NC}"
else
  for volume in "${volumes[@]}"; do
    print_subsection "Volume: $volume"
    docker volume inspect "$volume" --format 'Driver: {{.Driver}}
Mountpoint: {{.Mountpoint}}
Labels: {{range $k, $v := .Labels}}
  {{$k}}: {{$v}}{{end}}' || echo -e "${RED}Unable to inspect volume $volume${NC}"
    
    # Check volume size
    mountpoint=$(docker volume inspect "$volume" --format '{{.Mountpoint}}' 2>/dev/null)
    if [[ -n "$mountpoint" ]]; then
      size=$(sudo du -sh "$mountpoint" 2>/dev/null | cut -f1 || echo "N/A")
      echo -e "\n${YELLOW}Size: ${NC}$size"
    fi
    echo ""
  done
fi

print_section "7️⃣ Port Mappings & Exposure"
echo -e "${YELLOW}Port mappings for all containers:${NC}\n"
for container in "${containers[@]}"; do
  ports=$(docker port "$container" 2>/dev/null)
  if [[ -n "$ports" ]]; then
    echo -e "${GREEN}$container:${NC}"
    echo "$ports" | sed 's/^/   /'
  else
    echo -e "${YELLOW}$container: No exposed ports${NC}"
  fi
  echo ""
done

print_section "8️⃣ Logs (last 50 lines for each container)"
for container in "${containers[@]}"; do
  echo -e "${GREEN}--- Logs for: $container${NC}"
  docker logs "$container" --tail=50 2>&1 || echo -e "${YELLOW}No logs available for $container${NC}"
  echo "------------------------------------------------------------"
done

print_section "9️⃣ Container Environment Variables"
for container in "${containers[@]}"; do
  print_subsection "Environment: $container"
  docker inspect "$container" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -v "PASSWORD\|SECRET\|KEY" | sed 's/^/   /' || echo -e "${YELLOW}Unable to get env vars${NC}"
  echo ""
done

print_section "🔟 Health Checks Status"
has_healthcheck=false
for container in "${containers[@]}"; do
  health=$(docker inspect "$container" --format '{{.State.Health.Status}}' 2>/dev/null)
  if [[ -n "$health" && "$health" != "<no value>" ]]; then
    has_healthcheck=true
    echo -e "${GREEN}$container:${NC}"
    docker inspect "$container" --format '   Status: {{.State.Health.Status}}
   FailingStreak: {{.State.Health.FailingStreak}}
   Last Check: {{range .State.Health.Log}}{{.End}} - {{.ExitCode}}{{end}}' | tail -5
    echo ""
  fi
done

if [[ "$has_healthcheck" == false ]]; then
  echo -e "${YELLOW}No containers with health checks configured${NC}"
fi

print_section "⓫ Connectivity Tests"
# Find a running container to test from
running_container=""
for container in "${containers[@]}"; do
  status=$(docker inspect "$container" --format '{{.State.Running}}')
  if [[ "$status" == "true" ]]; then
    running_container="$container"
    break
  fi
done

if [[ -n "$running_container" ]]; then
  echo -e "${YELLOW}Running connectivity tests from: $running_container${NC}\n"
  
  # Test DNS resolution
  echo -e "${CYAN}DNS Resolution Test:${NC}"
  for container in "${containers[@]}"; do
    if [[ "$container" != "$running_container" ]]; then
      echo -n "   Testing $container... "
      docker exec "$running_container" sh -c "getent hosts $container >/dev/null 2>&1" && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✖${NC}"
    fi
  done
  
  # Test network connectivity (ping)
  echo -e "\n${CYAN}Network Ping Test:${NC}"
  for container in "${containers[@]}"; do
    if [[ "$container" != "$running_container" ]]; then
      echo -n "   Pinging $container... "
      docker exec "$running_container" sh -c "ping -c 1 -W 2 $container >/dev/null 2>&1" && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✖${NC}"
    fi
  done
  
  # Test service ports (if known)
  echo -e "\n${CYAN}Port Connectivity Test:${NC}"
  echo -e "${YELLOW}   (Testing common ports: 80, 8000, 5432, 3000)${NC}"
  for container in "${containers[@]}"; do
    if [[ "$container" != "$running_container" ]]; then
      for port in 80 8000 5432 3000; do
        docker exec "$running_container" sh -c "timeout 2 nc -zv $container $port >/dev/null 2>&1" && echo -e "   $container:$port ${GREEN}✓${NC}"
      done
    fi
  done
else
  echo -e "${YELLOW}No running container found for connectivity tests${NC}"
fi

print_section "⓬ Resource Usage"
echo -e "${YELLOW}Current resource usage:${NC}\n"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" \
  $(docker ps --filter "label=com.docker.compose.project=$PROJECT" --format "{{.Names}}")

print_section "⓭ Docker System Info"
echo -e "${YELLOW}Disk usage:${NC}"
docker system df || echo -e "${YELLOW}Unable to get disk usage${NC}"

echo -e "\n${YELLOW}Network info:${NC}"
docker network ls --filter "label=com.docker.compose.project=$PROJECT" || echo -e "${YELLOW}Unable to get networks${NC}"

echo -e "\n${YELLOW}Volume info:${NC}"
docker volume ls --filter "label=com.docker.compose.project=$PROJECT" || echo -e "${YELLOW}Unable to get volumes${NC}"

print_section "⓮ Compose Configuration Validation"
if [[ -f "$COMPOSE_FILE" ]]; then
  echo -e "${YELLOW}Validating compose file...${NC}\n"
  docker-compose -f "$COMPOSE_FILE" config --quiet && echo -e "${GREEN}✓ Compose file is valid${NC}" || echo -e "${RED}✖ Compose file has errors${NC}"
  
  echo -e "\n${YELLOW}Services defined in compose file:${NC}"
  docker-compose -f "$COMPOSE_FILE" config --services | sed 's/^/   - /'
else
  echo -e "${YELLOW}Compose file not found, skipping validation${NC}"
fi

print_section "⓯ Recent Docker Events (last 20)"
docker events --since 10m --until 1s --filter "label=com.docker.compose.project=$PROJECT" 2>/dev/null | tail -20 || echo -e "${YELLOW}No recent events${NC}"

print_section "✅ Summary"
echo -e "${YELLOW}Project:${NC} $PROJECT"
echo -e "${YELLOW}Total containers:${NC} ${#containers[@]}"

running=$(docker ps --filter "label=com.docker.compose.project=$PROJECT" --format "{{.Names}}" | wc -l)
echo -e "${YELLOW}Running containers:${NC} $running"

exited=$(docker ps -a --filter "label=com.docker.compose.project=$PROJECT" --filter "status=exited" --format "{{.Names}}" | wc -l)
if [[ $exited -gt 0 ]]; then
  echo -e "${RED}Exited containers:${NC} $exited"
else
  echo -e "${GREEN}Exited containers:${NC} 0"
fi

unhealthy_count=$(docker ps --filter "label=com.docker.compose.project=$PROJECT" --filter "health=unhealthy" --format "{{.Names}}" | wc -l)
if [[ $unhealthy_count -gt 0 ]]; then
  echo -e "${RED}Unhealthy containers:${NC} $unhealthy_count"
fi

echo -e "\n${YELLOW}Networks:${NC} ${#networks[@]}"
echo -e "${YELLOW}Volumes:${NC} ${#volumes[@]}"

echo -e "\n${GREEN}✔ Debug completed for project '$PROJECT'${NC}"
echo -e "${YELLOW}💡 Tip: Use 'docker-compose -f $COMPOSE_FILE logs -f' for live logs${NC}"