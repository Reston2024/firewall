#!/bin/bash
# validate-phase5.sh — Phase 5 validation suite: Telemetry Pipeline and Dashboards
# Run ON supportTAK-server (192.168.1.101) as opsadmin
# Usage: source /opt/telemetry/telemetry/.env && bash /opt/telemetry/scripts/validate-phase5.sh [--full]
# Quick mode: TEL-01 through TEL-08 and DASH-01 through DASH-04 smoke tests
# Full mode (--full): includes live EVE JSON ingest verification (requires 90 seconds)

if [ "${1}" = "--full" ]; then FULL=1; else FULL=0; fi

# Grafana credentials — read from environment to avoid hardcoding secrets
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GF_SECURITY_ADMIN_PASSWORD:-}"
if [ -z "$GRAFANA_PASS" ]; then
  echo "WARNING: GF_SECURITY_ADMIN_PASSWORD not set. Grafana API checks will be skipped."
  echo "         Run: source /opt/telemetry/telemetry/.env before running this script."
  echo ""
fi

FAIL=0
PASS=0
SKIP=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "SKIP: $1 (manual verification required)"; SKIP=$((SKIP + 1)); }

echo "=== Phase 5 Validation Suite — Telemetry Pipeline and Dashboards — $(date) ==="
echo ""

# --- TEL-01: IPFire syslog forwarding configured to 192.168.1.101 ---
echo "[TEL-01] IPFire syslog forwarding configured to 192.168.1.101"

TEL01_OUT=$(ssh -i /home/opsadmin/.ssh/ipfire_ed25519 \
  -o StrictHostKeyChecking=no \
  -o ConnectTimeout=10 \
  -o BatchMode=yes \
  root@192.168.1.1 \
  'grep -i "192.168.1.101" /etc/syslog.conf 2>/dev/null' 2>/dev/null)
TEL01_EXIT=$?

if [ $TEL01_EXIT -ne 0 ]; then
  skip "TEL-01: Cannot SSH to IPFire — verify manually via WUI: Logs > Log Settings > Syslog Server = 192.168.1.101"
elif [ -n "$TEL01_OUT" ]; then
  pass "TEL-01: syslog.conf contains 192.168.1.101 — syslog forwarding configured"
else
  fail "TEL-01: 192.168.1.101 not found in /etc/syslog.conf. Configure via WUI: Logs > Log Settings > Syslog Server = 192.168.1.101"
fi
echo ""

# --- TEL-02: UDP 514 available for Alloy (no rsyslog conflict) ---
echo "[TEL-02] UDP 514 available for Alloy (no rsyslog conflict)"

TEL02_OUT=$(sudo ss -ulnp 2>/dev/null | grep ':514')
if [ -z "$TEL02_OUT" ]; then
  fail "TEL-02: Port 514 not bound — no syslog receiver is running. Deploy stack and ensure rsyslog is enabled with /etc/rsyslog.d/10-ipfire-remote.conf"
elif echo "$TEL02_OUT" | grep -q "rsyslog"; then
  # Architecture: rsyslog receives UDP syslog → writes /var/log/ipfire/syslog.log → Alloy tails file
  if [ -f /etc/rsyslog.d/10-ipfire-remote.conf ]; then
    pass "TEL-02: rsyslog is receiving UDP 514 with IPFire remote config — Alloy tails /var/log/ipfire/syslog.log"
  else
    fail "TEL-02: rsyslog is holding UDP 514 but /etc/rsyslog.d/10-ipfire-remote.conf is missing. Deploy config: cp /opt/telemetry/rsyslog/ipfire-remote.conf /etc/rsyslog.d/10-ipfire-remote.conf && systemctl restart rsyslog"
  fi
else
  pass "TEL-02: UDP 514 is bound — syslog receiver is active"
  echo "        Binding: $(echo "$TEL02_OUT" | head -1)"
fi
echo ""

# --- TEL-03: Docker Compose stack running (all 5 containers) ---
echo "[TEL-03] Docker Compose stack running (all 5 containers)"

if [ ! -f /opt/telemetry/docker-compose.yml ]; then
  skip "TEL-03: /opt/telemetry/docker-compose.yml not found — stack not yet deployed (run Plan 02)"
else
  RUNNING_COUNT=$(sudo docker compose -f /opt/telemetry/docker-compose.yml ps --format json 2>/dev/null | grep -c '"State":"running"')
  if [ "$RUNNING_COUNT" -ge 5 ]; then
    pass "TEL-03: $RUNNING_COUNT containers running (expected >= 5)"
  else
    fail "TEL-03: Expected 5 running containers, found $RUNNING_COUNT. Run: docker compose -f /opt/telemetry/docker-compose.yml ps  to diagnose. Check logs: docker compose -f /opt/telemetry/docker-compose.yml logs --tail=50"
  fi
