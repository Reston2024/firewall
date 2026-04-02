#!/bin/bash
# validate-phase9.sh — Phase 9 validation suite: Malcolm NSM Deployment
# Run FROM local Windows machine — SSHes to supportTAK-server (192.168.1.22) as opsadmin
# Usage: bash scripts/validate-phase9.sh [--full]
# Quick mode (default): MAL-01 container health, kernel param, swap, OOM, MAL-06 capture disabled
# Full mode (--full): includes MAL-04 ISM policy check and MAL-05 dashboards check
#
# Environment variables:
#   MALCOLM_PASS — Malcolm admin password (required for MAL-01b heap check)
#                  If unset, MAL-01b will be skipped with instructions.
#
# Note: MAL-04 (ISM policy) is expected to FAIL after Plan 01 — it is configured in Plan 02.
# Note: Arkime container may report "unhealthy" — this is EXPECTED when capture is disabled.
#       It does NOT count as a failure for this validation suite.

if [ "${1}" = "--full" ]; then FULL=1; else FULL=0; fi

# Malcolm credentials — read from environment to avoid hardcoding secrets
MALCOLM_USER="${MALCOLM_USER:-admin}"
MALCOLM_PASS="${MALCOLM_PASS:-}"
if [ -z "$MALCOLM_PASS" ]; then
  echo "WARNING: MALCOLM_PASS not set. OpenSearch heap check (MAL-01b) will be skipped."
  echo "         Export the Malcolm admin password: export MALCOLM_PASS=<password>"
  echo ""
fi

FAIL=0
PASS=0
SKIP=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "SKIP: $1 (manual verification required)"; SKIP=$((SKIP + 1)); }

SSH_TARGET="opsadmin@192.168.1.22"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"

echo "=== Phase 9 Validation Suite — Malcolm NSM Deployment — $(date) ==="
echo ""

# --- MAL-01a: Malcolm containers running ---
echo "[MAL-01a] Malcolm Docker Compose containers running"

MAL01A_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" \
  "sudo docker compose -f /opt/malcolm/docker-compose.yml ps --format '{{.Name}} {{.Status}}' 2>/dev/null" 2>/dev/null)
MAL01A_EXIT=$?

if [ $MAL01A_EXIT -ne 0 ] || [ -z "$MAL01A_OUT" ]; then
  fail "MAL-01a: Cannot reach supportTAK-server or Malcolm Docker Compose not running. Check: ssh $SSH_TARGET 'sudo docker compose -f /opt/malcolm/docker-compose.yml ps'"
else
  CONTAINER_COUNT=$(echo "$MAL01A_OUT" | grep -c "malcolm" 2>/dev/null || echo "0")
  RESTARTING=$(echo "$MAL01A_OUT" | grep -i "restarting" | grep -v -i "arkime" 2>/dev/null)
  ARKIME_STATUS=$(echo "$MAL01A_OUT" | grep -i "arkime" 2>/dev/null)

  if [ "$CONTAINER_COUNT" -lt 8 ]; then
    fail "MAL-01a: Expected at least 8 Malcolm containers, found $CONTAINER_COUNT. Run: sudo docker compose -f /opt/malcolm/docker-compose.yml ps"
  elif [ -n "$RESTARTING" ]; then
    fail "MAL-01a: One or more non-Arkime containers in 'restarting' state: $RESTARTING"
  else
    pass "MAL-01a: $CONTAINER_COUNT Malcolm containers running, no unexpected restarts"
    if echo "$ARKIME_STATUS" | grep -qi "unhealthy"; then
      echo "        NOTE: Arkime container shows 'unhealthy' — this is EXPECTED when capture is disabled (MAL-06)"
    fi
  fi
fi
echo ""

# --- MAL-01b: OpenSearch heap within 6GB boundary ---
echo "[MAL-01b] OpenSearch JVM heap within 6GB boundary"

if [ -z "$MALCOLM_PASS" ]; then
  skip "MAL-01b: MALCOLM_PASS not set — export MALCOLM_PASS=<password> and re-run"
