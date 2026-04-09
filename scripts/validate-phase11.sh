# DEPRECATED — ADR-E04: AI removed from data layer. This script validated
# components that have been removed from supportTAK-server. Retained for
# audit trail only. Do not run.
#
#!/usr/bin/env bash
# validate-phase11.sh — Phase 11 validation suite: Foundation-Sec-8B AI Analyst
# Run FROM local machine — SSHes to supportTAK-server (192.168.1.22) as opsadmin
# Usage: bash scripts/validate-phase11.sh [--full]
# Quick mode (default): AI-01 service + binding, AI-02 keepalive, AI-04 security gate
# Full mode (--full): includes AI-01 model response test and RAM check
#
# CRITICAL SECURITY CHECK: ADR-E02 compliance — Ollama MUST bind to 127.0.0.1 only
# If this script reports FAIL_BINDING, the deployment violates ADR-E02 and MUST be fixed
# before Phase 11 is marked complete.
#
# Note: RAM check (AI-04 combined load) may SKIP if Malcolm is not running — run with
# Malcolm active to validate the full simultaneous load scenario.
# Note: Model response test in --full mode requires temporal separation from Malcolm
# indexing peaks — if it fails with "not enough memory", temporarily pause Malcolm's
# OpenSearch/Logstash containers and retry (this demonstrates the temporal separation policy).

set -euo pipefail

if [ "${1:-}" = "--full" ]; then FULL=1; else FULL=0; fi

FAIL=0
PASS=0
SKIP=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "SKIP: $1 (manual verification required)"; SKIP=$((SKIP + 1)); }

SSH_TARGET="opsadmin@192.168.1.22"
SSH_OPTS="-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o BatchMode=yes"

MODEL_NAME="hf.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF"

echo "=== Phase 11 Validation Suite — Foundation-Sec-8B AI Analyst — $(date) ==="
echo ""

# --- AI-01a: Ollama service running ---
echo "[AI-01a] Ollama service active on supportTAK-server"

AI01A_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" \
  "systemctl is-active ollama 2>/dev/null || (pgrep -x ollama > /dev/null 2>&1 && echo 'active' || echo 'inactive')" 2>/dev/null)
AI01A_EXIT=$?

if [ $AI01A_EXIT -ne 0 ] || [ -z "$AI01A_OUT" ]; then
  fail "AI-01a: Cannot reach supportTAK-server. Check: ssh $SSH_TARGET 'systemctl status ollama'"
elif echo "$AI01A_OUT" | grep -q "active"; then
  pass "AI-01a: Ollama service is active on supportTAK-server"
else
  fail "AI-01a: Ollama service is not active. Start: sudo systemctl start ollama"
fi
echo ""

# --- AI-01b: ADR-E02 CRITICAL — Ollama bound to 127.0.0.1 (not 0.0.0.0) ---
echo "[AI-01b] ADR-E02 SECURITY: Ollama bound to 127.0.0.1:11434 (not 0.0.0.0)"

AI01B_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" \
  "ss -tlnp | grep 11434 2>/dev/null" 2>/dev/null)
AI01B_EXIT=$?

if [ $AI01B_EXIT -ne 0 ] || [ -z "$AI01B_OUT" ]; then
  fail "AI-01b: ADR-E02 VIOLATION: Cannot verify Ollama binding — Ollama may not be running on port 11434. Check: ssh $SSH_TARGET 'ss -tlnp | grep 11434'"
elif echo "$AI01B_OUT" | grep -q "127.0.0.1:11434"; then
  pass "AI-01b: ADR-E02 COMPLIANT: Ollama bound to 127.0.0.1:11434 (LAN access blocked)"
elif echo "$AI01B_OUT" | grep -q "0.0.0.0:11434"; then
  fail "AI-01b: ADR-E02 VIOLATION: Ollama is bound to 0.0.0.0:11434 — CRITICAL: LAN devices can access the model unauthenticated. Fix: verify /etc/systemd/system/ollama.service.d/override.conf contains OLLAMA_HOST=127.0.0.1 and restart: sudo systemctl daemon-reload && sudo systemctl restart ollama"
else
  fail "AI-01b: ADR-E02: Cannot determine Ollama binding. Raw output: $AI01B_OUT"
fi
echo ""

# --- AI-02a: Systemd override file exists with OLLAMA_HOST ---
echo "[AI-02a] Systemd override file exists with OLLAMA_HOST=127.0.0.1"

AI02A_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" \
  "grep -q 'OLLAMA_HOST=127.0.0.1' /etc/systemd/system/ollama.service.d/override.conf 2>/dev/null && echo 'FOUND' || echo 'MISSING'" 2>/dev/null)
AI02A_EXIT=$?

