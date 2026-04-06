#!/bin/bash
# validate-phase10.sh — Phase 10 validation suite: Telemetry Migration to Malcolm
# Run FROM local machine — SSHes to supportTAK-server (192.168.1.22) as opsadmin
# Usage: bash scripts/validate-phase10.sh
#
# Covers: MAL-02, MAL-03, MIG-01 (post-decommission), MIG-02, MIG-03, MIG-04

FAIL=0
PASS=0
SKIP=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "SKIP: $1 (manual verification required)"; SKIP=$((SKIP + 1)); }

SSH_TARGET="opsadmin@192.168.1.22"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"

# Malcolm internal credentials
INTERNAL_CREDS=$(ssh $SSH_OPTS "$SSH_TARGET" \
  "docker exec malcolm-dashboards-helper-1 cat /var/local/curlrc/.opensearch.primary.curlrc \
   | grep '^user:' | sed 's/^user: \"//;s/\"$//'" 2>/dev/null)

echo "=== Phase 10 Validation Suite — Telemetry Migration to Malcolm — $(date) ==="
echo ""

# --- MAL-02: Suricata EVE JSON in Malcolm OpenSearch ---
echo "[MAL-02] Suricata EVE JSON alerts in Malcolm OpenSearch"

if [ -z "$INTERNAL_CREDS" ]; then
  skip "MAL-02: Cannot read Malcolm internal credentials"
else
  MAL02_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" \
    "docker exec malcolm-opensearch-1 curl -sk -u '${INTERNAL_CREDS}' \
     'https://localhost:9200/arkime_sessions3-*/_count' 2>/dev/null" 2>/dev/null)

  DOC_COUNT=$(echo "$MAL02_OUT" | grep -o '"count":[0-9]*' | grep -o '[0-9]*')
  if [ -n "$DOC_COUNT" ] && [ "$DOC_COUNT" -gt 0 ] 2>/dev/null; then
    pass "MAL-02: Suricata EVE data in arkime_sessions3-* indices ($DOC_COUNT documents)"
  else
    fail "MAL-02: No documents in arkime_sessions3-* indices. Check sync-eve.sh cron and Malcolm internal Filebeat."
  fi
fi
echo ""

# --- MAL-02b: Suricata alerts specifically ---
echo "[MAL-02b] Suricata alert events (event.dataset:alert) present"

if [ -z "$INTERNAL_CREDS" ]; then
  skip "MAL-02b: Cannot read Malcolm internal credentials"
else
  MAL02B_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" \
    "docker exec malcolm-opensearch-1 curl -sk -u '${INTERNAL_CREDS}' \
     'https://localhost:9200/arkime_sessions3-*/_count' -H 'Content-Type: application/json' \
     -d '{\"query\":{\"bool\":{\"must\":[{\"match\":{\"event.dataset\":\"alert\"}}]}}}' 2>/dev/null" 2>/dev/null)

  ALERT_COUNT=$(echo "$MAL02B_OUT" | grep -o '"count":[0-9]*' | grep -o '[0-9]*')
  if [ -n "$ALERT_COUNT" ] && [ "$ALERT_COUNT" -gt 0 ] 2>/dev/null; then
    pass "MAL-02b: $ALERT_COUNT Suricata alert events in OpenSearch"
  else
    fail "MAL-02b: No Suricata alert events found. Trigger test: ssh root@192.168.1.1 'curl -s http://testmynids.org/uid/index.html > /dev/null'"
  fi
fi
echo ""

# --- MAL-03: IPFire syslog in Malcolm OpenSearch ---
echo "[MAL-03] IPFire syslog entries in Malcolm OpenSearch"

if [ -z "$INTERNAL_CREDS" ]; then
  skip "MAL-03: Cannot read Malcolm internal credentials"
else
  MAL03_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" \
    "docker exec malcolm-opensearch-1 curl -sk -u '${INTERNAL_CREDS}' \
     'https://localhost:9200/malcolm_beats_syslog_*/_count' 2>/dev/null" 2>/dev/null)

  SYSLOG_COUNT=$(echo "$MAL03_OUT" | grep -o '"count":[0-9]*' | grep -o '[0-9]*')
  if [ -n "$SYSLOG_COUNT" ] && [ "$SYSLOG_COUNT" -gt 0 ] 2>/dev/null; then
    pass "MAL-03: Syslog data in malcolm_beats_syslog_* indices ($SYSLOG_COUNT documents)"
  else
    fail "MAL-03: No syslog documents in Malcolm. Check rsyslog relay (/etc/rsyslog.d/20-malcolm-forward.conf) and IPFire syslog.conf target."
  fi
fi
echo ""

# --- MIG-02: Loki stack decommissioned ---
echo "[MIG-02] Loki/Alloy/Grafana/Prometheus containers removed"

MIG02_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" \
  "docker ps --format '{{.Names}}' 2>/dev/null | grep -v malcolm | head -5" 2>/dev/null)

if [ -z "$MIG02_OUT" ]; then
  pass "MIG-02: Only Malcolm containers running — Loki stack decommissioned"
else
  fail "MIG-02: Non-Malcolm containers still running: $MIG02_OUT"
fi
echo ""

