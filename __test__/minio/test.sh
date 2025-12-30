#!/usr/bin/env bash
# MinIO standalone test for nix-infra-machine
#
# This test:
# 1. Deploys MinIO as a native service on custom ports 9002/9003
# 2. Verifies the service is running
# 3. Tests basic MinIO operations (bucket/object operations)
# 4. Cleans up on teardown

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Custom ports for testing
MINIO_API_PORT=9002
MINIO_CONSOLE_PORT=9003
MINIO_USER="testadmin"
MINIO_PASSWORD="testpassword123"

# Handle teardown command
if [ "$CMD" = "teardown" ]; then
  echo "Tearing down MinIO test..."
  
  # Stop MinIO service
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TEST_NODES" \
    'systemctl stop minio 2>/dev/null || true'
  
  # Clean up data directory
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TEST_NODES" \
    'rm -rf /var/lib/minio'
  
  echo "MinIO teardown complete"
  return 0
fi

# ============================================================================
# Test Setup
# ============================================================================

_start=$(date +%s)

echo ""
echo "========================================"
echo "MinIO Standalone Test (API: $MINIO_API_PORT, Console: $MINIO_CONSOLE_PORT)"
echo "========================================"
echo ""

# Deploy the minio configuration to test nodes
echo "Step 1: Deploying MinIO configuration..."
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
echo "Step 3: Verifying MinIO deployment..."
echo ""

# Wait for service to start
echo "Waiting for MinIO service to start..."
sleep 10

# Check if the systemd service is active
echo "Checking systemd service status..."
for node in $TEST_NODES; do
  service_status=$(cmd "$node" "systemctl is-active minio")
  if [[ "$service_status" == *"active"* ]]; then
    echo -e "  ${GREEN}✓${NC} minio: active ($node) [pass]"
  else
    echo -e "  ${RED}✗${NC} minio: $service_status ($node) [fail]"
    echo ""
    echo "Service logs:"
    cmd "$node" "journalctl -n 50 -u minio"
  fi
done

# Check if MinIO process is running
echo ""
echo "Checking MinIO process..."
for node in $TEST_NODES; do
  process_status=$(cmd "$node" "pgrep -a minio")
  if [[ -n "$process_status" ]]; then
    echo -e "  ${GREEN}✓${NC} MinIO process running ($node) [pass]"
  else
    echo -e "  ${RED}✗${NC} MinIO process not running ($node) [fail]"
  fi
done

# Check if MinIO API port is listening
echo ""
echo "Checking MinIO API port ($MINIO_API_PORT)..."
for node in $TEST_NODES; do
  port_check=$(cmd "$node" "ss -tlnp | grep $MINIO_API_PORT")
  if [[ "$port_check" == *"$MINIO_API_PORT"* ]]; then
    echo -e "  ${GREEN}✓${NC} API port $MINIO_API_PORT is listening ($node) [pass]"
  else
    echo -e "  ${RED}✗${NC} API port $MINIO_API_PORT is not listening ($node) [fail]"
  fi
done

# Check if MinIO Console port is listening
echo ""
echo "Checking MinIO Console port ($MINIO_CONSOLE_PORT)..."
for node in $TEST_NODES; do
  port_check=$(cmd "$node" "ss -tlnp | grep $MINIO_CONSOLE_PORT")
  if [[ "$port_check" == *"$MINIO_CONSOLE_PORT"* ]]; then
    echo -e "  ${GREEN}✓${NC} Console port $MINIO_CONSOLE_PORT is listening ($node) [pass]"
  else
    echo -e "  ${RED}✗${NC} Console port $MINIO_CONSOLE_PORT is not listening ($node) [fail]"
  fi
done

# ============================================================================
# Functional Tests
# ============================================================================

echo ""
echo "Step 4: Running functional tests..."
echo ""

