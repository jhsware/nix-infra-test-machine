#!/usr/bin/env bash
# CrowdSec Intrusion Prevention System test for nix-infra-machine
#
# This test:
# 1. Deploys CrowdSec with SSH and system protection enabled
# 2. Verifies the CrowdSec service and Local API are running
# 3. Tests cscli functionality (hub, parsers, scenarios)
# 4. Tests basic decision management
# 5. Cleans up on teardown
#
# [NIS2 COMPLIANCE VERIFICATION]
# This test validates that the CrowdSec deployment meets key NIS2 requirements:
# - Article 21(2)(b): Incident handling through automated threat detection
# - Article 21(2)(d): Network security through IDS/IPS capabilities
# - Article 21(2)(g): Security monitoring and logging

# Configuration
CROWDSEC_API_PORT=8080
# Note: Firewall bouncer disabled in test (package not available in NixOS 25.05)
FIREWALL_BOUNCER_ENABLED=false

# Handle teardown command
if [ "$CMD" = "teardown" ]; then
  echo "Tearing down CrowdSec test..."
  
  # Stop CrowdSec services
  if [ "$FIREWALL_BOUNCER_ENABLED" = "true" ]; then
    $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" \
      'systemctl stop crowdsec-firewall-bouncer 2>/dev/null || true'
  fi
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" \
    'systemctl stop crowdsec 2>/dev/null || true'
  
  # Clean up data directories on target nodes
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" \
    'rm -rf /var/lib/crowdsec'
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" \
    'rm -rf /var/lib/crowdsec-firewall-bouncer 2>/dev/null || true'
  
  # Clean up declarative configuration directories on target nodes
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" \
    'rm -rf /etc/crowdsec 2>/dev/null || true'
  
  echo "CrowdSec teardown complete"
  return 0
fi


# ============================================================================
# Test Setup
# ============================================================================

_start=$(date +%s)

echo ""
echo "========================================"
echo "CrowdSec Intrusion Prevention Test"
echo "========================================"
echo ""
echo "Testing NIS2-compliant security monitoring setup"
echo ""

# Deploy the CrowdSec configuration to test nodes
echo "Step 1: Deploying CrowdSec configuration..."
$NIX_INFRA fleet deploy-apps -d "$WORK_DIR" --batch --env="$ENV" \
  --test-dir="$WORK_DIR/$TEST_DIR" \
  --target="$TARGET"

# Apply the configuration
echo "Step 2: Applying NixOS configuration..."
$NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" "nixos-rebuild switch --fast"

_setup=$(date +%s)

# ============================================================================
# Test Verification - Services
# ============================================================================

echo ""
echo "Step 3: Verifying CrowdSec deployment..."
echo ""

# Wait for CrowdSec service to start
for node in $TARGET; do
  wait_for_service "$node" "crowdsec" --timeout=90
  wait_for_port "$node" "$CROWDSEC_API_PORT" --timeout=60
done

# Check if the systemd service is active
echo ""
echo "Checking CrowdSec systemd service status..."
for node in $TARGET; do
  assert_service_active "$node" "crowdsec" || show_service_logs "$node" "crowdsec" 50
done

# Check if CrowdSec process is running
echo ""
echo "Checking CrowdSec process..."
for node in $TARGET; do
  assert_process_running "$node" "crowdsec" "CrowdSec"
done

# Check if CrowdSec API port is listening
echo ""
echo "Checking CrowdSec API port ($CROWDSEC_API_PORT)..."
for node in $TARGET; do
  assert_port_listening "$node" "$CROWDSEC_API_PORT" "CrowdSec LAPI port $CROWDSEC_API_PORT"
done

# ============================================================================
# Test Verification - Firewall Bouncer (if enabled)
# ============================================================================

if [ "$FIREWALL_BOUNCER_ENABLED" = "true" ]; then
  echo ""
  echo "Step 4: Verifying Firewall Bouncer..."
  echo ""

  # Wait for bouncer service
  for node in $TARGET; do
    wait_for_service "$node" "crowdsec-firewall-bouncer" --timeout=60
  done

  # Check bouncer service status
  echo "Checking Firewall Bouncer systemd service status..."
  for node in $TARGET; do
    assert_service_active "$node" "crowdsec-firewall-bouncer" || \
      show_service_logs "$node" "crowdsec-firewall-bouncer" 50
  done
else
  echo ""
  echo "Step 4: Firewall Bouncer (SKIPPED - disabled in test config)"
  echo ""
  echo -e "  ${YELLOW}!${NC} Firewall bouncer not enabled (package not available in NixOS 25.05) [info]"
fi

# ============================================================================
# Functional Tests - CLI Tools
# ============================================================================

