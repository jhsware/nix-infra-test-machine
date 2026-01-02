#!/usr/bin/env bash
# n8n test for nix-infra-machine
#
# This test:
# 1. Deploys n8n with SQLite backend
# 2. Verifies all services are running
# 3. Tests n8n endpoints and functionality
# 4. Cleans up on teardown

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Handle teardown command
if [ "$CMD" = "teardown" ]; then
  echo "Tearing down n8n test..."
  
  # Stop services
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" \
    'systemctl stop n8n 2>/dev/null || true'
  
  # Clean up data directories
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" \
    'rm -rf /var/lib/n8n'
  
  echo "n8n teardown complete"
  return 0
fi

# ============================================================================
# Test Setup
# ============================================================================

_start=$(date +%s)

echo ""
echo "========================================"
echo "n8n Test (SQLite)"
echo "========================================"
echo ""

# Deploy the n8n configuration to test nodes
echo "Step 1: Deploying n8n configuration..."
$NIX_INFRA fleet deploy-apps -d "$WORK_DIR" --batch --debug --env="$ENV" \
  --test-dir="$WORK_DIR/$TEST_DIR" --no-rebuild \
  --target="$TARGET"

# Apply the configuration
echo "Step 2: Applying NixOS configuration..."
$NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" "nixos-rebuild switch --fast"

_setup=$(date +%s)

# ============================================================================
# Test Verification
# ============================================================================

echo ""
echo "Step 3: Verifying n8n deployment..."
echo ""

# Wait for services to start (n8n may take time to initialize)
echo "Waiting for services to start..."
sleep 15

# ============================================================================
# Check Service Status
# ============================================================================

echo ""
echo "Checking systemd services status..."
echo ""

# Only check n8n service (no PostgreSQL with SQLite backend)
SERVICES=("n8n")

for node in $TARGET; do
  echo "Checking services on $node..."
  
  for service in "${SERVICES[@]}"; do
    service_status=$(cmd "$node" "systemctl is-active $service")
    if [[ "$service_status" == *"active"* ]]; then
      echo -e "  ${GREEN}✓${NC} $service: active [pass]"
    else
      echo -e "  ${RED}✗${NC} $service: $service_status [fail]"
      echo ""
      echo "Service logs:"
      cmd "$node" "journalctl -n 50 -u $service"
    fi
  done
done

# ============================================================================
# Check Port Bindings
# ============================================================================

echo ""
echo "Step 4: Checking port bindings..."
echo ""

for node in $TARGET; do
  echo "Checking ports on $node..."
  
  # Check n8n port
  n8n_port=$(cmd "$node" "ss -tlnp | grep ':5678 '")
  if [[ "$n8n_port" == *":5678"* ]]; then
    echo -e "  ${GREEN}✓${NC} n8n port 5678 is listening [pass]"
  else
    echo -e "  ${RED}✗${NC} n8n port 5678 is not listening [fail]"
  fi
done

# ============================================================================
# Functional Tests
# ============================================================================

echo ""
echo "Step 5: Running functional tests..."
echo ""

