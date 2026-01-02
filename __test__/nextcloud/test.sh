#!/usr/bin/env bash
# Nextcloud test for nix-infra-machine
#
# This test:
# 1. Deploys Nextcloud with PostgreSQL, Redis, and Nginx
# 2. Verifies all services are running and started in correct order
# 3. Tests Nextcloud endpoints and functionality
# 4. Cleans up on teardown

# Handle teardown command
if [ "$CMD" = "teardown" ]; then
  echo "Tearing down Nextcloud test..."
  
  # Stop services in reverse order
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" \
    'systemctl stop nginx 2>/dev/null || true'
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" \
    'systemctl stop phpfpm-nextcloud 2>/dev/null || true'
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" \
    'systemctl stop nextcloud-cron 2>/dev/null || true'
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" \
    'systemctl stop redis-nextcloud 2>/dev/null || true'
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" \
    'systemctl stop postgresql 2>/dev/null || true'
  
  # Clean up data directories
  $NIX_INFRA fleet cmd -d "$WORK_DIR" --target="$TARGET" \
    'rm -rf /var/lib/nextcloud /var/lib/postgresql /var/lib/redis-nextcloud /run/secrets/nextcloud-admin-pass'
  
  echo "Nextcloud teardown complete"
  return 0
fi

# ============================================================================
# Test Setup
# ============================================================================

_start=$(date +%s)

echo ""
echo "========================================"
echo "Nextcloud Test"
echo "========================================"
echo ""

# Deploy the nextcloud configuration to test nodes
echo "Step 1: Deploying Nextcloud configuration..."
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
echo "Step 3: Verifying Nextcloud deployment..."
echo ""

# Wait for services to start (Nextcloud setup can take some time)
echo "Waiting for services to start (this may take a while for initial setup)..."
sleep 15

# ============================================================================
# Check Service Status
# ============================================================================

echo ""
echo "Checking systemd services status..."
echo ""

# Array of services to check (in dependency order)
SERVICES=("postgresql" "redis-nextcloud" "nextcloud-setup" "phpfpm-nextcloud" "nginx")

for node in $TARGET; do
  echo "Checking services on $node..."
  
  for service in "${SERVICES[@]}"; do
    # Skip nextcloud-setup as it's a oneshot service
    if [[ "$service" == "nextcloud-setup" ]]; then
      service_result=$(cmd_value "$node" "systemctl is-active $service 2>/dev/null || echo 'inactive'")
      # For oneshot services, check if it completed successfully
      if [[ "$service_result" == "inactive" ]]; then
        # Check if it exited successfully
        exit_status=$(cmd_value "$node" "systemctl show -p ExecMainStatus $service | cut -d= -f2")
        if [[ "$exit_status" == "0" ]]; then
          echo -e "  ${GREEN}✓${NC} $service: completed successfully [pass]"
        else
          echo -e "  ${RED}✗${NC} $service: failed (exit status: $exit_status) [fail]"
          echo ""
          echo "Service logs:"
          cmd "$node" "journalctl -n 50 -u $service"
        fi
      else
        echo -e "  ${GREEN}✓${NC} $service: $service_result [pass]"
      fi
    else
      service_status=$(cmd_value "$node" "systemctl is-active $service")
      if [[ "$service_status" == "active" ]]; then
        echo -e "  ${GREEN}✓${NC} $service: active [pass]"
      else
        echo -e "  ${RED}✗${NC} $service: $service_status [fail]"
        echo ""
        echo "Service logs:"
        cmd "$node" "journalctl -n 50 -u $service"
      fi
    fi
  done
done

# ============================================================================
# Check Service Dependencies
# ============================================================================

echo ""
echo "Step 4: Verifying service dependencies..."
echo ""