if [ $AI02A_EXIT -ne 0 ] || [ -z "$AI02A_OUT" ]; then
  fail "AI-02a: Cannot check systemd override file on supportTAK-server"
elif echo "$AI02A_OUT" | grep -q "FOUND"; then
  pass "AI-02a: OLLAMA_HOST=127.0.0.1 found in systemd override file"
else
  fail "AI-02a: OLLAMA_HOST=127.0.0.1 NOT in systemd override. Create: sudo mkdir -p /etc/systemd/system/ollama.service.d && echo '[Service]' | sudo tee /etc/systemd/system/ollama.service.d/override.conf && echo 'Environment=\"OLLAMA_HOST=127.0.0.1\"' | sudo tee -a /etc/systemd/system/ollama.service.d/override.conf"
fi
echo ""

# --- AI-02b: Systemd override file contains OLLAMA_KEEP_ALIVE=5m ---
echo "[AI-02b] Systemd override file contains OLLAMA_KEEP_ALIVE=5m"

AI02B_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" \
  "grep -q 'OLLAMA_KEEP_ALIVE=5m' /etc/systemd/system/ollama.service.d/override.conf 2>/dev/null && echo 'FOUND' || echo 'MISSING'" 2>/dev/null)
AI02B_EXIT=$?

if [ $AI02B_EXIT -ne 0 ] || [ -z "$AI02B_OUT" ]; then
  fail "AI-02b: Cannot check systemd override file on supportTAK-server"
elif echo "$AI02B_OUT" | grep -q "FOUND"; then
  pass "AI-02b: OLLAMA_KEEP_ALIVE=5m found in systemd override (model unloads after 5m idle)"
else
  fail "AI-02b: OLLAMA_KEEP_ALIVE=5m NOT in systemd override. Without this, Foundation-Sec-8B pins 5.5GB RAM permanently, causing Malcolm OOM. Add to override.conf: Environment=\"OLLAMA_KEEP_ALIVE=5m\""
fi
echo ""

# --- AI-04a: UFW deny rule for port 11434 (defense-in-depth per ADR-E02) ---
echo "[AI-04a] UFW deny rule for port 11434 (ADR-E02 defense-in-depth)"

AI04A_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" \
  "sudo ufw status 2>/dev/null | grep -q '11434' && echo 'ACTIVE_RULE' || (sudo grep -q '11434' /etc/ufw/user.rules 2>/dev/null && echo 'SAVED_RULE' || echo 'NO_RULE')" 2>/dev/null)
AI04A_EXIT=$?

if [ $AI04A_EXIT -ne 0 ] || [ -z "$AI04A_OUT" ]; then
  fail "AI-04a: Cannot check UFW rules on supportTAK-server"
elif echo "$AI04A_OUT" | grep -q "ACTIVE_RULE"; then
  pass "AI-04a: UFW deny rule for port 11434 is active (defense-in-depth enforced)"
elif echo "$AI04A_OUT" | grep -q "SAVED_RULE"; then
  pass "AI-04a: UFW deny rule for port 11434 exists in config (UFW inactive but rule saved; primary control is 127.0.0.1 binding)"
else
  fail "AI-04a: UFW deny rule for port 11434 not found. Add: sudo ufw deny 11434. Note: primary ADR-E02 control is OLLAMA_HOST=127.0.0.1; UFW is defense-in-depth."
fi
echo ""

# --- AI-01c: Foundation-Sec-8B model available ---
echo "[AI-01c] Foundation-Sec-8B Q4_K_M model available in ollama list"

AI01C_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" \
  "ollama list 2>/dev/null | grep -q 'Foundation-Sec' && echo 'FOUND' || echo 'NOT_FOUND'" 2>/dev/null)
AI01C_EXIT=$?

if [ $AI01C_EXIT -ne 0 ] || [ -z "$AI01C_OUT" ]; then
  fail "AI-01c: Cannot check ollama list on supportTAK-server. Verify Ollama is running."
elif echo "$AI01C_OUT" | grep -q "FOUND"; then
  pass "AI-01c: Foundation-Sec-8B Q4_K_M model found in ollama list"
else
  fail "AI-01c: Foundation-Sec-8B model NOT found. Pull: ollama pull hf.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF (requires ~4.9GB download)"
fi
echo ""

# --- AI-04b: RAM check (Malcolm + Ollama simultaneous load) ---
echo "[AI-04b] RAM usage check (Malcolm steady-state < 14GB to allow AI triage)"

AI04B_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" \
  "free -m | awk '/Mem:/{print \$3}'" 2>/dev/null)
AI04B_EXIT=$?

if [ $AI04B_EXIT -ne 0 ] || [ -z "$AI04B_OUT" ]; then
  skip "AI-04b: Cannot check RAM on supportTAK-server"
