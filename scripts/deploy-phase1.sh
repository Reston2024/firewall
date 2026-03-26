#!/bin/bash
# deploy-phase1.sh — Deploy Phase 1 configs to IPFire
# Phase 1: Platform Foundation
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

echo "=== deploy-phase1.sh — Platform Foundation === $(date)"

# --- udev NIC persistence rules ---
if [ -f "$REPO/configs/udev/30-persistent-network.rules" ]; then
  backup_and_copy "$REPO/configs/udev/30-persistent-network.rules" \
    "/etc/udev/rules.d/30-persistent-network.rules" "zone"
  pass "udev rules deployed: /etc/udev/rules.d/30-persistent-network.rules"
  echo "NOTE: NIC-to-zone assignment requires reboot if udev rules changed"
else
  fail "udev rules not found: $REPO/configs/udev/30-persistent-network.rules"
fi

# --- firewall.local ---
if [ -f "$REPO/configs/firewall/firewall.local" ]; then
  backup_and_copy "$REPO/configs/firewall/firewall.local" \
    "/etc/sysconfig/firewall.local" "firewall"
  chmod 755 /etc/sysconfig/firewall.local
  pass "firewall.local deployed: /etc/sysconfig/firewall.local"
else
  fail "firewall.local not found: $REPO/configs/firewall/firewall.local"
fi

# --- backup include list ---
if [ -f "$REPO/configs/firewall/backup-include.user" ]; then
  backup_and_copy "$REPO/configs/firewall/backup-include.user" \
    "/var/ipfire/backup/include.user" "backup-include"
  pass "backup include list deployed: /var/ipfire/backup/include.user"
else
  fail "backup-include.user not found: $REPO/configs/firewall/backup-include.user"
fi

# --- Reload firewall ---
/etc/init.d/firewall restart >/dev/null 2>&1
if iptables -L CUSTOMINPUT -n >/dev/null 2>&1; then
  pass "firewall.local loaded — CUSTOMINPUT chain present"
else
  fail "firewall.local failed to load — CUSTOMINPUT chain missing"
fi

echo ""
echo "=== Phase 1 complete: $PASS pass, $FAIL fail ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
