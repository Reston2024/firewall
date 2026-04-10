#!/bin/bash
# validate-phase13.sh — Phase 13 validation: Alert Triage & SOC Integration
# Run FROM the laptop (192.168.1.100) or IPFire (both can reach 192.168.1.22)
#
# Scope: infrastructure prerequisites for the TRI-06 end-to-end test.
# The actual E2E receipt verification lives in validate-tri06.sh.
#
# History:
# - TRI-05 was an IPFire-local executor scaffold check (:8300 /health).
#   Retracted per ADR-E04: the executor gate lives on the desktop SOC.
#   Retained as documented SKIP so the intent is preserved, not silently removed.
# - TRI-06 (ISM policy coverage) renamed to TRI-03b. The real TRI-06 E2E
#   (receipt-in-index) is now gated by scripts/validate-tri06.sh.

FAIL=0; PASS=0; SKIP=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "SKIP: $1"; SKIP=$((SKIP + 1)); }

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

# --- TRI-03b: ISM retention policy covers triage-results ---
# (Was TRI-06 infra-check; the real TRI-06 E2E gate lives in validate-tri06.sh.)
echo "[TRI-03b] ISM retention policy includes triage-results-*"
TRI03B_OUT=$(curl -sk -u "${CREDS}" "https://192.168.1.22:9200/_plugins/_ism/policies/malcolm-retention" 2>/dev/null)
if echo "$TRI03B_OUT" | grep -q "triage-results"; then
  pass "TRI-03b: ISM policy malcolm-retention covers triage-results-*"
else
  fail "TRI-03b: ISM policy does not cover triage-results-* indices"
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

# --- TRI-05: Firewall executor endpoint (retracted per ADR-E04) ---
# Original intent: check scaffold executor at 127.0.0.1:8300 (on IPFire or supportTAK).
# ADR-E04 moved the executor gate to the desktop SOC (192.168.1.102), which is
# outside this repo's validation scope. Recorded as SKIP with rationale so the
# requirement history is preserved.
echo "[TRI-05] Firewall executor endpoint (scaffold retracted)"
skip "TRI-05: executor gate retracted from data layer per ADR-E04; E2E validated via TRI-06 receipt in scripts/validate-tri06.sh"
echo ""

# --- TRI-06: End-to-end receipt in OpenSearch ---
# The actual E2E gate lives in scripts/validate-tri06.sh so it can be run
# independently, orchestrated by validate-all.sh, and rerun after the desktop
# SOC emits a receipt. This line is a pointer, not a duplicate check.
echo "[TRI-06] End-to-end receipt verification"
skip "TRI-06: run scripts/validate-tri06.sh (dedicated E2E gate; see docs/tri06-receipt-contract.md)"
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