for node in $TARGET; do
  echo "Checking service dependencies on $node..."
  
  # Check PostgreSQL started before nextcloud-setup
  pg_start=$(cmd_value "$node" "systemctl show -p ActiveEnterTimestampMonotonic postgresql --value")
  nc_setup_start=$(cmd_value "$node" "systemctl show -p ActiveEnterTimestampMonotonic nextcloud-setup --value")
  
  if [[ -n "$pg_start" ]] && [[ -n "$nc_setup_start" ]] && [[ "$pg_start" -lt "$nc_setup_start" ]]; then
    echo -e "  ${GREEN}✓${NC} PostgreSQL started before nextcloud-setup [pass]"
  else
    echo -e "  ${YELLOW}!${NC} Could not verify PostgreSQL started before nextcloud-setup [fail]"
  fi
  
  # Check Redis started before nextcloud-setup
  redis_start=$(cmd_value "$node" "systemctl show -p ActiveEnterTimestampMonotonic redis-nextcloud --value")
  
  if [[ -n "$redis_start" ]] && [[ -n "$nc_setup_start" ]] && [[ "$redis_start" -lt "$nc_setup_start" ]]; then
    echo -e "  ${GREEN}✓${NC} Redis started before nextcloud-setup [pass]"
  else
    echo -e "  ${YELLOW}!${NC} Could not verify Redis started before nextcloud-setup [fail]"
  fi
  
  # Check nextcloud-setup completed before phpfpm-nextcloud
  phpfpm_start=$(cmd_value "$node" "systemctl show -p ActiveEnterTimestampMonotonic phpfpm-nextcloud --value")
  
  if [[ -n "$nc_setup_start" ]] && [[ -n "$phpfpm_start" ]] && [[ "$nc_setup_start" -lt "$phpfpm_start" ]]; then
    echo -e "  ${GREEN}✓${NC} nextcloud-setup completed before phpfpm-nextcloud [pass]"
  else
    echo -e "  ${YELLOW}!${NC} Could not verify nextcloud-setup completed before phpfpm-nextcloud [fail]"
  fi
  
  # Check phpfpm-nextcloud started before nginx
  nginx_start=$(cmd_value "$node" "systemctl show -p ActiveEnterTimestampMonotonic nginx --value")
  
  if [[ -n "$phpfpm_start" ]] && [[ -n "$nginx_start" ]] && [[ "$phpfpm_start" -lt "$nginx_start" ]]; then
    echo -e "  ${GREEN}✓${NC} phpfpm-nextcloud started before nginx [pass]"
  else
    echo -e "  ${YELLOW}!${NC} Could not verify phpfpm-nextcloud started before nginx [fail]"
  fi
done

# ============================================================================
# Check Port Bindings
# ============================================================================

echo ""
echo "Step 5: Checking port bindings..."
echo ""

for node in $TARGET; do
  echo "Checking ports on $node..."
  
  # Check PostgreSQL port
  pg_port=$(cmd "$node" "ss -tlnp | grep ':5432 '")
  if [[ "$pg_port" == *":5432"* ]]; then
    echo -e "  ${GREEN}✓${NC} PostgreSQL port 5432 is listening [pass]"
  else
    echo -e "  ${RED}✗${NC} PostgreSQL port 5432 is not listening [fail]"
  fi
  
  # Check Redis port
  redis_port=$(cmd "$node" "ss -tlnp | grep ':6379 '")
  if [[ "$redis_port" == *":6379"* ]]; then
    echo -e "  ${GREEN}✓${NC} Redis port 6379 is listening [pass]"
  else
    echo -e "  ${RED}✗${NC} Redis port 6379 is not listening [fail]"
  fi
  
  # Check HTTP port
  http_port=$(cmd "$node" "ss -tlnp | grep ':80 '")
  if [[ "$http_port" == *":80"* ]]; then
    echo -e "  ${GREEN}✓${NC} HTTP port 80 is listening [pass]"
  else
    echo -e "  ${RED}✗${NC} HTTP port 80 is not listening [fail]"
  fi
done

# ============================================================================
# Functional Tests
# ============================================================================

echo ""
echo "Step 6: Running functional tests..."
echo ""

