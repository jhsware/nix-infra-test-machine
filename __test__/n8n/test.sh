#!/usr/bin/env bash
# n8n test for nix-infra-machine
#
# This test:
# 1. Deploys n8n with SQLite backend
# 2. Verifies all services are running
# 3. Tests n8n endpoints and REST API functionality
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
    
  # Clean up entire n8n data directory including SQLite database
  echo "  Removing n8n data directory..."
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" \
    'rm -rf /var/lib/n8n'
  
  # Clean up temporary cookie file used in tests
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" \
    'rm -f /tmp/n8n-cookies.txt 2>/dev/null || true'
    
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
    echo -e "  ${YELLOW}!${NC} n8n healthcheck response: $healthcheck [fail]"
  fi
  
  # ============================================================================
  # Authenticated REST API Tests (using session cookie)
  # ============================================================================
  echo "  Setting up authentication for API testing..."
  
  # Create authentication test script using base64 to avoid escaping issues
  AUTH_SCRIPT='#!/usr/bin/env bash

# Step 1: Create owner user (will fail if already exists, which is fine)
curl -s -X POST http://localhost:5678/rest/owner/setup \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"test@example.com\",\"firstName\":\"Test\",\"lastName\":\"User\",\"password\":\"TestPassword123!\"}" > /tmp/n8n-owner-result.json 2>&1

# Step 2: Login and get session cookie
curl -s -c /tmp/n8n-cookies.txt -X POST http://localhost:5678/rest/login \
  -H "Content-Type: application/json" \
  -d "{\"emailOrLdapLoginId\":\"test@example.com\",\"password\":\"TestPassword123!\"}" > /tmp/n8n-login-result.json 2>&1