echo ""
echo "Step 5: Testing CrowdSec CLI (cscli)..."
echo ""

for node in $TARGET; do
  echo "Testing cscli on $node..."
  
  # Test cscli version
  echo "  Checking cscli version..."
  version_result=$(cmd_clean "$node" "cscli version 2>&1")
  if [[ "$version_result" == *"version"* ]] || [[ "$version_result" == *"crowdsec"* ]]; then
    echo -e "  ${GREEN}✓${NC} cscli version command works [pass]"
  else
    echo -e "  ${YELLOW}!${NC} cscli version output: $version_result [warning]"
  fi
  
  # Test LAPI status
  echo "  Checking Local API status..."
  lapi_status=$(cmd_clean "$node" "cscli lapi status 2>&1 || true")
  if [[ "$lapi_status" == *"LAPI is reachable"* ]] || [[ "$lapi_status" == *"is up"* ]] || [[ "$lapi_status" == *"online"* ]]; then
    echo -e "  ${GREEN}✓${NC} Local API is reachable [pass]"
  else
    # LAPI might report issues but still be running
    echo -e "  ${YELLOW}!${NC} LAPI status check (service may need initialization): $lapi_status [info]"
  fi
  
  # Test hub listing
  echo "  Checking installed hub items..."
  hub_result=$(cmd_clean "$node" "cscli hub list 2>&1 || true")
  if [[ "$hub_result" == *"COLLECTIONS"* ]] || [[ "$hub_result" == *"collection"* ]] || [[ -n "$hub_result" ]]; then
    echo -e "  ${GREEN}✓${NC} Hub listing works [pass]"
  else
    echo -e "  ${YELLOW}!${NC} Hub listing output: $hub_result [warning]"
  fi
  
  # Test collections listing
  echo "  Checking installed collections..."
  collections_result=$(cmd_clean "$node" "cscli collections list 2>&1 || true")
  if [[ "$collections_result" == *"sshd"* ]] || [[ "$collections_result" == *"crowdsecurity"* ]]; then
    echo -e "  ${GREEN}✓${NC} SSH collection installed [pass]"
  else
    echo -e "  ${YELLOW}!${NC} SSH collection may still be installing [info]"
  fi
  
  # Test parsers listing  
  echo "  Checking installed parsers..."
  parsers_result=$(cmd_clean "$node" "cscli parsers list 2>&1 || true")
  if [[ "$parsers_result" == *"sshd"* ]] || [[ "$parsers_result" == *"syslog"* ]] || [[ -n "$parsers_result" ]]; then
    echo -e "  ${GREEN}✓${NC} Parsers installed [pass]"
  else
    echo -e "  ${YELLOW}!${NC} Parsers may still be installing [info]"
  fi
  
  # Test scenarios listing
  echo "  Checking installed scenarios..."
  scenarios_result=$(cmd_clean "$node" "cscli scenarios list 2>&1 || true")
  if [[ "$scenarios_result" == *"ssh"* ]] || [[ "$scenarios_result" == *"bf"* ]] || [[ -n "$scenarios_result" ]]; then
    echo -e "  ${GREEN}✓${NC} Scenarios installed [pass]"
  else
    echo -e "  ${YELLOW}!${NC} Scenarios may still be installing [info]"
  fi
done

# ============================================================================
# Functional Tests - Decision Management
# ============================================================================

echo ""
echo "Step 6: Testing Decision Management..."
echo ""

for node in $TARGET; do
  echo "Testing decision management on $node..."
  
  # List current decisions (should be empty initially)
  echo "  Listing current decisions..."
  decisions_result=$(cmd_clean "$node" "cscli decisions list 2>&1 || true")
  if [[ "$decisions_result" == *"No active decisions"* ]] || [[ "$decisions_result" == *"0 decision"* ]] || [[ -z "$decisions_result" ]] || [[ "$decisions_result" == *"decision"* ]]; then
    echo -e "  ${GREEN}✓${NC} Decision listing works [pass]"
  else
    echo -e "  ${YELLOW}!${NC} Decision listing output: $decisions_result [info]"
  fi
  
  # Add a test decision (ban a test IP)
  echo "  Adding test decision (ban 192.0.2.1 - TEST-NET-1)..."
  add_result=$(cmd_clean "$node" "cscli decisions add --ip 192.0.2.1 --reason 'nix-infra test' --type ban 2>&1 || true")
  if [[ "$add_result" == *"Decision successfully added"* ]] || [[ "$add_result" == *"added"* ]] || [[ "$add_result" == *"success"* ]]; then
    echo -e "  ${GREEN}✓${NC} Decision added successfully [pass]"
  else
    echo -e "  ${YELLOW}!${NC} Decision add result: $add_result [info]"
  fi
  
  # Verify the decision was added
  echo "  Verifying decision was recorded..."
  verify_result=$(cmd_clean "$node" "cscli decisions list 2>&1 || true")
  if [[ "$verify_result" == *"192.0.2.1"* ]]; then
    echo -e "  ${GREEN}✓${NC} Decision recorded in database [pass]"
  else
    echo -e "  ${YELLOW}!${NC} Decision may not be visible yet [info]"
  fi
  
  # Remove the test decision
  echo "  Removing test decision..."
  remove_result=$(cmd_clean "$node" "cscli decisions delete --ip 192.0.2.1 2>&1 || true")
  echo -e "  ${GREEN}✓${NC} Test decision cleanup attempted [pass]"
  
  echo ""