for node in $TARGET; do
  echo "Testing n8n on $node..."
  
  # Test n8n HTTP response
  echo "  Testing n8n HTTP response..."
  http_code=$(cmd "$node" "curl -s -o /dev/null -w '%{http_code}' http://localhost:5678/ 2>/dev/null || echo '000'")
  # n8n may return 200 or redirect to setup/login
  if [[ "$http_code" == *"200"* ]] || [[ "$http_code" == *"302"* ]] || [[ "$http_code" == *"303"* ]]; then
    echo -e "  ${GREEN}✓${NC} HTTP response code: $http_code [pass]"
  else
    echo -e "  ${RED}✗${NC} HTTP response code: $http_code [fail]"
  fi
  
  # Test n8n healthcheck endpoint
  echo "  Testing n8n healthcheck endpoint..."
  healthcheck=$(cmd "$node" "curl -s http://localhost:5678/healthz 2>/dev/null")
  if [[ "$healthcheck" == *"ok"* ]] || [[ "$healthcheck" == *"healthy"* ]] || [[ -n "$healthcheck" ]]; then
    echo -e "  ${GREEN}✓${NC} n8n healthcheck responded: $healthcheck [pass]"
  else
    echo -e "  ${YELLOW}!${NC} n8n healthcheck response: $healthcheck [warning]"
  fi
  
  # Test n8n API types endpoint (should list available node types)
  echo "  Testing n8n API endpoint..."
  api_response=$(cmd "$node" "curl -s http://localhost:5678/api/v1/node-types 2>/dev/null | head -c 200")
  if [[ "$api_response" == *"data"* ]] || [[ "$api_response" == *"type"* ]]; then
    echo -e "  ${GREEN}✓${NC} n8n API is responding [pass]"
  else
    echo -e "  ${YELLOW}!${NC} n8n API response: ${api_response:0:100} [warning]"
  fi
  
  # Check n8n data directory exists
  echo "  Testing n8n data directory..."
  data_exists=$(cmd "$node" "test -d /var/lib/n8n && echo 'exists' || echo 'missing'")
  if [[ "$data_exists" == *"exists"* ]]; then
    echo -e "  ${GREEN}✓${NC} n8n data directory exists [pass]"
  else
    echo -e "  ${YELLOW}!${NC} n8n data directory not found [warning]"
  fi
  
  # Check SQLite database file exists
  echo "  Testing SQLite database file..."
  sqlite_exists=$(cmd "$node" "test -f /var/lib/n8n/.n8n/database.sqlite && echo 'exists' || echo 'missing'")
  if [[ "$sqlite_exists" == *"exists"* ]]; then
    echo -e "  ${GREEN}✓${NC} SQLite database file exists [pass]"
  else
    echo -e "  ${YELLOW}!${NC} SQLite database file not found (may be created on first use) [warning]"
  fi
  
  # Check service is not in error state
  echo "  Checking service state..."
  service_state=$(cmd "$node" "systemctl show -p SubState n8n --value")
  if [[ "$service_state" == "running" ]]; then
    echo -e "  ${GREEN}✓${NC} Service is running normally [pass]"
  else
    echo -e "  ${YELLOW}!${NC} Service state: $service_state [warning]"
  fi
  
  # Check for any failed units related to n8n
  echo "  Checking for failed units..."
  failed_units=$(cmd "$node" "systemctl list-units --failed | grep -i n8n || echo 'none'")
  if [[ "$failed_units" == *"none"* ]] || [[ -z "$failed_units" ]]; then
    echo -e "  ${GREEN}✓${NC} No failed n8n related units [pass]"
  else
    echo -e "  ${RED}✗${NC} Failed units found: $failed_units [fail]"
  fi
  
  # Check n8n process is running
  echo "  Checking n8n process..."
  n8n_process=$(cmd "$node" "pgrep -f n8n || echo 'not_found'")
  if [[ "$n8n_process" != *"not_found"* ]] && [[ -n "$n8n_process" ]]; then
    echo -e "  ${GREEN}✓${NC} n8n process is running (PID: $n8n_process) [pass]"
  else
    echo -e "  ${RED}✗${NC} n8n process not found [fail]"
  fi
done

# ============================================================================
# Test Summary
# ============================================================================

_end=$(date +%s)

echo ""
echo "========================================"
echo "n8n Test Summary (SQLite)"
echo "========================================"

printTime() {
  local _start=$1; local _end=$2; local _secs=$((_end-_start))
  printf '%02dh:%02dm:%02ds' $((_secs/3600)) $((_secs%3600/60)) $((_secs%60))
}

printf '+ setup     %s\n' $(printTime $_start $_setup)
printf '+ tests     %s\n' $(printTime $_setup $_end)
printf '= TOTAL     %s\n' $(printTime $_start $_end)

echo ""
echo "========================================"
echo "n8n Test Complete"
echo "========================================"
