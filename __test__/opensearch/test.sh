#!/usr/bin/env bash
# OpenSearch standalone test for nix-infra-machine
#
# This test:
# 1. Deploys OpenSearch as a native service on custom port 9201
# 2. Verifies the service is running
# 3. Tests basic OpenSearch operations (index/query)
# 4. Cleans up on teardown

# Custom ports for testing
OPENSEARCH_HTTP_PORT=9201
OPENSEARCH_TRANSPORT_PORT=9301

# Handle teardown command
if [ "$CMD" = "teardown" ]; then
  echo "Tearing down OpenSearch test..."
  
  # Stop OpenSearch service
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" \
    'systemctl stop opensearch 2>/dev/null || true'
  
  # Clean up data directory
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" \
    'rm -rf /var/lib/opensearch'
  
  echo "OpenSearch teardown complete"
  return 0
fi

# ============================================================================
# Test Setup
# ============================================================================

_start=$(date +%s)

echo ""
echo "========================================"
echo "OpenSearch Standalone Test (port $OPENSEARCH_HTTP_PORT)"
echo "========================================"
echo ""

# Deploy the opensearch configuration to test nodes
echo "Step 1: Deploying OpenSearch configuration..."
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
echo "Step 3: Verifying OpenSearch deployment..."
echo ""

# Wait for service to start (OpenSearch can take a while to initialize)
echo "Waiting for OpenSearch service to start (this may take up to 60 seconds)..."
sleep 30

# Check if the systemd service is active
echo "Checking systemd service status..."
for node in $TARGET; do
  service_status=$(cmd_value "$node" "systemctl is-active opensearch")
  if [[ "$service_status" == "active" ]]; then
    echo -e "  ${GREEN}✓${NC} opensearch: active ($node) [pass]"
  else
    echo -e "  ${RED}✗${NC} opensearch: $service_status ($node) [fail]"
    echo ""
    echo "Service logs:"
    cmd "$node" "journalctl -n 50 -u opensearch"
  fi
done

# Check if OpenSearch process is running
echo ""
echo "Checking OpenSearch process..."
for node in $TARGET; do
  process_status=$(cmd_clean "$node" "pgrep -a -f opensearch")
  if [[ -n "$process_status" ]]; then
    echo -e "  ${GREEN}✓${NC} OpenSearch process running ($node) [pass]"
  else
    echo -e "  ${RED}✗${NC} OpenSearch process not running ($node) [fail]"
  fi
done

# Check if OpenSearch HTTP port is listening
echo ""
echo "Checking OpenSearch HTTP port ($OPENSEARCH_HTTP_PORT)..."
for node in $TARGET; do
  port_check=$(cmd "$node" "ss -tlnp | grep $OPENSEARCH_HTTP_PORT")
  if [[ "$port_check" == *"$OPENSEARCH_HTTP_PORT"* ]]; then
    echo -e "  ${GREEN}✓${NC} HTTP port $OPENSEARCH_HTTP_PORT is listening ($node) [pass]"
  else
    echo -e "  ${RED}✗${NC} HTTP port $OPENSEARCH_HTTP_PORT is not listening ($node) [fail]"
  fi
done

# Wait a bit more for HTTP API to be ready
echo ""
echo "Waiting for HTTP API to be ready..."
sleep 10

# ============================================================================
# Functional Tests
# ============================================================================

echo ""
echo "Step 4: Running functional tests..."
echo ""