# Check login result
if grep -q "test@example.com" /tmp/n8n-login-result.json 2>/dev/null; then
  echo "LOGIN_SUCCESS"
  
  # Step 3: Test REST API with session cookie (list workflows)
  WORKFLOWS_RESPONSE=$(curl -s -b /tmp/n8n-cookies.txt http://localhost:5678/rest/workflows 2>&1)
  
  if echo "$WORKFLOWS_RESPONSE" | jq -e ".data" > /dev/null 2>&1; then
    WORKFLOW_COUNT=$(echo "$WORKFLOWS_RESPONSE" | jq -r ".data | length")
    echo "REST_API_SUCCESS:workflows=$WORKFLOW_COUNT"
  else
    echo "REST_API_FAILED:$WORKFLOWS_RESPONSE"
  fi
  
  # Step 4: Test creating a workflow via REST API
  CREATE_WORKFLOW_RESPONSE=$(curl -s -b /tmp/n8n-cookies.txt -X POST http://localhost:5678/rest/workflows \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"Test Workflow\",\"nodes\":[],\"connections\":{},\"settings\":{},\"active\":false}" 2>&1)
  
  if echo "$CREATE_WORKFLOW_RESPONSE" | jq -e ".data.id" > /dev/null 2>&1; then
    WORKFLOW_ID=$(echo "$CREATE_WORKFLOW_RESPONSE" | jq -r ".data.id")
    echo "WORKFLOW_CREATED:$WORKFLOW_ID"
    
    # Step 5: Delete the test workflow
    DELETE_RESPONSE=$(curl -s -b /tmp/n8n-cookies.txt -X DELETE "http://localhost:5678/rest/workflows/$WORKFLOW_ID" 2>&1)
    if echo "$DELETE_RESPONSE" | jq -e ".data" > /dev/null 2>&1; then
      echo "WORKFLOW_DELETED"
    else
      echo "WORKFLOW_DELETE_FAILED:$DELETE_RESPONSE"
    fi
  else
    echo "WORKFLOW_CREATE_FAILED:$CREATE_WORKFLOW_RESPONSE"
  fi
  
else
  echo "LOGIN_FAILED:$(cat /tmp/n8n-login-result.json)"
fi

# Cleanup
rm -f /tmp/n8n-owner-result.json /tmp/n8n-login-result.json /tmp/n8n-cookies.txt
'

  # Encode script and send to remote node
  AUTH_SCRIPT_B64=$(echo "$AUTH_SCRIPT" | base64 -w0)
  cmd "$node" "echo '$AUTH_SCRIPT_B64' | base64 -d > /tmp/n8n-auth-test.sh && chmod +x /tmp/n8n-auth-test.sh"
  
  # Run the auth test script
  auth_result=$(cmd "$node" "bash /tmp/n8n-auth-test.sh")
  cmd "$node" "rm -f /tmp/n8n-auth-test.sh"
  
  # Parse results
  if [[ "$auth_result" == *"LOGIN_SUCCESS"* ]]; then
    echo -e "  ${GREEN}✓${NC} Login successful [pass]"
    
    # Check REST API access with session cookie
    if [[ "$auth_result" == *"REST_API_SUCCESS:"* ]]; then
      rest_info=$(echo "$auth_result" | grep "REST_API_SUCCESS:" | sed 's/.*REST_API_SUCCESS://')
      echo -e "  ${GREEN}✓${NC} REST API accessible ($rest_info) [pass]"
    elif [[ "$auth_result" == *"REST_API_FAILED:"* ]]; then
      rest_error=$(echo "$auth_result" | grep "REST_API_FAILED:" | sed 's/.*REST_API_FAILED://')
      echo -e "  ${RED}✗${NC} REST API failed: ${rest_error:0:100} [fail]"
    fi
    
    # Check workflow CRUD operations
    if [[ "$auth_result" == *"WORKFLOW_CREATED:"* ]]; then
      workflow_id=$(echo "$auth_result" | grep "WORKFLOW_CREATED:" | sed 's/.*WORKFLOW_CREATED://')
      echo -e "  ${GREEN}✓${NC} Workflow created (id: $workflow_id) [pass]"
      
      if [[ "$auth_result" == *"WORKFLOW_DELETED"* ]]; then
        echo -e "  ${GREEN}✓${NC} Workflow deleted [pass]"
      elif [[ "$auth_result" == *"WORKFLOW_DELETE_FAILED:"* ]]; then
        delete_error=$(echo "$auth_result" | grep "WORKFLOW_DELETE_FAILED:" | sed 's/.*WORKFLOW_DELETE_FAILED://')
        echo -e "  ${RED}✗${NC} Workflow delete failed: ${delete_error:0:100} [fail]"
      fi
    elif [[ "$auth_result" == *"WORKFLOW_CREATE_FAILED:"* ]]; then
      create_error=$(echo "$auth_result" | grep "WORKFLOW_CREATE_FAILED:" | sed 's/.*WORKFLOW_CREATE_FAILED://')
      echo -e "  ${RED}✗${NC} Workflow create failed: ${create_error:0:100} [fail]"
    fi
    
  else
    login_error=$(echo "$auth_result" | grep "LOGIN_FAILED:" | sed 's/.*LOGIN_FAILED://')
    echo -e "  ${RED}✗${NC} Login failed: ${login_error:0:100} [fail]"
  fi

  # Check n8n data directory exists
  echo "  Testing n8n data directory..."
  data_exists=$(cmd "$node" "test -d /var/lib/n8n && echo 'exists' || echo 'missing'")
  if [[ "$data_exists" == *"exists"* ]]; then
    echo -e "  ${GREEN}✓${NC} n8n data directory exists [pass]"
  else
    echo -e "  ${RED}✗${NC} n8n data directory not found [fail]"
  fi
  
  # Check SQLite database file exists
  echo "  Testing SQLite database file..."
  sqlite_exists=$(cmd "$node" "test -f /var/lib/n8n/.n8n/database.sqlite && echo 'exists' || echo 'missing'")
  if [[ "$sqlite_exists" == *"exists"* ]]; then
    echo -e "  ${GREEN}✓${NC} SQLite database file exists [pass]"
  else
    echo -e "  ${RED}✗${NC} SQLite database file not found [fail]"
  fi
  
  # Check service is not in error state (handle node-prefixed output)
  echo "  Checking service state..."
  service_state=$(cmd "$node" "systemctl show -p SubState n8n --value")
  if [[ "$service_state" == *"running"* ]]; then
    echo -e "  ${GREEN}✓${NC} Service is running normally [pass]"
  else
    echo -e "  ${RED}✗${NC} Service state: $service_state [fail]"
  fi
  
  # Check for any failed units related to n8n
  echo "  Checking for failed units..."
  failed_units=$(cmd "$node" "systemctl list-units --failed | grep -i n8n || echo 'none'")
  if [[ "$failed_units" == *"none"* ]] || [[ -z "$failed_units" ]] || [[ ! "$failed_units" == *"failed"* ]]; then
    echo -e "  ${GREEN}✓${NC} No failed n8n related units [pass]"
  else
    echo -e "  ${RED}✗${NC} Failed units found: $failed_units [fail]"
  fi
  
  # Check n8n process is running
  echo "  Checking n8n process..."
  n8n_process=$(cmd "$node" "pgrep -f 'n8n' | head -1 || echo 'not_found'")
  if [[ "$n8n_process" != *"not_found"* ]] && [[ -n "$n8n_process" ]] && [[ "$n8n_process" =~ [0-9] ]]; then
    echo -e "  ${GREEN}✓${NC} n8n process is running [pass]"
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
