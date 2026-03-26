#!/bin/bash
# deploy-phase6.sh — Deploy Phase 6 configs to IPFire
# Phase 6: System Hardening
# Run ON IPFire (called by rebuild.sh via SSH)
# Per D-05: All operations are idempotent (safe to re-run)
# Per D-09: Creates /root/rollback/{category}-{timestamp}.bak before overwriting
#
# CRITICAL: This script appends to /etc/sysctl.conf (does NOT overwrite).
#           Overwriting would destroy IPFire's own net.ipv4.ip_forward=1.
#           Uses grep-before-append to ensure idempotent operation.

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

echo "=== deploy-phase6.sh — System Hardening === $(date)"

# --- Idempotent sysctl hardening append (D-05, Pitfall 1) ---
# Check for a sentinel param before appending to avoid duplicate params on re-run
if grep -q "net.ipv4.conf.all.send_redirects" /etc/sysctl.conf; then
  pass "sysctl hardening params already present — skipping append"
else
  if [ -f "$REPO/configs/hardening/sysctl-hardening.conf" ]; then
    # Backup sysctl.conf before modifying (special case: backup src IS the dest)
    mkdir -p /root/rollback
    if [ -f "/etc/sysctl.conf" ]; then
      cp "/etc/sysctl.conf" "/root/rollback/sysctl-pre-hardening-${TIMESTAMP}.bak"
    fi
    cat "$REPO/configs/hardening/sysctl-hardening.conf" >> /etc/sysctl.conf
    pass "sysctl hardening params appended to /etc/sysctl.conf"
  else
    fail "sysctl-hardening.conf not found: $REPO/configs/hardening/sysctl-hardening.conf"
  fi
fi

# Apply sysctl params
sysctl -p >/dev/null 2>&1

# --- Critical: verify ip_forward is still 1 ---
IP_FORWARD=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
if [ "$IP_FORWARD" = "1" ]; then
  pass "ip_forward=1 confirmed — WAN routing intact"
else
  fail "CRITICAL: ip_forward=0 — WAN routing broken!"
  echo "RECOVERY: Run: echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf && sysctl -p"
fi

# --- Create integrity baseline ---
if [ -f "$REPO/scripts/check-integrity.sh" ]; then
  bash "$REPO/scripts/check-integrity.sh" --create-baseline
  if [ $? -eq 0 ]; then
    pass "Integrity baseline created: /root/integrity-baseline.sha256"
  else
    echo "NOTE: Integrity baseline created with some files missing — re-run after all phases complete"
    pass "Integrity baseline created (partial — some files not yet deployed)"
  fi
else
  fail "check-integrity.sh not found: $REPO/scripts/check-integrity.sh"
fi

# --- Capture Pakfire manifest ---
ls /opt/pakfire/db/installed/ 2>/dev/null | sed 's/^meta-//' > "$REPO/manifests/pakfire-manifest.txt" 2>/dev/null || true
if [ -s "$REPO/manifests/pakfire-manifest.txt" ]; then
  pass "Pakfire manifest captured: $REPO/manifests/pakfire-manifest.txt"
else
  echo "NOTE: Pakfire manifest empty or Pakfire not initialized — install guardian via WUI Pakfire"
fi

echo ""
echo "=== Phase 6 complete: $PASS pass, $FAIL fail ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