else
  MEM_USED="$AI04B_OUT"
  if [ -n "$MEM_USED" ] && [ "$MEM_USED" -lt 12000 ] 2>/dev/null; then
    pass "AI-04b: RAM used = ${MEM_USED}MB (Malcolm only — within safe range for AI triage)"
  elif [ -n "$MEM_USED" ] && [ "$MEM_USED" -lt 14000 ] 2>/dev/null; then
    pass "AI-04b: RAM used = ${MEM_USED}MB (WARN: above 12GB — temporal separation required for AI triage; monitor for OOM during simultaneous load)"
  elif [ -n "$MEM_USED" ] && [ "$MEM_USED" -lt 15500 ] 2>/dev/null; then
    pass "AI-04b: RAM used = ${MEM_USED}MB (WARN: above 14GB — this includes Foundation-Sec-8B loaded; swap active; OLLAMA_KEEP_ALIVE=5m ensures model unloads after idle)"
  elif [ -n "$MEM_USED" ]; then
    fail "AI-04b: RAM used = ${MEM_USED}MB exceeds 15500MB threshold. Temporal separation MANDATORY — do not run AI triage during Malcolm indexing peaks. Check: sudo dmesg | grep -i oom"
  else
    skip "AI-04b: Could not parse RAM usage from free -m output"
  fi
fi
echo ""

# --- Full mode checks ---

if [ "$FULL" -eq 1 ]; then

  # --- AI-01d: Model responds to security query ---
  echo "[AI-01d] Foundation-Sec-8B responds to security query (temporal separation may be required)"

  AI01D_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" \
    "ollama run '$MODEL_NAME' 'What is XSS?' 2>&1 | head -c 100" 2>/dev/null)
  AI01D_EXIT=$?

  if [ $AI01D_EXIT -ne 0 ]; then
    skip "AI-01d: Cannot test model response on supportTAK-server"
  elif echo "$AI01D_OUT" | grep -q "more system memory\|cannot allocate"; then
    fail "AI-01d: Model cannot load — insufficient RAM. Apply temporal separation: temporarily stop Malcolm's OpenSearch/Logstash containers before running AI triage. This is expected behavior per the temporal separation policy (STATE.md). Command: sudo docker stop malcolm-opensearch-1 malcolm-logstash-1"
  elif [ -n "$AI01D_OUT" ] && ! echo "$AI01D_OUT" | grep -q "Error"; then
    pass "AI-01d: Foundation-Sec-8B responded to security query (first 100 chars): ${AI01D_OUT:0:100}"
  else
    fail "AI-01d: Model did not produce expected response. Output: $AI01D_OUT. Check: ssh $SSH_TARGET 'ollama run $MODEL_NAME \"What is XSS?\"'"
  fi
  echo ""

  # --- AI-03: External access blocked from LAN (ADR-E02 verification) ---
  echo "[AI-03] External LAN access to Ollama API blocked (ADR-E02 gate)"

  AI03_OUT=$(ssh $SSH_OPTS "$SSH_TARGET" \
    "curl -s -m 3 http://192.168.1.22:11434/api/version 2>&1 || echo 'CONNECTION_REFUSED'" 2>/dev/null)
  AI03_EXIT=$?

  if [ $AI03_EXIT -ne 0 ]; then
    skip "AI-03: Cannot verify external access from supportTAK-server (SSH issue)"
  elif echo "$AI03_OUT" | grep -q "CONNECTION_REFUSED\|connection refused\|Failed to connect"; then
    pass "AI-03: LAN access to Ollama API correctly refused — ADR-E02 verified from server itself"
  elif echo "$AI03_OUT" | grep -q "version"; then
    fail "AI-03: ADR-E02 VIOLATION: Ollama API is accessible from LAN IP 192.168.1.22 — binding is not restricted to localhost"
  else
    skip "AI-03: Unexpected response from LAN access check: $AI03_OUT"
  fi
  echo ""

fi

if [ "$FULL" -eq 0 ]; then
  echo "[AI-01d] Model response test — SKIPPED in quick mode (run with --full to include)"
  skip "AI-01d: Model response test — run with --full flag"
  echo ""
fi

# --- Summary ---
echo "=== Phase 11 Validation Summary ==="
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo ""
if [ $FAIL -gt 0 ]; then
  echo "=== FAILED: $FAIL check(s) require attention ==="
  if grep -q "ADR-E02 VIOLATION" <<< "$(cat /dev/null)" 2>/dev/null || [ $FAIL -gt 0 ]; then
    echo "IMPORTANT: If binding check failed, this is a CRITICAL security violation (ADR-E02)."
    echo "           Ollama must never bind to 0.0.0.0 — any GREEN device could access the LLM API."
  fi
  exit $FAIL
else
  echo "=== ALL CHECKS PASS ($SKIP skipped) ==="
  exit 0
fi