for node in $TARGET; do
  echo "Testing Nextcloud on $node..."
  
  # Test Nextcloud HTTP response
  echo "  Testing Nextcloud HTTP response..."
  http_code=$(cmd_value "$node" "curl -s -o /dev/null -w '%{http_code}' http://localhost/ 2>/dev/null || echo '000'")
  # Nextcloud may redirect to login or return 200
  if [[ "$http_code" == "200" ]] || [[ "$http_code" == "302" ]] || [[ "$http_code" == "303" ]]; then
    echo -e "  ${GREEN}✓${NC} HTTP response code: $http_code [pass]"
  else
    echo -e "  ${RED}✗${NC} HTTP response code: $http_code [fail]"
  fi
  
  # Test Nextcloud login page
  echo "  Testing Nextcloud login page..."
  login_page=$(cmd_clean "$node" "curl -s -L http://localhost/login 2>/dev/null | head -c 2000")
  if [[ "$login_page" == *"Nextcloud"* ]] || [[ "$login_page" == *"login"* ]]; then
    echo -e "  ${GREEN}✓${NC} Nextcloud login page is accessible [pass]"
  else
    echo -e "  ${RED}✗${NC} Nextcloud login page not accessible [fail]"
    echo "    Response preview: ${login_page:0:200}..."
  fi
  
  # Test Nextcloud status endpoint
  echo "  Testing Nextcloud status endpoint..."
  status_response=$(cmd_clean "$node" "curl -s http://localhost/status.php 2>/dev/null")
  if [[ "$status_response" == *"installed"* ]] && [[ "$status_response" == *"true"* ]]; then
    echo -e "  ${GREEN}✓${NC} Nextcloud is installed (status.php) [pass]"
    # Parse version if possible
    version=$(echo "$status_response" | grep -o '"versionstring":"[^"]*"' | cut -d'"' -f4)
    if [[ -n "$version" ]]; then
      echo -e "  ${GREEN}✓${NC} Nextcloud version: $version [info]"
    fi
  else
    echo -e "  ${RED}✗${NC} Nextcloud status check failed [fail]"
    echo "    Response: $status_response"
  fi
  
  # Test PostgreSQL database connection
  echo "  Testing PostgreSQL database..."
  db_check=$(cmd_clean "$node" "sudo -u postgres psql -l | grep nextcloud")
  if [[ "$db_check" == *"nextcloud"* ]]; then
    echo -e "  ${GREEN}✓${NC} Nextcloud database exists in PostgreSQL [pass]"
  else
    echo -e "  ${RED}✗${NC} Nextcloud database not found [fail]"
  fi
  
  # Test Redis connection
  echo "  Testing Redis connection..."
  redis_check=$(cmd_clean "$node" "redis-cli -p 6379 PING 2>/dev/null")
  if [[ "$redis_check" == *"PONG"* ]]; then
    echo -e "  ${GREEN}✓${NC} Redis is responding [pass]"
  else
    echo -e "  ${RED}✗${NC} Redis is not responding [fail]"
  fi
  
  # Test Nextcloud OCC command
  echo "  Testing Nextcloud OCC command..."
  occ_check=$(cmd_clean "$node" "sudo -u nextcloud /run/current-system/sw/bin/nextcloud-occ status 2>/dev/null")
  if [[ "$occ_check" == *"installed: true"* ]]; then
    echo -e "  ${GREEN}✓${NC} Nextcloud OCC reports installed [pass]"
  else
    echo -e "  ${YELLOW}!${NC} Nextcloud OCC status: $occ_check [fail]"
  fi
  
  # Test admin user exists
  echo "  Testing admin user exists..."
  admin_check=$(cmd_clean "$node" "sudo -u nextcloud /run/current-system/sw/bin/nextcloud-occ user:list 2>/dev/null | grep admin")
  if [[ "$admin_check" == *"admin"* ]]; then
    echo -e "  ${GREEN}✓${NC} Admin user exists [pass]"
  else
    echo -e "  ${YELLOW}!${NC} Could not verify admin user [fail]"
  fi
done

# ============================================================================
# Test Summary
# ============================================================================

_end=$(date +%s)

echo ""
echo "========================================"
echo "Nextcloud Test Summary"
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
echo "Nextcloud Test Complete"
echo "========================================"