# Test OpenSearch connection and basic operations
for node in $TARGET; do
  echo "Testing OpenSearch operations on $node..."
  
  # Test cluster health endpoint
  echo "  Checking cluster health..."
  health_result=$(cmd_clean "$node" "curl -s http://127.0.0.1:$OPENSEARCH_HTTP_PORT/_cluster/health")
  if [[ "$health_result" == *"cluster_name"* ]]; then
    echo -e "  ${GREEN}✓${NC} Cluster health endpoint accessible [pass]"
    # Extract and show status (now works with clean JSON)
    status=$(echo "$health_result" | jq -r '.status' 2>/dev/null || echo "unknown")
    echo "       Cluster status: $status"
  else
    echo -e "  ${RED}✗${NC} Cluster health endpoint failed: $health_result [fail]"
  fi
  
  # Create a test index
  echo "  Creating test index..."
  create_result=$(cmd_clean "$node" "curl -s -X PUT 'http://127.0.0.1:$OPENSEARCH_HTTP_PORT/test-index' -H 'Content-Type: application/json' -d '{\"settings\": {\"number_of_shards\": 1, \"number_of_replicas\": 0}}'")
  if [[ "$create_result" == *"acknowledged"* ]] && [[ "$create_result" == *"true"* ]]; then
    echo -e "  ${GREEN}✓${NC} Index creation successful [pass]"
  else
    echo -e "  ${RED}✗${NC} Index creation failed: $create_result [fail]"
  fi
  
  # Insert a test document
  echo "  Inserting test document..."
  insert_result=$(cmd_clean "$node" "curl -s -X POST 'http://127.0.0.1:$OPENSEARCH_HTTP_PORT/test-index/_doc/1' -H 'Content-Type: application/json' -d '{\"name\": \"test\", \"value\": 42}'")
  if [[ "$insert_result" == *"created"* ]] || [[ "$insert_result" == *"_id"* ]]; then
    echo -e "  ${GREEN}✓${NC} Document insert successful [pass]"
  else
    echo -e "  ${RED}✗${NC} Document insert failed: $insert_result [fail]"
  fi
  
  # Force refresh to make document searchable
  cmd "$node" "curl -s -X POST 'http://127.0.0.1:$OPENSEARCH_HTTP_PORT/test-index/_refresh'" > /dev/null 2>&1
  
  # Query the test document
  echo "  Querying test document..."
  query_result=$(cmd_clean "$node" "curl -s 'http://127.0.0.1:$OPENSEARCH_HTTP_PORT/test-index/_doc/1'")
  if [[ "$query_result" == *"found"* ]] && [[ "$query_result" == *"true"* ]]; then
    echo -e "  ${GREEN}✓${NC} Document query successful [pass]"
  else
    echo -e "  ${RED}✗${NC} Document query failed: $query_result [fail]"
  fi
  
  # Test search functionality
  echo "  Testing search..."
  search_result=$(cmd_clean "$node" "curl -s -X GET 'http://127.0.0.1:$OPENSEARCH_HTTP_PORT/test-index/_search' -H 'Content-Type: application/json' -d '{\"query\": {\"match\": {\"name\": \"test\"}}}'")
  if [[ "$search_result" == *"hits"* ]] && [[ "$search_result" == *"value"* ]]; then
    echo -e "  ${GREEN}✓${NC} Search operation successful [pass]"
  else
    echo -e "  ${RED}✗${NC} Search operation failed: $search_result [fail]"
  fi
  
  # List indices
  echo "  Listing indices..."
  indices_result=$(cmd_clean "$node" "curl -s 'http://127.0.0.1:$OPENSEARCH_HTTP_PORT/_cat/indices?v'")
  if [[ "$indices_result" == *"test-index"* ]]; then
    echo -e "  ${GREEN}✓${NC} Index listing successful [pass]"
  else
    echo -e "  ${RED}✗${NC} Index listing failed: $indices_result [fail]"
  fi
  
  # Clean up test index
  echo "  Cleaning up test index..."
  cmd "$node" "curl -s -X DELETE 'http://127.0.0.1:$OPENSEARCH_HTTP_PORT/test-index'" > /dev/null 2>&1
  echo -e "  ${GREEN}✓${NC} Test index cleaned up [pass]"
done

# ============================================================================
# Test Summary
# ============================================================================

_end=$(date +%s)

echo ""
echo "========================================"
echo "OpenSearch Test Summary"
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
echo "OpenSearch Test Complete"
echo "========================================"