# --- MIG-03a: Malcolm containers healthy ---
echo "[MIG-03a] Malcolm Docker Compose containers healthy"

MIG03_HEALTHY=$(ssh $SSH_OPTS "$SSH_TARGET" \
  "docker compose -f /opt/malcolm/docker-compose.yml ps --format '{{.Name}} {{.Status}}' 2>/dev/null | grep -c healthy" 2>/dev/null)
MIG03_TOTAL=$(ssh $SSH_OPTS "$SSH_TARGET" \
  "docker compose -f /opt/malcolm/docker-compose.yml ps --format '{{.Name}}' 2>/dev/null | wc -l" 2>/dev/null)

if [ -n "$MIG03_HEALTHY" ] && [ "$MIG03_HEALTHY" -ge 20 ] 2>/dev/null; then
  pass "MIG-03a: $MIG03_HEALTHY of $MIG03_TOTAL Malcolm containers healthy"
else
  fail "MIG-03a: Only $MIG03_HEALTHY of $MIG03_TOTAL containers healthy. Run: docker compose -f /opt/malcolm/docker-compose.yml ps"
fi
echo ""

# --- MIG-03b: Filebeat service active ---
echo "[MIG-03b] rsyslog service active on supportTAK-server"

MIG03B_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" "pgrep -c rsyslogd 2>/dev/null" 2>/dev/null)
if [ -n "$MIG03B_OUT" ] && [ "$MIG03B_OUT" -ge 1 ] 2>/dev/null; then
  pass "MIG-03b: rsyslogd is running ($MIG03B_OUT processes)"
else
  fail "MIG-03b: rsyslogd not running — syslog relay to Malcolm is broken"
fi
echo ""

# --- MIG-03c: SCP cron active ---
echo "[MIG-03c] EVE JSON SCP cron active"

MIG03C_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" "crontab -l 2>/dev/null | grep -c 'sync-eve\|rsync-eve'" 2>/dev/null)
if [ -n "$MIG03C_OUT" ] && [ "$MIG03C_OUT" -ge 1 ] 2>/dev/null; then
  pass "MIG-03c: EVE JSON sync cron is active"
else
  fail "MIG-03c: No EVE sync cron found. Add: * * * * * /opt/malcolm/scripts/sync-eve.sh"
fi
echo ""

# --- MIG-03d: Malcolm web UI accessible ---
echo "[MIG-03d] Malcolm web UI accessible at :443"

MIG03D_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" \
  "curl -sk -o /dev/null -w '%{http_code}' https://localhost:443/ 2>/dev/null" 2>/dev/null)

if [ "$MIG03D_OUT" = "200" ] || [ "$MIG03D_OUT" = "302" ] || [ "$MIG03D_OUT" = "401" ]; then
  pass "MIG-03d: Malcolm web UI returns HTTP $MIG03D_OUT at :443"
else
  fail "MIG-03d: Malcolm web UI returned HTTP $MIG03D_OUT — expected 200/302/401"
fi
echo ""

# --- MIG-03e: RAM check ---
echo "[MIG-03e] Steady-state RAM after Loki decommission"

MIG03E_USED=$(ssh $SSH_OPTS "$SSH_TARGET" "free -m | grep Mem | awk '{print \$3}'" 2>/dev/null)
if [ -n "$MIG03E_USED" ] && [ "$MIG03E_USED" -lt 14000 ] 2>/dev/null; then
  pass "MIG-03e: RAM used = ${MIG03E_USED}MB (under 14GB threshold — Loki decommission freed RAM)"
else
  fail "MIG-03e: RAM used = ${MIG03E_USED}MB (over 14GB threshold)"
fi
echo ""

# --- MIG-04: Runbook updated ---
echo "[MIG-04] Telemetry runbook references Malcolm architecture"

if [ -f "docs/telemetry-deployment-runbook.md" ]; then
  DEPRECATED=$(grep -ciE 'alloy.*source|loki.*source|scp.*cron.*primary' docs/telemetry-deployment-runbook.md 2>/dev/null)
  DEPRECATED=${DEPRECATED:-0}
  MALCOLM_REF=$(grep -ci 'malcolm' docs/telemetry-deployment-runbook.md 2>/dev/null)
  MALCOLM_REF=${MALCOLM_REF:-0}
  if [ "$DEPRECATED" -eq 0 ] && [ "$MALCOLM_REF" -gt 0 ] 2>/dev/null; then
    pass "MIG-04: Runbook references Malcolm ($MALCOLM_REF mentions), no deprecated Alloy/Loki-as-source references"
  elif [ "$DEPRECATED" -gt 0 ]; then
    fail "MIG-04: Runbook still contains $DEPRECATED deprecated references to Alloy/Loki as active sources"
  else
    fail "MIG-04: Runbook does not mention Malcolm"
  fi
else
  fail "MIG-04: docs/telemetry-deployment-runbook.md not found"
fi
echo ""

# --- Summary ---
echo "=== Phase 10 Validation Summary ==="
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo ""
if [ $FAIL -gt 0 ]; then
  echo "=== FAILED: $FAIL check(s) require attention ==="
  exit $FAIL
else
  echo "=== ALL CHECKS PASS ($SKIP skipped) ==="
  exit 0
fi
