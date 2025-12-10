#!/usr/bin/env bash
# MongoDB standalone test for nix-infra-machine
#
# This test:
# 1. Deploys MongoDB 4.4 as a podman container
# 2. Verifies the service is running
# 3. Tests basic MongoDB operations (insert/query)
# 4. Cleans up on teardown

# Handle teardown command
if [ "$CMD" = "teardown" ]; then
  echo "Tearing down MongoDB test..."
  
  # Stop and remove container if running
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TEST_NODES" \
    'systemctl stop podman-mongodb-4 2>/dev/null || true'
  
  # Clean up data directory
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TEST_NODES" \
    'rm -rf /var/lib/mongodb-4'
  
  echo "MongoDB teardown complete"
  return 0
fi

# ============================================================================
# Test Setup
# ============================================================================

_start=$(date +%s)

echo ""
echo "========================================"
echo "MongoDB Standalone Test"
echo "========================================"
echo ""

# Deploy the mongodb configuration to test nodes
echo "Step 1: Deploying MongoDB configuration..."
$NIX_INFRA fleet deploy-apps -d "$WORK_DIR" --batch --env="$WORK_DIR/.env" \
  --test-dir="$WORK_DIR/$TEST_DIR" \
  --target="$TEST_NODES" \
  --no-overlay-network

# Apply the configuration
echo "Step 2: Applying NixOS configuration..."
$NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TEST_NODES" "nixos-rebuild switch --fast"

_setup=$(date +%s)

# ============================================================================
# Test Verification
# ============================================================================

echo ""
echo "Step 3: Verifying MongoDB deployment..."
echo ""

# Wait for service to start
echo "Waiting for MongoDB service to start..."
sleep 5

# Check if the systemd service is active
echo "Checking systemd service status..."
for node in $TEST_NODES; do
  service_status=$(cmd "$node" "systemctl is-active podman-mongodb-4")
  if [[ "$service_status" == *"active"* ]]; then
    echo "  ✓ podman-mongodb-4: active ($node)"
  else
    echo "  ✗ podman-mongodb-4: $service_status ($node)"
    echo ""
    echo "Service logs:"
    cmd "$node" "journalctl -n 30 -u podman-mongodb-4"
  fi
done

# Check if container is running
echo ""
echo "Checking container status..."
for node in $TEST_NODES; do
  container_status=$(cmd "$node" "podman ps --filter name=mongodb-4 --format '{{.Names}} {{.Status}}'")
  if [[ "$container_status" == *"mongodb-4"* ]]; then
    echo "  ✓ Container running: $container_status ($node)"
  else
    echo "  ✗ Container not running ($node)"
    echo "All containers:"
    cmd "$node" "podman ps -a"
  fi
done

# Check if MongoDB port is listening
echo ""
echo "Checking MongoDB port (27017)..."
for node in $TEST_NODES; do
  port_check=$(cmd "$node" "ss -tlnp | grep 27017")
  if [[ "$port_check" == *"27017"* ]]; then
    echo "  ✓ Port 27017 is listening ($node)"
  else
    echo "  ✗ Port 27017 is not listening ($node)"
  fi
done

# ============================================================================
# Functional Tests
# ============================================================================

echo ""
echo "Step 4: Running functional tests..."
echo ""

# Test MongoDB connection and basic operations
for node in $TEST_NODES; do
  echo "Testing MongoDB operations on $node..."
  
  # Insert a test document
  echo "  Inserting test document..."
  insert_result=$(cmd "$node" "podman exec mongodb-4 mongosh --quiet --eval 'db.test.insertOne({name: \"test\", value: 42})'")
  if [[ "$insert_result" == *"acknowledged"* ]] || [[ "$insert_result" == *"insertedId"* ]]; then
    echo "  ✓ Insert operation successful"
  else
    echo "  ✗ Insert operation failed: $insert_result"
  fi
  
  # Query the test document
  echo "  Querying test document..."
  query_result=$(cmd "$node" "podman exec mongodb-4 mongosh --quiet --eval 'db.test.findOne({name: \"test\"})'")
  if [[ "$query_result" == *"value"* ]] && [[ "$query_result" == *"42"* ]]; then
    echo "  ✓ Query operation successful"
  else
    echo "  ✗ Query operation failed: $query_result"
  fi
  
  # Test database listing
  echo "  Listing databases..."
  db_list=$(cmd "$node" "podman exec mongodb-4 mongosh --quiet --eval 'db.adminCommand({listDatabases: 1}).databases.map(d => d.name)'")
  if [[ "$db_list" == *"admin"* ]]; then
    echo "  ✓ Database listing successful"
  else
    echo "  ✗ Database listing failed: $db_list"
  fi
  
  # Clean up test data
  echo "  Cleaning up test data..."
  cmd "$node" "podman exec mongodb-4 mongosh --quiet --eval 'db.test.drop()'" > /dev/null 2>&1
  echo "  ✓ Test data cleaned up"
done

# ============================================================================
# Test Summary
# ============================================================================

_end=$(date +%s)

echo ""
echo "========================================"
echo "MongoDB Test Summary"
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
echo "MongoDB Test Complete"
echo "========================================"
