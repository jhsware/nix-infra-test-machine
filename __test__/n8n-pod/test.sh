#!/usr/bin/env bash
# n8n-pod test for nix-infra-machine
#
# This test:
# 1. Deploys n8n as a podman container with SQLite backend
# 2. Verifies the service is running
# 3. Tests n8n endpoints and functionality
# 4. Cleans up on teardown

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Handle teardown command
if [ "$CMD" = "teardown" ]; then
  echo "Tearing down n8n-pod test..."
  
  # Stop and remove container if running
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" \
    'systemctl stop podman-n8n-pod 2>/dev/null || true'
  
  # Clean up data directory
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" \
    'rm -rf /var/lib/n8n-pod'
  
  echo "n8n-pod teardown complete"
  return 0
fi

# ============================================================================
# Test Setup
# ============================================================================

_start=$(date +%s)

echo ""
echo "========================================"
echo "n8n-pod Test (SQLite, Container)"
echo "========================================"
echo ""

# Deploy the n8n-pod configuration to test nodes
echo "Step 1: Deploying n8n-pod configuration..."
$NIX_INFRA fleet deploy-apps -d "$WORK_DIR" --batch --env="$ENV" \
  --test-dir="$WORK_DIR/$TEST_DIR" \
  --target="$TARGET"

# Apply the configuration
echo "Step 2: Applying NixOS configuration..."
$NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" "nixos-rebuild switch --fast"

_setup=$(date +%s)

# ============================================================================
# Test Verification
# ============================================================================

echo ""
echo "Step 3: Verifying n8n-pod deployment..."
echo ""

# Wait for container to start and n8n to initialize
echo "Waiting for n8n container to start..."
sleep 15

# ============================================================================
# Check Service Status
# ============================================================================

echo ""
echo "Checking systemd service status..."
for node in $TARGET; do
  service_status=$(cmd "$node" "systemctl is-active podman-n8n-pod")
  if [[ "$service_status" == *"active"* ]]; then
    echo -e "  ${GREEN}✓${NC} podman-n8n-pod: active ($node) [pass]"
  else
    echo -e "  ${RED}✗${NC} podman-n8n-pod: $service_status ($node) [fail]"
    echo ""
    echo "Service logs:"
    cmd "$node" "journalctl -n 50 -u podman-n8n-pod"
  fi
done

# Check if container is running
echo ""
echo "Checking container status..."
for node in $TARGET; do
  container_status=$(cmd "$node" "podman ps --filter name=n8n-pod --format '{{.Names}} {{.Status}}'")
  if [[ "$container_status" == *"n8n-pod"* ]]; then
    echo -e "  ${GREEN}✓${NC} Container running: $container_status ($node) [pass]"
  else
    echo -e "  ${RED}✗${NC} Container not running ($node) [fail]"
    echo "All containers:"
    cmd "$node" "podman ps -a"
  fi
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
    echo -e "  ${YELLOW}!${NC} n8n healthcheck response: $healthcheck [fail]"
  fi
  
  # Test n8n API types endpoint (should list available node types)
  echo "  Testing n8n API endpoint..."
  api_response=$(cmd "$node" "curl -s http://localhost:5678/api/v1/node-types 2>/dev/null | head -c 200")
  if [[ "$api_response" == *"data"* ]] || [[ "$api_response" == *"type"* ]]; then
    echo -e "  ${GREEN}✓${NC} n8n API is responding [pass]"
  else
    echo -e "  ${YELLOW}!${NC} n8n API response: ${api_response:0:100} [fail]"
  fi
  
  # Check n8n data directory exists on host
  echo "  Testing n8n data directory..."
  data_exists=$(cmd "$node" "test -d /var/lib/n8n-pod && echo 'exists' || echo 'missing'")
  if [[ "$data_exists" == *"exists"* ]]; then
    echo -e "  ${GREEN}✓${NC} n8n data directory exists [pass]"
  else
    echo -e "  ${YELLOW}!${NC} n8n data directory not found [fail]"
  fi
  
  # Check SQLite database file exists (inside container volume)
  echo "  Testing SQLite database file..."
  sqlite_exists=$(cmd "$node" "test -f /var/lib/n8n-pod/database.sqlite && echo 'exists' || echo 'missing'")
  if [[ "$sqlite_exists" == *"exists"* ]]; then
    echo -e "  ${GREEN}✓${NC} SQLite database file exists [pass]"
  else
    echo -e "  ${YELLOW}!${NC} SQLite database file not found (may be created on first use) [fail]"
  fi
  
  # Check container logs for errors
  echo "  Checking container logs for errors..."
  error_logs=$(cmd "$node" "podman logs n8n-pod 2>&1 | grep -i 'error\|fatal' | tail -5 || echo 'none'")
  if [[ "$error_logs" == *"none"* ]] || [[ -z "$error_logs" ]]; then
    echo -e "  ${GREEN}✓${NC} No errors in container logs [pass]"
  else
    echo -e "  ${YELLOW}!${NC} Errors found in logs: $error_logs [fail]"
  fi
  
  # Check container health
  echo "  Checking container process..."
  n8n_process=$(cmd "$node" "podman exec n8n-pod pgrep -f 'n8n' || echo 'not_found'")
  if [[ "$n8n_process" != *"not_found"* ]] && [[ -n "$n8n_process" ]]; then
    echo -e "  ${GREEN}✓${NC} n8n process is running inside container [pass]"
  else
    echo -e "  ${RED}✗${NC} n8n process not found in container [fail]"
  fi
done

# ============================================================================
# Test Summary
# ============================================================================

_end=$(date +%s)

echo ""
echo "========================================"
echo "n8n-pod Test Summary (SQLite, Container)"
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
echo "n8n-pod Test Complete"
echo "========================================"
