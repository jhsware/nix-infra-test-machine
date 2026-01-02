#!/usr/bin/env bash
# Redis test for nix-infra-machine
#
# This test:
# 1. Deploys multiple Redis servers using infrastructure.redis
# 2. Verifies all services are running
# 3. Tests basic Redis operations on each server
# 4. Cleans up on teardown

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Server configurations: name:port
declare -A REDIS_SERVERS=(
  ["redis"]=6379
  ["redis-cache"]=6380
)

# Handle teardown command
if [ "$CMD" = "teardown" ]; then
  echo "Tearing down Redis test..."
  
  # Stop Redis services
  for server in "${!REDIS_SERVERS[@]}"; do
    $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" \
      "systemctl stop $server 2>/dev/null || true"
  done
  
  # Clean up data directories
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" \
    'rm -rf /var/lib/redis /var/lib/redis-cache'
  
  echo "Redis teardown complete"
  return 0
fi

# ============================================================================
# Test Setup
# ============================================================================

_start=$(date +%s)

echo ""
echo "========================================"
echo "Redis Multi-Server Test"
echo "========================================"
echo ""

# Deploy the redis configuration to test nodes
echo "Step 1: Deploying Redis configuration..."
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
echo "Step 3: Verifying Redis deployment..."
echo ""

# Wait for services to start
echo "Waiting for Redis services to start..."
sleep 5

# Check if the systemd services are active
echo "Checking systemd service status..."
for node in $TARGET; do
  for server in "${!REDIS_SERVERS[@]}"; do
    service_status=$(cmd_value "$node" "systemctl is-active $server")
    if [[ "$service_status" == "active" ]]; then
      echo -e "  ${GREEN}✓${NC} $server: active ($node) [pass]"
    else
      echo -e "  ${RED}✗${NC} $server: $service_status ($node) [fail]"
      echo ""
      echo "Service logs:"
      cmd "$node" "journalctl -n 30 -u $server"
    fi
  done
done

# Check if Redis processes are running
echo ""
echo "Checking Redis processes..."
for node in $TEST_NODES; do
  # Use cmd_value to get clean numeric output
  process_count=$(cmd_value "$node" "pgrep -c redis-server || echo 0")
  expected_count=${#REDIS_SERVERS[@]}
  if [[ "$process_count" -ge "$expected_count" ]]; then
    echo -e "  ${GREEN}✓${NC} $process_count Redis processes running ($node) [pass]"
  else
    echo -e "  ${RED}✗${NC} Expected $expected_count processes, found $process_count ($node) [fail]"
  fi
done



# Check if Redis ports are listening
echo ""
echo "Checking Redis ports..."
for node in $TARGET; do
  for server in "${!REDIS_SERVERS[@]}"; do
    port=${REDIS_SERVERS[$server]}
    port_check=$(cmd "$node" "ss -tlnp | grep :$port")
    if [[ "$port_check" == *":$port"* ]]; then
      echo -e "  ${GREEN}✓${NC} $server port $port is listening ($node) [pass]"
    else
      echo -e "  ${RED}✗${NC} $server port $port is not listening ($node) [fail]"
    fi
  done
done

# ============================================================================
# Functional Tests
# ============================================================================

echo ""
echo "Step 4: Running functional tests..."
echo ""

# Test Redis connection and basic operations on each server
for node in $TARGET; do
  for server in "${!REDIS_SERVERS[@]}"; do
    port=${REDIS_SERVERS[$server]}
    echo "Testing $server (port $port) on $node..."
    
    # Test PING command
    echo "  Testing PING command..."
    ping_result=$(cmd_clean "$node" "redis-cli -p $port PING")
    if [[ "$ping_result" == *"PONG"* ]]; then
      echo -e "  ${GREEN}✓${NC} PING successful [pass]"
    else
      echo -e "  ${RED}✗${NC} PING failed: $ping_result [fail]"
    fi
    
    # Test SET command
    echo "  Testing SET command..."
    set_result=$(cmd_clean "$node" "redis-cli -p $port SET testkey-$server 'hello-from-$server'")
    if [[ "$set_result" == *"OK"* ]]; then
      echo -e "  ${GREEN}✓${NC} SET operation successful [pass]"
    else
      echo -e "  ${RED}✗${NC} SET operation failed: $set_result [fail]"
    fi
    
    # Test GET command
    echo "  Testing GET command..."
    get_result=$(cmd_clean "$node" "redis-cli -p $port GET testkey-$server")
    if [[ "$get_result" == *"hello-from-$server"* ]]; then
      echo -e "  ${GREEN}✓${NC} GET operation successful [pass]"
    else
      echo -e "  ${RED}✗${NC} GET operation failed: $get_result [fail]"
    fi
    
    # Test INCR command
    echo "  Testing INCR command..."
    cmd "$node" "redis-cli -p $port SET counter 0" > /dev/null 2>&1
    incr_result=$(cmd_clean "$node" "redis-cli -p $port INCR counter")
    if [[ "$incr_result" == *"1"* ]]; then
      echo -e "  ${GREEN}✓${NC} INCR operation successful [pass]"
    else
      echo -e "  ${RED}✗${NC} INCR operation failed: $incr_result [fail]"
    fi
    
    # Test INFO command
    echo "  Testing INFO command..."
    info_result=$(cmd_clean "$node" "redis-cli -p $port INFO server | head -5")
    if [[ "$info_result" == *"redis_version"* ]]; then
      echo -e "  ${GREEN}✓${NC} INFO command successful [pass]"
    else
      echo -e "  ${RED}✗${NC} INFO command failed: $info_result [fail]"
    fi
    
    # Clean up test data
    echo "  Cleaning up test data..."
    cmd "$node" "redis-cli -p $port FLUSHALL" > /dev/null 2>&1
    echo -e "  ${GREEN}✓${NC} Test data cleaned up [pass]"
    echo ""
  done
done

# ============================================================================
# Test Server Isolation
# ============================================================================

echo "Step 5: Testing server isolation..."
echo ""

for node in $TARGET; do
  echo "Testing data isolation on $node..."
  
  # Set a key on the default server
  cmd "$node" "redis-cli -p 6379 SET isolation-test 'default-server'" > /dev/null 2>&1
  
  # Try to get it from the cache server (should not exist)
  # Use cmd_value to get clean output without node prefix
  cache_result=$(cmd_value "$node" "redis-cli -p 6380 GET isolation-test")
  if [[ -z "$cache_result" ]] || [[ "$cache_result" == "nil" ]] || [[ "$cache_result" == "(nil)" ]]; then
    echo -e "  ${GREEN}✓${NC} Servers are properly isolated [pass]"
  else
    echo -e "  ${RED}✗${NC} Data leaked between servers: $cache_result [fail]"
  fi

  
  # Clean up
  cmd "$node" "redis-cli -p 6379 FLUSHALL" > /dev/null 2>&1
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