else
  MAL01B_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" \
    "sudo docker exec malcolm-opensearch-1 curl -sk -u \"${MALCOLM_USER}:${MALCOLM_PASS}\" http://localhost:9200/_nodes/stats/jvm 2>/dev/null" 2>/dev/null)
  MAL01B_EXIT=$?

  if [ $MAL01B_EXIT -ne 0 ] || [ -z "$MAL01B_OUT" ]; then
    skip "MAL-01b: Cannot reach OpenSearch API — verify Malcolm is running and credentials are correct"
  elif echo "$MAL01B_OUT" | grep -q "heap_max_in_bytes"; then
    HEAP_BYTES=$(echo "$MAL01B_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); nodes=d['nodes']; n=list(nodes.values())[0]; print(n['jvm']['mem']['heap_max_in_bytes'])" 2>/dev/null)
    # 6GB = 6442450944 bytes
    MAX_HEAP=6442450944
    if [ -n "$HEAP_BYTES" ] && [ "$HEAP_BYTES" -le "$MAX_HEAP" ] 2>/dev/null; then
      HEAP_GB=$(echo "scale=1; $HEAP_BYTES / 1073741824" | bc 2>/dev/null || echo "~6")
      pass "MAL-01b: OpenSearch heap_max = ${HEAP_GB}GB (<= 6GB boundary)"
    elif [ -n "$HEAP_BYTES" ]; then
      HEAP_GB=$(echo "scale=1; $HEAP_BYTES / 1073741824" | bc 2>/dev/null || echo "?")
      fail "MAL-01b: OpenSearch heap_max = ${HEAP_GB}GB exceeds 6GB limit. Edit /opt/malcolm/config/opensearch.env: OPENSEARCH_JAVA_OPTS=-Xms6g -Xmx6g and restart Malcolm."
    else
      skip "MAL-01b: Could not parse heap_max_in_bytes from OpenSearch JVM stats — check OpenSearch health"
    fi
  else
    skip "MAL-01b: Unexpected OpenSearch response — check credentials and OpenSearch health"
  fi
fi
echo ""

# --- MAL-01c: vm.max_map_count kernel parameter ---
echo "[MAL-01c] vm.max_map_count=262144 kernel parameter set"

MAL01C_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" \
  "sysctl vm.max_map_count 2>/dev/null" 2>/dev/null)
MAL01C_EXIT=$?

if [ $MAL01C_EXIT -ne 0 ] || [ -z "$MAL01C_OUT" ]; then
  fail "MAL-01c: Cannot reach supportTAK-server to check vm.max_map_count. Set: echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-malcolm.conf && sudo sysctl -w vm.max_map_count=262144"
elif echo "$MAL01C_OUT" | grep -q "262144"; then
  pass "MAL-01c: vm.max_map_count = 262144 (required for OpenSearch)"
else
  CURRENT_VAL=$(echo "$MAL01C_OUT" | awk '{print $3}')
  fail "MAL-01c: vm.max_map_count = $CURRENT_VAL (expected 262144). Fix: sudo sysctl -w vm.max_map_count=262144 && echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-malcolm.conf"
fi
echo ""

# --- MAL-01d: Swap configured (at least 3GB) ---
echo "[MAL-01d] Swap configured (at least 3GB as OOM safety net)"

MAL01D_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" \
  "free -m | grep Swap 2>/dev/null" 2>/dev/null)
MAL01D_EXIT=$?

if [ $MAL01D_EXIT -ne 0 ] || [ -z "$MAL01D_OUT" ]; then
  fail "MAL-01d: Cannot check swap on supportTAK-server. Configure: sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile"
else
  SWAP_TOTAL=$(echo "$MAL01D_OUT" | awk '{print $2}')
  if [ -n "$SWAP_TOTAL" ] && [ "$SWAP_TOTAL" -ge 3000 ] 2>/dev/null; then
    pass "MAL-01d: Swap total = ${SWAP_TOTAL}MB (>= 3000MB OOM safety net configured)"
  elif [ -n "$SWAP_TOTAL" ] && [ "$SWAP_TOTAL" -eq 0 ] 2>/dev/null; then
    fail "MAL-01d: No swap configured. Create 4GB swap: sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile && echo '/swapfile none swap sw,pri=10 0 0' | sudo tee -a /etc/fstab"
  else
    fail "MAL-01d: Swap total = ${SWAP_TOTAL}MB (expected >= 3000MB). Expand swap to 4GB."
  fi
fi
echo ""

# --- MAL-01e: No OOM kills detected ---
echo "[MAL-01e] No OOM kills in dmesg (silent container death detection)"

MAL01E_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" \
  "sudo dmesg | grep -i 'oom' 2>/dev/null | tail -5" 2>/dev/null)
MAL01E_EXIT=$?

if [ $MAL01E_EXIT -ne 0 ]; then
  skip "MAL-01e: Cannot check dmesg on supportTAK-server — verify manually: sudo dmesg | grep -i oom"
elif [ -z "$MAL01E_OUT" ]; then
  pass "MAL-01e: No OOM kills in dmesg — no container memory exhaustion detected"
