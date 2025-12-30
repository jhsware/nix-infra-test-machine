#!/usr/bin/env bash
# Redis standalone test for nix-infra-machine
#
# This test:
# 1. Deploys Redis as a native service on custom port 6380
# 2. Verifies the service is running
# 3. Tests basic Redis operations (SET/GET)
# 4. Cleans up on teardown

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Custom port for testing
REDIS_PORT=6380

# Handle teardown command
if [ "$CMD" = "teardown" ]; then
  echo "Tearing down Redis test..."
  
  # Stop Redis service
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TEST_NODES" \
    'systemctl stop redis 2>/dev/null || true'
  
  # Clean up data directory
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TEST_NODES" \
    'rm -rf /var/lib/redis'
  
  echo "Redis teardown complete"
  return 0
fi

# ============================================================================
# Test Setup
# ============================================================================

_start=$(date +%s)

echo ""
echo "========================================"
echo "Redis Standalone Test (port $REDIS_PORT)"
echo "========================================"
echo ""

# Deploy the redis configuration to test nodes
echo "Step 1: Deploying Redis configuration..."
$NIX_INFRA fleet deploy-apps -d "$WORK_DIR" --batch --env="$ENV" \
  --test-dir="$WORK_DIR/$TEST_DIR" \
  --target="$TEST_NODES"

# Apply the configuration
echo "Step 2: Applying NixOS configuration..."
$NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TEST_NODES" "nixos-rebuild switch --fast"

_setup=$(date +%s)

# ============================================================================
# Test Verification
# ============================================================================

echo ""
echo "Step 3: Verifying Redis deployment..."
echo ""

# Wait for service to start
echo "Waiting for Redis service to start..."
sleep 5

# Check if the systemd service is active
echo "Checking systemd service status..."
for node in $TEST_NODES; do
  service_status=$(cmd "$node" "systemctl is-active redis")
  if [[ "$service_status" == *"active"* ]]; then
    echo -e "  ${GREEN}✓${NC} redis: active ($node) [pass]"
  else
    echo -e "  ${RED}✗${NC} redis: $service_status ($node) [fail]"
    echo ""
    echo "Service logs:"
    cmd "$node" "journalctl -n 30 -u redis"
  fi
done

# Check if Redis process is running
echo ""
echo "Checking Redis process..."
for node in $TEST_NODES; do
  process_status=$(cmd "$node" "pgrep -a redis-server")
  if [[ -n "$process_status" ]]; then
    echo -e "  ${GREEN}✓${NC} Redis process running ($node) [pass]"
  else
    echo -e "  ${RED}✗${NC} Redis process not running ($node) [fail]"
  fi
done

# Check if Redis port is listening
echo ""
echo "Checking Redis port ($REDIS_PORT)..."
for node in $TEST_NODES; do
  port_check=$(cmd "$node" "ss -tlnp | grep $REDIS_PORT")
  if [[ "$port_check" == *"$REDIS_PORT"* ]]; then
    echo -e "  ${GREEN}✓${NC} Port $REDIS_PORT is listening ($node) [pass]"
  else
    echo -e "  ${RED}✗${NC} Port $REDIS_PORT is not listening ($node) [fail]"
  fi
done

# ============================================================================
# Functional Tests
# ============================================================================

echo ""
echo "Step 4: Running functional tests..."
echo ""

# Test Redis connection and basic operations
for node in $TEST_NODES; do
  echo "Testing Redis operations on $node..."
  
  # Test PING command
  echo "  Testing PING command..."
  ping_result=$(cmd "$node" "redis-cli -p $REDIS_PORT PING")
  if [[ "$ping_result" == *"PONG"* ]]; then
    echo -e "  ${GREEN}✓${NC} PING successful [pass]"
  else
    echo -e "  ${RED}✗${NC} PING failed: $ping_result [fail]"
  fi
  
  # Test SET command
  echo "  Testing SET command..."
  set_result=$(cmd "$node" "redis-cli -p $REDIS_PORT SET testkey 'hello-nix-infra'")
  if [[ "$set_result" == *"OK"* ]]; then
    echo -e "  ${GREEN}✓${NC} SET operation successful [pass]"
  else
    echo -e "  ${RED}✗${NC} SET operation failed: $set_result [fail]"
  fi
  
  # Test GET command
  echo "  Testing GET command..."
  get_result=$(cmd "$node" "redis-cli -p $REDIS_PORT GET testkey")
  if [[ "$get_result" == *"hello-nix-infra"* ]]; then
    echo -e "  ${GREEN}✓${NC} GET operation successful [pass]"
  else
    echo -e "  ${RED}✗${NC} GET operation failed: $get_result [fail]"
  fi
  
  # Test INCR command
  echo "  Testing INCR command..."
  cmd "$node" "redis-cli -p $REDIS_PORT SET counter 0" > /dev/null 2>&1
  incr_result=$(cmd "$node" "redis-cli -p $REDIS_PORT INCR counter")
  if [[ "$incr_result" == *"1"* ]]; then
    echo -e "  ${GREEN}✓${NC} INCR operation successful [pass]"
  else
    echo -e "  ${RED}✗${NC} INCR operation failed: $incr_result [fail]"
  fi
  
  # Test LPUSH/LRANGE (list operations)
  echo "  Testing list operations..."
  cmd "$node" "redis-cli -p $REDIS_PORT LPUSH mylist item1 item2 item3" > /dev/null 2>&1
  list_result=$(cmd "$node" "redis-cli -p $REDIS_PORT LRANGE mylist 0 -1")
  if [[ "$list_result" == *"item"* ]]; then
    echo -e "  ${GREEN}✓${NC} List operations successful [pass]"
  else
    echo -e "  ${RED}✗${NC} List operations failed: $list_result [fail]"
  fi
  
  # Test INFO command
  echo "  Testing INFO command..."
  info_result=$(cmd "$node" "redis-cli -p $REDIS_PORT INFO server | head -5")
  if [[ "$info_result" == *"redis_version"* ]]; then
    echo -e "  ${GREEN}✓${NC} INFO command successful [pass]"
  else
    echo -e "  ${RED}✗${NC} INFO command failed: $info_result [fail]"
  fi
  
  # Clean up test data
  echo "  Cleaning up test data..."
  cmd "$node" "redis-cli -p $REDIS_PORT FLUSHALL" > /dev/null 2>&1
  echo -e "  ${GREEN}✓${NC} Test data cleaned up [pass]"
done

# ============================================================================
# Test Summary
# ============================================================================

_end=$(date +%s)

echo ""
echo "========================================"
echo "Redis Test Summary"
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
echo "Redis Test Complete"
echo "========================================"
