#!/usr/bin/env bash
# Home Assistant test for nix-infra-machine
#
# This test:
# 1. Deploys Home Assistant with the infrastructure module
# 2. Verifies the service is running
# 3. Tests Home Assistant endpoints and functionality
# 4. Cleans up on teardown

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Handle teardown command
if [ "$CMD" = "teardown" ]; then
  echo "Tearing down Home Assistant test..."
  
  # Stop services
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" \
    'systemctl stop home-assistant 2>/dev/null || true'
  
  # Clean up data directories
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" \
    'rm -rf /var/lib/hass'
  
  echo "Home Assistant teardown complete"
  return 0
fi

# ============================================================================
# Test Setup
# ============================================================================

_start=$(date +%s)

echo ""
echo "========================================"
echo "Home Assistant Test"
echo "========================================"
echo ""

# Deploy the home-assistant configuration to test nodes
echo "Step 1: Deploying Home Assistant configuration..."
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
echo "Step 3: Verifying Home Assistant deployment..."
echo ""

# Wait for services to start (Home Assistant can take some time to initialize)
echo "Waiting for Home Assistant to start (this may take a while for initial setup)..."
sleep 30

# ============================================================================
# Check Service Status
# ============================================================================

echo ""
echo "Checking systemd services status..."
echo ""

# Array of services to check
SERVICES=("home-assistant")

for node in $TARGET; do
  echo "Checking services on $node..."
  
  for service in "${SERVICES[@]}"; do
    service_status=$(cmd_value "$node" "systemctl is-active $service")
    if [[ "$service_status" == "active" ]]; then
      echo -e "  ${GREEN}✓${NC} $service: active [pass]"
    else
      echo -e "  ${RED}✗${NC} $service: $service_status [fail]"
      echo ""
      echo "Service logs:"
      cmd "$node" "journalctl -n 100 -u $service"
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
  
  # Check Home Assistant port
  ha_port=$(cmd "$node" "ss -tlnp | grep ':8123 '")
  if [[ "$ha_port" == *":8123"* ]]; then
    echo -e "  ${GREEN}✓${NC} Home Assistant port 8123 is listening [pass]"
  else
    echo -e "  ${RED}✗${NC} Home Assistant port 8123 is not listening [fail]"
  fi
done

# ============================================================================
# Functional Tests
# ============================================================================

echo ""
echo "Step 5: Running functional tests..."
echo ""

for node in $TARGET; do
  echo "Testing Home Assistant on $node..."
  
  # Test Home Assistant HTTP response
  echo "  Testing Home Assistant HTTP response..."
  http_code=$(cmd_value "$node" "curl -s -o /dev/null -w '%{http_code}' http://localhost:8123/ 2>/dev/null || echo '000'")
  # Home Assistant may return 200 or redirect to onboarding
  if [[ "$http_code" == "200" ]] || [[ "$http_code" == "302" ]] || [[ "$http_code" == "303" ]]; then
    echo -e "  ${GREEN}✓${NC} HTTP response code: $http_code [pass]"
  else
    echo -e "  ${RED}✗${NC} HTTP response code: $http_code [fail]"
  fi
  
  # Test Home Assistant API health check
  echo "  Testing Home Assistant API health..."
  api_response=$(cmd_clean "$node" "curl -s http://localhost:8123/api/ 2>/dev/null")
  if [[ "$api_response" == *"API running"* ]] || [[ "$api_response" == *"message"* ]]; then
    echo -e "  ${GREEN}✓${NC} Home Assistant API is responding [pass]"
  else
    echo -e "  ${YELLOW}!${NC} Home Assistant API response: ${api_response:0:100} [fail]"
  fi
  
  # Test Home Assistant manifest
  echo "  Testing Home Assistant manifest endpoint..."
  manifest_response=$(cmd_clean "$node" "curl -s http://localhost:8123/manifest.json 2>/dev/null")
  if [[ "$manifest_response" == *"Home Assistant"* ]]; then
    echo -e "  ${GREEN}✓${NC} Home Assistant manifest is accessible [pass]"
  else
    echo -e "  ${YELLOW}!${NC} Manifest response: ${manifest_response:0:100} [fail]"
  fi
  
  # Test Home Assistant frontend assets
  echo "  Testing Home Assistant frontend..."
  frontend_response=$(cmd_value "$node" "curl -s -o /dev/null -w '%{http_code}' http://localhost:8123/frontend_latest/app.js 2>/dev/null || echo '000'")
  if [[ "$frontend_response" == "200" ]]; then
    echo -e "  ${GREEN}✓${NC} Frontend assets are accessible [pass]"
  else
    echo -e "  ${YELLOW}!${NC} Frontend response code: $frontend_response [fail]"
  fi
  
  # Check configuration directory exists
  echo "  Testing configuration directory..."
  config_exists=$(cmd_value "$node" "test -d /var/lib/hass && echo 'exists' || echo 'missing'")
  if [[ "$config_exists" == "exists" ]]; then
    echo -e "  ${GREEN}✓${NC} Configuration directory exists [pass]"
  else
    echo -e "  ${RED}✗${NC} Configuration directory missing [fail]"
  fi
  
  # Check configuration file exists
  echo "  Testing configuration.yaml..."
  config_file=$(cmd_value "$node" "test -f /var/lib/hass/configuration.yaml && echo 'exists' || echo 'missing'")
  if [[ "$config_file" == "exists" ]]; then
    echo -e "  ${GREEN}✓${NC} configuration.yaml exists [pass]"
  else
    echo -e "  ${YELLOW}!${NC} configuration.yaml not found (may be using NixOS-managed config) [fail]"
  fi
  
  # Check Home Assistant database
  echo "  Testing Home Assistant database..."
  db_exists=$(cmd_value "$node" "test -f /var/lib/hass/home-assistant_v2.db && echo 'exists' || echo 'missing'")
  if [[ "$db_exists" == "exists" ]]; then
    echo -e "  ${GREEN}✓${NC} Home Assistant database exists [pass]"
  else
    echo -e "  ${YELLOW}!${NC} Database not found (may still be initializing) [fail]"
  fi
  
  # Check service is not in error state
  echo "  Checking service state..."
  service_state=$(cmd_value "$node" "systemctl show -p SubState home-assistant --value")
  if [[ "$service_state" == "running" ]]; then
    echo -e "  ${GREEN}✓${NC} Service is running normally [pass]"
  else
    echo -e "  ${YELLOW}!${NC} Service state: $service_state [fail]"
  fi
  
  # Check for any failed units related to home-assistant
  echo "  Checking for failed units..."
  failed_units=$(cmd_clean "$node" "systemctl list-units --failed | grep -i home || echo 'none'")
  if [[ "$failed_units" == *"none"* ]] || [[ -z "$failed_units" ]]; then
    echo -e "  ${GREEN}✓${NC} No failed home-assistant related units [pass]"
  else
    echo -e "  ${RED}✗${NC} Failed units found: $failed_units [fail]"
  fi
done

# ============================================================================
# Test Summary
# ============================================================================

_end=$(date +%s)

echo ""
echo "========================================"
echo "Home Assistant Test Summary"
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
echo "Home Assistant Test Complete"
echo "========================================"