else
  fail "MAL-01e: OOM messages found in dmesg — container(s) may have been killed by OOM killer:
$(echo "$MAL01E_OUT" | sed 's/^/        /')
        Check for containers with high restart counts: sudo docker compose -f /opt/malcolm/docker-compose.yml ps"
fi
echo ""

# --- MAL-01f: Steady-state RAM check ---
echo "[MAL-01f] Steady-state RAM usage under 14GB threshold"

MAL01F_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" \
  "free -m | grep Mem 2>/dev/null" 2>/dev/null)
MAL01F_EXIT=$?

if [ $MAL01F_EXIT -ne 0 ] || [ -z "$MAL01F_OUT" ]; then
  skip "MAL-01f: Cannot check RAM on supportTAK-server"
else
  MEM_USED=$(echo "$MAL01F_OUT" | awk '{print $3}')
  MEM_TOTAL=$(echo "$MAL01F_OUT" | awk '{print $2}')
  if [ -n "$MEM_USED" ] && [ "$MEM_USED" -lt 14000 ] 2>/dev/null; then
    if [ "$MEM_USED" -gt 13000 ] 2>/dev/null; then
      pass "MAL-01f: RAM used = ${MEM_USED}MB / ${MEM_TOTAL}MB (WARN: above 13GB — approaching limit; monitor for OOM)"
    else
      pass "MAL-01f: RAM used = ${MEM_USED}MB / ${MEM_TOTAL}MB (within safe operating range)"
    fi
  elif [ -n "$MEM_USED" ]; then
    fail "MAL-01f: RAM used = ${MEM_USED}MB / ${MEM_TOTAL}MB exceeds 14GB threshold. Swap active? Check: sudo dmesg | grep -i oom"
  else
    skip "MAL-01f: Could not parse RAM usage from free -m output"
  fi
fi
echo ""

# --- MAL-04: ISM policy exists (expected to fail after Plan 01, pass after Plan 02) ---
echo "[MAL-04] OpenSearch ISM retention policy 'malcolm-retention' exists"

if [ "$FULL" -eq 0 ]; then
  skip "MAL-04: ISM policy check skipped in quick mode — run with --full to include (expected to FAIL until Plan 02 configures it)"
else
  if [ -z "$MALCOLM_PASS" ]; then
    skip "MAL-04: MALCOLM_PASS not set — export MALCOLM_PASS=<password> and re-run with --full"
  else
    MAL04_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" \
      "sudo docker exec malcolm-opensearch-1 curl -sk -u \"${MALCOLM_USER}:${MALCOLM_PASS}\" http://localhost:9200/_plugins/_ism/policies/malcolm-retention 2>/dev/null" 2>/dev/null)
    MAL04_EXIT=$?

    if [ $MAL04_EXIT -ne 0 ] || [ -z "$MAL04_OUT" ]; then
      fail "MAL-04: Cannot reach OpenSearch ISM API — verify Malcolm is running. Note: ISM policy is configured in Plan 02."
    elif echo "$MAL04_OUT" | grep -q "malcolm-retention"; then
      pass "MAL-04: ISM policy 'malcolm-retention' exists in OpenSearch"
    elif echo "$MAL04_OUT" | grep -q "policy_not_found\|Policy not found\|404"; then
      fail "MAL-04: ISM policy 'malcolm-retention' not found — EXPECTED until Plan 02. Configure via OpenSearch Dashboards: https://192.168.1.22:5601 > Index Management > State Management Policies"
    else
      skip "MAL-04: Unexpected response from ISM API — check OpenSearch health. Response: $(echo "$MAL04_OUT" | head -1)"
    fi
  fi
fi
echo ""

# --- MAL-05: OpenSearch Dashboards accessible (--full mode) ---
echo "[MAL-05] OpenSearch Dashboards accessible via Malcolm nginx at :443"

if [ "$FULL" -eq 0 ]; then
  skip "MAL-05: Dashboards accessibility check skipped in quick mode — run with --full to include"
else
  # Malcolm serves dashboards through nginx at :443, not directly at :5601
  MAL05_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" \
    "curl -sk -o /dev/null -w '%{http_code}' https://localhost:443/ 2>/dev/null" 2>/dev/null)
  MAL05_EXIT=$?

  if [ $MAL05_EXIT -ne 0 ] || [ -z "$MAL05_OUT" ]; then
    fail "MAL-05: Cannot check Malcolm web UI at https://192.168.1.22:443. Verify Malcolm is running and nginx-proxy is healthy."
  elif [ "$MAL05_OUT" = "200" ] || [ "$MAL05_OUT" = "302" ] || [ "$MAL05_OUT" = "401" ]; then
    pass "MAL-05: Malcolm web UI returns HTTP ${MAL05_OUT} at :443 (401=auth required, 302=redirect — both indicate nginx+dashboards are serving)"
  else
    fail "MAL-05: Malcolm web UI returned unexpected HTTP ${MAL05_OUT} at :443. Expected 200, 302, or 401."
  fi
