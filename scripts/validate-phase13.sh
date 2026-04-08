#!/bin/bash
# validate-phase13.sh — Phase 13 validation: Alert Triage & SOC Integration
# Run FROM local Windows machine

FAIL=0; PASS=0; SKIP=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "SKIP: $1"; SKIP=$((SKIP + 1)); }

SSH_TARGET="opsadmin@192.168.1.22"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
CREDS="malcolm_internal:AzZqIn8B6AS1RuX0K8NbbzJZuYaTDARks9Tu"

echo "=== Phase 13 Validation — Alert Triage & SOC Integration — $(date) ==="
echo ""

# --- TRI-01: OpenSearch accessible from LAN ---
echo "[TRI-01] Malcolm OpenSearch API accessible from Windows desktop"
TRI01_OUT=$(curl -sk -u "${CREDS}" "https://192.168.1.22:9200/_cluster/health" 2>/dev/null)
if echo "$TRI01_OUT" | grep -q '"status":"green"'; then
  pass "TRI-01: OpenSearch API accessible from LAN — cluster green"
elif echo "$TRI01_OUT" | grep -q '"status"'; then
  pass "TRI-01: OpenSearch API accessible from LAN — cluster $(echo "$TRI01_OUT" | grep -o '"status":"[^"]*"')"
else
  fail "TRI-01: Cannot reach OpenSearch at https://192.168.1.22:9200"
fi
echo ""

# --- TRI-02: Suricata alerts queryable ---
echo "[TRI-02] Suricata alert events queryable via OpenSearch API"
TRI02_COUNT=$(curl -sk -u "${CREDS}" "https://192.168.1.22:9200/arkime_sessions3-*/_count" -H "Content-Type: application/json" -d '{"query":{"match":{"event.dataset":"alert"}}}' 2>/dev/null | grep -o '"count":[0-9]*' | grep -o '[0-9]*')
if [ -n "$TRI02_COUNT" ] && [ "$TRI02_COUNT" -gt 0 ] 2>/dev/null; then
  pass "TRI-02: $TRI02_COUNT Suricata alerts queryable from LAN"
else
  fail "TRI-02: No Suricata alerts found in OpenSearch"
fi
echo ""

# --- TRI-03: triage-results index template exists ---
echo "[TRI-03] triage-results-* index template configured"
TRI03_OUT=$(curl -sk -u "${CREDS}" "https://192.168.1.22:9200/_index_template/triage-results-template" 2>/dev/null)
if echo "$TRI03_OUT" | grep -q "triage-results"; then
  pass "TRI-03: triage-results-* index template exists in OpenSearch"
else
  fail "TRI-03: triage-results-* index template not found"
fi
echo ""

# --- TRI-04: ChromaDB RAG API accessible ---
echo "[TRI-04] ChromaDB RAG API accessible from Windows desktop"
TRI04_OUT=$(curl -s "http://192.168.1.22:8200/health" 2>/dev/null)
if echo "$TRI04_OUT" | grep -q '"status": "ok"'; then
  TRI04_COUNT=$(echo "$TRI04_OUT" | grep -o '"count": [0-9]*' | grep -o '[0-9]*')
  pass "TRI-04: ChromaDB API accessible — $TRI04_COUNT chunks in corpus"
else
  fail "TRI-04: ChromaDB API not accessible at http://192.168.1.22:8200"
fi
echo ""

# --- TRI-05: Firewall executor endpoint running ---
echo "[TRI-05] Firewall executor endpoint running (scaffold mode)"
TRI05_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" "curl -s http://127.0.0.1:8300/health" 2>/dev/null)
if echo "$TRI05_OUT" | grep -q '"mode": "scaffold"'; then
  pass "TRI-05: Executor running in scaffold mode on localhost:8300"
else
  fail "TRI-05: Executor not running at 127.0.0.1:8300"
fi
echo ""

# --- TRI-06: ISM policy covers triage-results ---
echo "[TRI-06] ISM retention policy includes triage-results-*"
TRI06_OUT=$(curl -sk -u "${CREDS}" "https://192.168.1.22:9200/_plugins/_ism/policies/malcolm-retention" 2>/dev/null)
if echo "$TRI06_OUT" | grep -q "triage-results"; then
  pass "TRI-06: ISM policy malcolm-retention covers triage-results-*"
else
  fail "TRI-06: ISM policy does not cover triage-results-* indices"
fi
echo ""

# --- Summary ---
echo "=== Phase 13 Validation Summary ==="
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo ""
if [ $FAIL -gt 0 ]; then
  echo "=== FAILED: $FAIL check(s) require attention ==="
  exit $FAIL
else
  echo "=== ALL CHECKS PASS ($SKIP skipped) ==="
  exit 0
fi