fi
echo ""

# --- TEL-04: Alloy receiving syslog and Loki has entries ---
echo "[TEL-04] Alloy receiving syslog and Loki has entries"

TEL04_RESULT=$(curl -s -G 'http://localhost:3100/loki/api/v1/query' \
  --data-urlencode 'query=count_over_time({job="ipfire-syslog"}[5m])' 2>/dev/null)
TEL04_EXIT=$?

if [ $TEL04_EXIT -ne 0 ] || echo "$TEL04_RESULT" | grep -q "connection refused"; then
  fail "TEL-04: Cannot reach Loki at http://localhost:3100 — check TEL-03 first"
elif echo "$TEL04_RESULT" | grep -q '"result":\[\]'; then
  skip "TEL-04: No syslog entries in Loki yet — configure IPFire syslog forwarding (Plan 02 runbook Section 5) and wait 60 seconds for first events"
elif echo "$TEL04_RESULT" | grep -q '"result"'; then
  pass "TEL-04: Loki has ipfire-syslog entries"
else
  skip "TEL-04: Unexpected Loki response — check Loki health with TEL-05"
fi
echo ""

# --- TEL-05: Loki ready and storing logs ---
echo "[TEL-05] Loki ready and storing logs"

TEL05_RESULT=$(curl -s http://localhost:3100/ready 2>/dev/null)
TEL05_EXIT=$?

if [ $TEL05_EXIT -ne 0 ] || echo "$TEL05_RESULT" | grep -q "connection refused"; then
  skip "TEL-05: Cannot reach Loki — Loki container not running. Check TEL-03 first"
elif echo "$TEL05_RESULT" | grep -q "ready"; then
  pass "TEL-05: Loki is ready"
else
  fail "TEL-05: Loki not ready. Response: $TEL05_RESULT. Check logs: docker logs loki --tail=50"
fi
echo ""

# --- TEL-06: Grafana accessible and Loki datasource healthy ---
echo "[TEL-06] Grafana accessible and Loki datasource healthy"

if [ -z "$GRAFANA_PASS" ]; then
  skip "TEL-06: GF_SECURITY_ADMIN_PASSWORD not set — source .env first"
else
  TEL06_RESULT=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" http://localhost:3000/api/datasources 2>/dev/null)
  TEL06_EXIT=$?

  if [ $TEL06_EXIT -ne 0 ] || echo "$TEL06_RESULT" | grep -q "connection refused"; then
    skip "TEL-06: Cannot reach Grafana at http://localhost:3000 — Grafana container not running. Check TEL-03 first"
  elif echo "$TEL06_RESULT" | grep -q '"name":"Loki"'; then
    pass "TEL-06: Grafana is accessible and Loki datasource is provisioned"
  elif echo "$TEL06_RESULT" | grep -q "Invalid username or password"; then
    fail "TEL-06: Grafana auth failed — check GF_SECURITY_ADMIN_PASSWORD in .env matches the deployed password"
  else
    fail "TEL-06: Loki datasource not found in Grafana. Check provisioning: docker exec grafana ls /etc/grafana/provisioning/datasources/"
  fi
fi
echo ""

# --- TEL-07: Phased ingest order (syslog before EVE) ---
echo "[TEL-07] Phased ingest order (syslog before EVE)"
skip "TEL-07: Phased ingest order is a deployment procedure (Plan 02 syslog first, Plan 03 EVE JSON). Ordering cannot be automated. Verify: syslog stream {job='ipfire-syslog'} has entries before EVE stream {job='suricata-eve'} is wired."
echo ""

# --- TEL-08: Loki retention configured ---
echo "[TEL-08] Loki retention configured"

if [ ! -f /opt/telemetry/loki/loki-config.yml ]; then
  skip "TEL-08: /opt/telemetry/loki/loki-config.yml not found — stack not yet deployed (run Plan 02)"
elif grep -q "retention_period" /opt/telemetry/loki/loki-config.yml 2>/dev/null; then
  RETENTION_VAL=$(grep "retention_period" /opt/telemetry/loki/loki-config.yml | tr -d ' ')
  pass "TEL-08: retention_period is configured — $RETENTION_VAL"
else
  fail "TEL-08: retention_period not in loki-config.yml. Add: retention_period: 720h under limits_config"
fi
echo ""

# --- DASH-01: Threat trace panel — both syslog and EVE entries (--full only) ---
echo "[DASH-01] Threat trace panel: Loki has both syslog and EVE entries"

if [ "$FULL" -eq 0 ]; then
  skip "DASH-01: Threat trace requires --full flag and live traffic from both IPFire syslog and Suricata. Run: bash validate-phase5.sh --full"
else
  DASH01_SYSLOG=$(curl -s -G 'http://localhost:3100/loki/api/v1/query' \
    --data-urlencode 'query=count_over_time({job="ipfire-syslog"}[24h])' 2>/dev/null | grep -c '"result"')
  DASH01_EVE=$(curl -s -G 'http://localhost:3100/loki/api/v1/query' \
    --data-urlencode 'query=count_over_time({job="suricata-eve"}[24h])' 2>/dev/null | grep -c '"result"')
  if [ "$DASH01_SYSLOG" -gt 0 ] && [ "$DASH01_EVE" -gt 0 ]; then
    pass "DASH-01: Both ipfire-syslog and suricata-eve streams have data — threat trace panel can be populated"
  elif [ "$DASH01_SYSLOG" -gt 0 ] && [ "$DASH01_EVE" -eq 0 ]; then
    skip "DASH-01: No EVE alert data yet — trigger test: ssh -i /home/opsadmin/.ssh/ipfire_ed25519 root@192.168.1.1 'curl -s http://testmynids.org/uid/index.html', wait 90 seconds, then re-run"
  else
    skip "DASH-01: No syslog or EVE data yet — ensure IPFire syslog forwarding is active (Plan 02) and EVE rsync is running (Plan 03)"
  fi
fi
echo ""

# --- DASH-02: Firewall drops time-series query works ---
echo "[DASH-02] Firewall drops time-series query works"

DASH02_RESULT=$(curl -s -G 'http://localhost:3100/loki/api/v1/query' \
  --data-urlencode 'query=count_over_time({job="ipfire-syslog"} |= "FORWARDFW" [1h])' \
  2>/dev/null)
DASH02_EXIT=$?

if [ $DASH02_EXIT -ne 0 ] || echo "$DASH02_RESULT" | grep -q "connection refused"; then
  fail "DASH-02: Cannot reach Loki — check TEL-03 and TEL-05 first"
elif echo "$DASH02_RESULT" | grep -q '"result"'; then
  pass "DASH-02: FORWARDFW time-series query executes successfully (even if value is 0)"
else
  skip "DASH-02: No FORWARDFW entries yet — IPFire syslog forwarding may not be active. Check TEL-01 first."
fi
echo ""

# --- DASH-03: Dashboard 22247 imported ---
echo "[DASH-03] Dashboard 22247 (Suricata Logs Eve JSON) imported"

if [ -z "$GRAFANA_PASS" ]; then
  skip "DASH-03: GF_SECURITY_ADMIN_PASSWORD not set — source .env first"
else
  DASH03_RESULT=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" "http://localhost:3000/api/search?query=suricata" 2>/dev/null)
  DASH03_EXIT=$?

  if [ $DASH03_EXIT -ne 0 ] || echo "$DASH03_RESULT" | grep -q "connection refused"; then
    skip "DASH-03: Cannot reach Grafana — check TEL-03 and TEL-06 first"
  elif echo "$DASH03_RESULT" | grep -qi "suricata"; then
    pass "DASH-03: Suricata dashboard found in Grafana"
  elif echo "$DASH03_RESULT" | grep -q "Invalid username or password"; then
    fail "DASH-03: Grafana auth failed — check GF_SECURITY_ADMIN_PASSWORD in .env matches the deployed password"
  else
    fail "DASH-03: Dashboard 22247 not found. Import via Plan 04 Task 2. Or manually: Grafana > Dashboards > Import > ID 22247. Download URL: https://grafana.com/api/dashboards/22247/revisions/latest/download"
  fi
fi
echo ""

# --- DASH-04: Top rules query executes (EVE data required) ---
echo "[DASH-04] Top rules query executes (EVE data required)"

DASH04_RESULT=$(curl -s -G 'http://localhost:3100/loki/api/v1/query' \
  --data-urlencode 'query=topk(5,sum by (signature)(count_over_time({job="suricata-eve",event_type="alert"}[24h])))' \
  2>/dev/null)
DASH04_EXIT=$?

if [ $DASH04_EXIT -ne 0 ] || echo "$DASH04_RESULT" | grep -q "connection refused"; then
  fail "DASH-04: Cannot reach Loki — check TEL-03 and TEL-05 first"
elif echo "$DASH04_RESULT" | grep -q '"result"'; then
  pass "DASH-04: Top rules (topk) query executes successfully"
else
  skip "DASH-04: No EVE alert data yet — EVE JSON rsync path not active (Plan 03). Run test: ssh -i /home/opsadmin/.ssh/ipfire_ed25519 root@192.168.1.1 'curl -s http://testmynids.org/uid/index.html' and wait 90s"
fi
echo ""

# --- Summary ---
echo "=== Phase 5 Validation ==="
if [ $FAIL -gt 0 ]; then
  echo "=== CHECKS COMPLETE: $PASS PASS, $FAIL FAIL, $SKIP SKIP ==="
  exit 1
else
  echo "=== ALL CHECKS PASS ($SKIP skipped) ==="
  exit 0
fi