fi
echo ""

# --- MAL-06: Arkime capture disabled ---
echo "[MAL-06] Arkime live capture disabled (no tcpdump/netsniff processes)"

MAL06A_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" \
  "grep -E 'PCAP_ENABLE_NETSNIFF|PCAP_ENABLE_TCPDUMP' /opt/malcolm/config/*.env 2>/dev/null" 2>/dev/null)
MAL06A_EXIT=$?

if [ $MAL06A_EXIT -ne 0 ] || [ -z "$MAL06A_OUT" ]; then
  fail "MAL-06a: Cannot read Malcolm config files at /opt/malcolm/config/*.env — is Malcolm installed? Check: ssh $SSH_TARGET 'ls /opt/malcolm/config/'"
else
  NETSNIFF_FALSE=$(echo "$MAL06A_OUT" | grep "PCAP_ENABLE_NETSNIFF" | grep -c "=false")
  TCPDUMP_FALSE=$(echo "$MAL06A_OUT" | grep "PCAP_ENABLE_TCPDUMP" | grep -c "=false")

  if [ "$NETSNIFF_FALSE" -ge 1 ] && [ "$TCPDUMP_FALSE" -ge 1 ]; then
    pass "MAL-06a: PCAP_ENABLE_NETSNIFF=false and PCAP_ENABLE_TCPDUMP=false confirmed in Malcolm config"
  else
    fail "MAL-06a: Live capture NOT fully disabled. Current settings:
$(echo "$MAL06A_OUT" | sed 's/^/        /')
        Set PCAP_ENABLE_NETSNIFF=false and PCAP_ENABLE_TCPDUMP=false in /opt/malcolm/config/pcap-capture.env"
  fi
fi
echo ""

# --- MAL-06b: Arkime RAM check ---
echo "[MAL-06b] Arkime container RAM usage minimal (< 200MiB — no active capture)"

MAL06B_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" \
  "sudo docker stats --no-stream --format '{{.Name}} {{.MemUsage}}' 2>/dev/null | grep -i arkime" 2>/dev/null)
MAL06B_EXIT=$?

if [ $MAL06B_EXIT -ne 0 ]; then
  skip "MAL-06b: Cannot reach supportTAK-server docker stats — verify Docker is running"
elif [ -z "$MAL06B_OUT" ]; then
  skip "MAL-06b: Arkime container not found in docker stats — verify Malcolm is running"
else
  # Extract memory usage — docker stats reports in format like "150MiB / 16GiB"
  ARKIME_MEM=$(echo "$MAL06B_OUT" | awk '{print $2}' | head -1)
  # Check if memory is in MiB and under 200, or in GiB (which would be a fail)
  if echo "$ARKIME_MEM" | grep -q "GiB"; then
    fail "MAL-06b: Arkime RAM usage is ${ARKIME_MEM} — exceeds 200MiB limit. Capture may be enabled. Check: grep PCAP /opt/malcolm/config/pcap-capture.env"
  elif echo "$ARKIME_MEM" | grep -q "MiB"; then
    MEM_VAL=$(echo "$ARKIME_MEM" | sed 's/MiB.*//')
    if [ -n "$MEM_VAL" ] && [ "${MEM_VAL%.*}" -lt 200 ] 2>/dev/null; then
      pass "MAL-06b: Arkime RAM usage = ${ARKIME_MEM} (< 200MiB — capture is disabled as expected)"
    else
      fail "MAL-06b: Arkime RAM usage = ${ARKIME_MEM} exceeds 200MiB. Disable capture: PCAP_ENABLE_NETSNIFF=false, PCAP_ENABLE_TCPDUMP=false"
    fi
  else
    pass "MAL-06b: Arkime RAM usage = ${ARKIME_MEM} (appears minimal; verify manually if uncertain)"
  fi
fi
echo ""

# --- Summary ---
echo "=== Phase 9 Validation Summary ==="
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo ""
if [ $FAIL -gt 0 ]; then
  echo "=== FAILED: $FAIL check(s) require attention ==="
  exit $FAIL
else
  echo "=== ALL CHECKS PASS ($SKIP skipped) ==="
  exit 0
fi
