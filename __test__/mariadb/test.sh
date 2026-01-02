#!/usr/bin/env bash
# MariaDB standalone test for nix-infra-machine
#
# This test:
# 1. Deploys MariaDB as a native service
# 2. Verifies the service is running
# 3. Tests basic MariaDB operations (create table, insert, query)
# 4. Cleans up on teardown

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# MariaDB port
MARIADB_PORT=3306

# Handle teardown command
if [ "$CMD" = "teardown" ]; then
  echo "Tearing down MariaDB test..."
  
  # Stop MariaDB service
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" \
    'systemctl stop mysql 2>/dev/null || true'
  
  # Clean up data directory
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" \
    'rm -rf /var/lib/mysql'
  
  echo "MariaDB teardown complete"
  return 0
fi

# ============================================================================
# Test Setup
# ============================================================================

_start=$(date +%s)

echo ""
echo "========================================"
echo "MariaDB Standalone Test (port $MARIADB_PORT)"
echo "========================================"
echo ""

# Deploy the mariadb configuration to test nodes
echo "Step 1: Deploying MariaDB configuration..."
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
echo "Step 3: Verifying MariaDB deployment..."
echo ""

# Wait for service to start
echo "Waiting for MariaDB service to start..."
sleep 5

# Check if the systemd service is active
echo "Checking systemd service status..."
for node in $TARGET; do
  service_status=$(cmd "$node" "systemctl is-active mysql")
  if [[ "$service_status" == *"active"* ]]; then
    echo -e "  ${GREEN}✓${NC} mysql: active ($node) [pass]"
  else
    echo -e "  ${RED}✗${NC} mysql: $service_status ($node) [fail]"
    echo ""
    echo "Service logs:"
    cmd "$node" "journalctl -n 30 -u mysql"
  fi
done

# Check if MariaDB process is running
echo ""
echo "Checking MariaDB process..."
for node in $TARGET; do
  process_status=$(cmd "$node" "pgrep -a mariadbd || pgrep -a mysqld")
  if [[ -n "$process_status" ]]; then
    echo -e "  ${GREEN}✓${NC} MariaDB process running ($node) [pass]"
  else
    echo -e "  ${RED}✗${NC} MariaDB process not running ($node) [fail]"
  fi
done

# Check if MariaDB port is listening
echo ""
echo "Checking MariaDB port ($MARIADB_PORT)..."
for node in $TARGET; do
  port_check=$(cmd "$node" "ss -tlnp | grep $MARIADB_PORT")
  if [[ "$port_check" == *"$MARIADB_PORT"* ]]; then
    echo -e "  ${GREEN}✓${NC} Port $MARIADB_PORT is listening ($node) [pass]"
  else
    echo -e "  ${RED}✗${NC} Port $MARIADB_PORT is not listening ($node) [fail]"
  fi
done

# ============================================================================
# Functional Tests
# ============================================================================

echo ""
echo "Step 4: Running functional tests..."
echo ""

# Test MariaDB connection and basic operations
for node in $TARGET; do
  echo "Testing MariaDB operations on $node..."
  
  # Test connection
  echo "  Testing connection..."
  conn_result=$(cmd "$node" "mysql -u root -e 'SELECT 1 as test;' 2>&1")
  if [[ "$conn_result" == *"1"* ]]; then
    echo -e "  ${GREEN}✓${NC} Connection successful [pass]"
  else
    echo -e "  ${RED}✗${NC} Connection failed: $conn_result [fail]"
  fi
  
  # Check if testdb was created
  echo "  Checking testdb database..."
  db_check=$(cmd "$node" "mysql -u root -e 'SHOW DATABASES;' | grep testdb")
  if [[ "$db_check" == *"testdb"* ]]; then
    echo -e "  ${GREEN}✓${NC} Database 'testdb' exists [pass]"
  else
    echo -e "  ${RED}✗${NC} Database 'testdb' not found [fail]"
  fi
  
  # Create a test table
  echo "  Creating test table..."
  create_result=$(cmd "$node" "mysql -u root -D testdb -e 'CREATE TABLE IF NOT EXISTS test_table (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(100), value INT);' 2>&1")
  if [[ "$create_result" != *"ERROR"* ]]; then
    echo -e "  ${GREEN}✓${NC} Create table successful [pass]"
  else
    echo -e "  ${RED}✗${NC} Create table failed: $create_result [fail]"
  fi
  
  # Insert a test record
  echo "  Inserting test record..."
  insert_result=$(cmd "$node" "mysql -u root -D testdb -e \"INSERT INTO test_table (name, value) VALUES ('test', 42);\" 2>&1")
  if [[ "$insert_result" != *"ERROR"* ]]; then
    echo -e "  ${GREEN}✓${NC} Insert operation successful [pass]"
  else
    echo -e "  ${RED}✗${NC} Insert operation failed: $insert_result [fail]"
  fi

  
  # Query the test record
  echo "  Querying test record..."
  query_result=$(cmd "$node" "mysql -u root -D testdb -e \"SELECT * FROM test_table WHERE name = 'test';\" 2>&1")
  if [[ "$query_result" == *"test"* ]] && [[ "$query_result" == *"42"* ]]; then
    echo -e "  ${GREEN}✓${NC} Query operation successful [pass]"
  else
    echo -e "  ${RED}✗${NC} Query operation failed: $query_result [fail]"
  fi
  
  # Test database listing
  echo "  Listing databases..."
  db_list=$(cmd "$node" "mysql -u root -e 'SHOW DATABASES;' 2>&1")
  if [[ "$db_list" == *"mysql"* ]] && [[ "$db_list" == *"information_schema"* ]]; then
    echo -e "  ${GREEN}✓${NC} Database listing successful [pass]"
  else
    echo -e "  ${RED}✗${NC} Database listing failed: $db_list [fail]"
  fi
  
  # Test user was created
  echo "  Checking testuser exists..."
  user_check=$(cmd "$node" "mysql -u root -e \"SELECT User FROM mysql.user WHERE User='testuser';\" 2>&1")
  if [[ "$user_check" == *"testuser"* ]]; then
    echo -e "  ${GREEN}✓${NC} User 'testuser' exists [pass]"
  else
    echo -e "  ${RED}✗${NC} User 'testuser' not found: $user_check [fail]"
  fi
  
  # Clean up test data
  echo "  Cleaning up test data..."
  cmd "$node" "mysql -u root -D testdb -e 'DROP TABLE IF EXISTS test_table;'" > /dev/null 2>&1
  echo -e "  ${GREEN}✓${NC} Test data cleaned up [pass]"
done

# ============================================================================
# Test Summary
# ============================================================================

_end=$(date +%s)

echo ""
echo "========================================"
echo "MariaDB Test Summary"
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
echo "MariaDB Test Complete"
echo "========================================"