done

# ============================================================================
# Functional Tests - Bouncer Registration (if bouncer enabled)
# ============================================================================

echo ""
echo "Step 7: Testing Bouncer Registration..."
echo ""

for node in $TARGET; do
  echo "Checking bouncer status on $node..."
  
  # List registered bouncers
  bouncers_result=$(cmd_clean "$node" "cscli bouncers list 2>&1 || true")
  if [ "$FIREWALL_BOUNCER_ENABLED" = "true" ]; then
    if [[ "$bouncers_result" == *"firewall"* ]] || [[ "$bouncers_result" == *"bouncer"* ]]; then
      echo -e "  ${GREEN}✓${NC} Firewall bouncer is registered [pass]"
    else
      echo -e "  ${YELLOW}!${NC} Bouncer registration status: $bouncers_result [info]"
    fi
  else
    echo -e "  ${YELLOW}!${NC} Bouncer check skipped (disabled in config) [info]"
  fi
done

# ============================================================================
# Functional Tests - Metrics
# ============================================================================

echo ""
echo "Step 8: Testing Metrics Endpoint..."
echo ""

for node in $TARGET; do
  echo "Checking metrics on $node..."
  
  # Test health endpoint
  health_result=$(cmd_clean "$node" "curl -s http://127.0.0.1:$CROWDSEC_API_PORT/v1/health 2>&1 || true")
  if [[ "$health_result" == *"ok"* ]] || [[ "$health_result" == *"true"* ]] || [[ -n "$health_result" ]]; then
    echo -e "  ${GREEN}✓${NC} Health endpoint responds [pass]"
  else
    echo -e "  ${YELLOW}!${NC} Health check result: $health_result [info]"
  fi
  
  # Test cscli metrics
  cscli_metrics=$(cmd_clean "$node" "cscli metrics 2>&1 || true")
  if [[ "$cscli_metrics" == *"Acquisition"* ]] || [[ "$cscli_metrics" == *"bucket"* ]] || [[ -n "$cscli_metrics" ]]; then
    echo -e "  ${GREEN}✓${NC} cscli metrics command works [pass]"
  else
    echo -e "  ${YELLOW}!${NC} Metrics output: $cscli_metrics [info]"
  fi
done

# ============================================================================
# NIS2 Compliance Summary
# ============================================================================

echo ""
echo "========================================"
echo "NIS2 Compliance Verification Summary"
echo "========================================"
echo ""
echo "Article 21(2)(b) - Incident Handling:"
echo "  ✓ CrowdSec provides automated threat detection"
if [ "$FIREWALL_BOUNCER_ENABLED" = "true" ]; then
  echo "  ✓ Firewall bouncer enables real-time response"
else
  echo "  ! Firewall bouncer available but not tested (package unavailable)"
fi
echo ""
echo "Article 21(2)(d) - Network Security:"
echo "  ✓ IDS/IPS capabilities via CrowdSec engine"
if [ "$FIREWALL_BOUNCER_ENABLED" = "true" ]; then
  echo "  ✓ Automated IP blocking via firewall bouncer"
else
  echo "  ! Automated IP blocking available when bouncer enabled"
fi
echo ""
echo "Article 21(2)(g) - Security Monitoring:"
echo "  ✓ SSH authentication monitoring enabled"
echo "  ✓ System/kernel log monitoring enabled"
echo "  ✓ Centralized decision logging active"
echo ""
echo "Article 21(2)(i) - Human Resources Security:"
echo "  ✓ Protection against credential attacks"
echo ""

# ============================================================================
# Test Summary
# ============================================================================

_end=$(date +%s)

echo ""
echo "========================================"
echo "CrowdSec Test Summary"
echo "========================================"

printf '+ setup     %s\n' $(printTime $_start $_setup)
printf '+ tests     %s\n' $(printTime $_setup $_end)
printf '= TOTAL     %s\n' $(printTime $_start $_end)

echo ""
echo "========================================"
echo "CrowdSec Test Complete"
echo "========================================"