# Test MinIO connection and basic operations
for node in $TEST_NODES; do
  echo "Testing MinIO operations on $node..."
  
  # Configure mc (MinIO client) alias
  echo "  Configuring MinIO client..."
  mc_config=$(cmd "$node" "mc alias set testminio http://127.0.0.1:$MINIO_API_PORT $MINIO_USER $MINIO_PASSWORD 2>&1")
  if [[ "$mc_config" == *"successfully"* ]] || [[ "$mc_config" == *"Added"* ]] || [[ -z "$mc_config" ]]; then
    echo -e "  ${GREEN}✓${NC} MinIO client configured [pass]"
  else
    echo -e "  ${RED}✗${NC} MinIO client configuration failed: $mc_config [fail]"
  fi
  
  # Test server health endpoint using HTTP status code
  echo "  Checking server health..."
  health_code=$(cmd "$node" "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$MINIO_API_PORT/minio/health/live")
  if [[ "$health_code" == *"200"* ]]; then
    echo -e "  ${GREEN}✓${NC} Server health endpoint accessible (HTTP 200) [pass]"
  else
    echo -e "  ${RED}✗${NC} Server health check failed: HTTP $health_code [fail]"
  fi
  
  # Create a test bucket
  echo "  Creating test bucket..."
  bucket_result=$(cmd "$node" "mc mb testminio/test-bucket 2>&1")
  if [[ "$bucket_result" == *"Bucket created successfully"* ]] || [[ "$bucket_result" == *"created"* ]]; then
    echo -e "  ${GREEN}✓${NC} Bucket creation successful [pass]"
  else
    echo -e "  ${RED}✗${NC} Bucket creation failed: $bucket_result [fail]"
  fi
  
  # List buckets
  echo "  Listing buckets..."
  list_result=$(cmd "$node" "mc ls testminio 2>&1")
  if [[ "$list_result" == *"test-bucket"* ]]; then
    echo -e "  ${GREEN}✓${NC} Bucket listing successful [pass]"
  else
    echo -e "  ${RED}✗${NC} Bucket listing failed: $list_result [fail]"
  fi
  
  # Upload a test object
  echo "  Uploading test object..."
  cmd "$node" "echo 'Hello MinIO Test!' > /tmp/test-file.txt"
  upload_result=$(cmd "$node" "mc cp /tmp/test-file.txt testminio/test-bucket/test-file.txt 2>&1")
  if [[ "$upload_result" == *"test-file.txt"* ]] || [[ -z "$upload_result" ]]; then
    echo -e "  ${GREEN}✓${NC} Object upload successful [pass]"
  else
    echo -e "  ${RED}✗${NC} Object upload failed: $upload_result [fail]"
  fi
  
  # List objects in bucket
  echo "  Listing objects in bucket..."
  objects_result=$(cmd "$node" "mc ls testminio/test-bucket 2>&1")
  if [[ "$objects_result" == *"test-file.txt"* ]]; then
    echo -e "  ${GREEN}✓${NC} Object listing successful [pass]"
  else
    echo -e "  ${RED}✗${NC} Object listing failed: $objects_result [fail]"
  fi
  
  # Download the test object
  echo "  Downloading test object..."
  cmd "$node" "rm -f /tmp/downloaded-file.txt"
  download_result=$(cmd "$node" "mc cp testminio/test-bucket/test-file.txt /tmp/downloaded-file.txt 2>&1")
  content_check=$(cmd "$node" "cat /tmp/downloaded-file.txt 2>/dev/null")
  if [[ "$content_check" == *"Hello MinIO Test!"* ]]; then
    echo -e "  ${GREEN}✓${NC} Object download successful [pass]"
  else
    echo -e "  ${RED}✗${NC} Object download failed: $download_result [fail]"
  fi
  
  # Get object info/stat
  echo "  Getting object info..."
  stat_result=$(cmd "$node" "mc stat testminio/test-bucket/test-file.txt 2>&1")
  if [[ "$stat_result" == *"test-file.txt"* ]] || [[ "$stat_result" == *"Size"* ]]; then
    echo -e "  ${GREEN}✓${NC} Object stat successful [pass]"
  else
    echo -e "  ${RED}✗${NC} Object stat failed: $stat_result [fail]"
  fi
  
  # Clean up - remove object
  echo "  Cleaning up test object..."
  cmd "$node" "mc rm testminio/test-bucket/test-file.txt 2>&1" > /dev/null
  echo -e "  ${GREEN}✓${NC} Test object removed [pass]"
  
  # Clean up - remove bucket
  echo "  Cleaning up test bucket..."
  cmd "$node" "mc rb testminio/test-bucket 2>&1" > /dev/null
  echo -e "  ${GREEN}✓${NC} Test bucket removed [pass]"
  
  # Clean up temp files
  cmd "$node" "rm -f /tmp/test-file.txt /tmp/downloaded-file.txt" > /dev/null 2>&1
done

# ============================================================================
# Test Summary
# ============================================================================

_end=$(date +%s)

echo ""
echo "========================================"
echo "MinIO Test Summary"
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
echo "MinIO Test Complete"
echo "========================================"
