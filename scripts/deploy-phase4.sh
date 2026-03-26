#!/bin/bash
# deploy-phase4.sh — Deploy Phase 4 configs to IPFire
# Phase 4: Suricata IDS/IPS
# Run ON IPFire (called by rebuild.sh via SSH)
# Per D-05: All operations are idempotent (safe to re-run)
# Per D-09: Creates /root/rollback/{category}-{timestamp}.bak before overwriting

REPO="/root/firewall-repo"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

backup_and_copy() {
  local SRC="$1"
  local DEST="$2"
  local CATEGORY="$3"
  mkdir -p /root/rollback
  if [ -f "$DEST" ]; then
    cp "$DEST" "/root/rollback/${CATEGORY}-${TIMESTAMP}.bak"
  fi
  cp "$SRC" "$DEST"
}

echo "=== deploy-phase4.sh — Suricata IDS/IPS === $(date)"

# --- Suricata config ---
if [ -f "$REPO/configs/suricata/suricata.yaml" ]; then
  backup_and_copy "$REPO/configs/suricata/suricata.yaml" \
    "/etc/suricata/suricata.yaml" "suricata"
  pass "suricata.yaml deployed: /etc/suricata/suricata.yaml"
else
  fail "suricata.yaml not found: $REPO/configs/suricata/suricata.yaml"
fi

# --- Restart Suricata (only if service exists — WUI must enable IPS first) ---
if [ -f "/etc/init.d/suricata" ]; then
  /etc/init.d/suricata restart >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    pass "Suricata restarted"
  else
    fail "Suricata restart failed — check /var/log/suricata/suricata.log"
  fi
else
  fail "Suricata service not found — enable IPS via WUI first"
  echo "NOTE: After enabling IPS in WUI, re-run this script to deploy suricata.yaml"
fi

echo ""
echo "NOTE: IPS mode (monitor/active), zone selection, and ruleset selection are WUI-managed"
echo "      Configure via WUI > Intrusion Prevention System:"
echo "        - Enable: Yes"
echo "        - Interfaces: RED + GREEN"
echo "        - Ruleset: Emerging Threats Community"
echo "        - Mode: Monitor only (until tuning complete)"
echo ""
echo "=== Phase 4 complete: $PASS pass, $FAIL fail ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
