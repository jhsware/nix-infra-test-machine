#!/usr/bin/env bash
# PostgreSQL standalone test for nix-infra-machine
#
# This test:
# 1. Deploys PostgreSQL as a native service
# 2. Verifies the service is running
# 3. Tests basic PostgreSQL operations (create table, insert, query)
# 4. Cleans up on teardown

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Handle teardown command
if [ "$CMD" = "teardown" ]; then
  echo "Tearing down PostgreSQL test..."
  
  # Stop PostgreSQL service
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TEST_NODES" \
    'systemctl stop postgresql 2>/dev/null || true'
  
  # Clean up data directory
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TEST_NODES" \
    'rm -rf /var/lib/postgresql'
  
  echo "PostgreSQL teardown complete"
  return 0
fi

# ============================================================================
# Test Setup
# ============================================================================

_start=$(date +%s)

echo ""
echo "========================================"
echo "PostgreSQL Standalone Test"
echo "========================================"
echo ""

# Deploy the postgres configuration to test nodes
echo "Step 1: Deploying PostgreSQL configuration..."
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
echo "Step 3: Verifying PostgreSQL deployment..."
echo ""

# Wait for service to start
echo "Waiting for PostgreSQL service to start..."
sleep 5

# Check if the systemd service is active
echo "Checking systemd service status..."
for node in $TEST_NODES; do
  service_status=$(cmd "$node" "systemctl is-active postgresql")
  if [[ "$service_status" == *"active"* ]]; then
    echo -e "  ${GREEN}✓${NC} postgresql: active ($node) [pass]"
  else
    echo -e "  ${RED}✗${NC} postgresql: $service_status ($node) [fail]"
    echo ""
    echo "Service logs:"
    cmd "$node" "journalctl -n 30 -u postgresql"
  fi
done

# Check if PostgreSQL process is running
echo ""
echo "Checking PostgreSQL process..."
for node in $TEST_NODES; do
  process_status=$(cmd "$node" "pgrep -a postgres")
  if [[ -n "$process_status" ]]; then
    echo -e "  ${GREEN}✓${NC} PostgreSQL process running ($node) [pass]"
  else
    echo -e "  ${RED}✗${NC} PostgreSQL process not running ($node) [fail]"
  fi
done

# Check if PostgreSQL port is listening
echo ""
echo "Checking PostgreSQL port (5432)..."
for node in $TEST_NODES; do
  port_check=$(cmd "$node" "ss -tlnp | grep 5432")
  if [[ "$port_check" == *"5432"* ]]; then
    echo -e "  ${GREEN}✓${NC} Port 5432 is listening ($node) [pass]"
  else
    echo -e "  ${RED}✗${NC} Port 5432 is not listening ($node) [fail]"
  fi
done

# ============================================================================
# Functional Tests
# ============================================================================

echo ""
echo "Step 4: Running functional tests..."
echo ""

# Test PostgreSQL connection and basic operations
for node in $TEST_NODES; do
  echo "Testing PostgreSQL operations on $node..."
  
  # Test connection
  echo "  Testing connection..."
  conn_result=$(cmd "$node" "sudo -u postgres psql -c 'SELECT 1 as test;' 2>&1")
  if [[ "$conn_result" == *"1"* ]]; then
    echo -e "  ${GREEN}✓${NC} Connection successful [pass]"
  else
    echo -e "  ${RED}✗${NC} Connection failed: $conn_result [fail]"
  fi
  
  # Check if testdb was created
  echo "  Checking testdb database..."
  db_check=$(cmd "$node" "sudo -u postgres psql -l | grep testdb")
  if [[ "$db_check" == *"testdb"* ]]; then
    echo -e "  ${GREEN}✓${NC} Database 'testdb' exists [pass]"
  else
    echo -e "  ${RED}✗${NC} Database 'testdb' not found [fail]"
  fi
  
  # Create a test table
  echo "  Creating test table..."
  create_result=$(cmd "$node" "sudo -u postgres psql -d testdb -c 'CREATE TABLE IF NOT EXISTS test_table (id SERIAL PRIMARY KEY, name VARCHAR(100), value INTEGER);' 2>&1")
  if [[ "$create_result" == *"CREATE TABLE"* ]] || [[ "$create_result" == *"already exists"* ]] || [[ -z "$create_result" ]]; then
    echo -e "  ${GREEN}✓${NC} Create table successful [pass]"
  else
    echo -e "  ${RED}✗${NC} Create table failed: $create_result [fail]"
  fi
  
  # Insert a test record
  echo "  Inserting test record..."
  insert_result=$(cmd "$node" "sudo -u postgres psql -d testdb -c \"INSERT INTO test_table (name, value) VALUES ('test', 42);\" 2>&1")
  if [[ "$insert_result" == *"INSERT"* ]]; then
    echo -e "  ${GREEN}✓${NC} Insert operation successful [pass]"
  else
    echo -e "  ${RED}✗${NC} Insert operation failed: $insert_result [fail]"
  fi
  
  # Query the test record
  echo "  Querying test record..."
  query_result=$(cmd "$node" "sudo -u postgres psql -d testdb -c 'SELECT * FROM test_table WHERE name = '\\''test'\\'';' 2>&1")
  if [[ "$query_result" == *"test"* ]] && [[ "$query_result" == *"42"* ]]; then
    echo -e "  ${GREEN}✓${NC} Query operation successful [pass]"
  else
    echo -e "  ${RED}✗${NC} Query operation failed: $query_result [fail]"
  fi
  
  # Test database listing
  echo "  Listing databases..."
  db_list=$(cmd "$node" "sudo -u postgres psql -c '\\l' 2>&1")
  if [[ "$db_list" == *"postgres"* ]]; then
    echo -e "  ${GREEN}✓${NC} Database listing successful [pass]"
  else
    echo -e "  ${RED}✗${NC} Database listing failed: $db_list [fail]"
  fi
  
  # Clean up test data
  echo "  Cleaning up test data..."
  cmd "$node" "sudo -u postgres psql -d testdb -c 'DROP TABLE IF EXISTS test_table;'" > /dev/null 2>&1
  echo -e "  ${GREEN}✓${NC} Test data cleaned up [pass]"
done

# ============================================================================
# Test Summary
# ============================================================================

_end=$(date +%s)

echo ""
echo "========================================"
echo "PostgreSQL Test Summary"
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
echo "PostgreSQL Test Complete"
echo "========================================"
