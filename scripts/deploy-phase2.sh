#!/bin/bash
# deploy-phase2.sh — Deploy Phase 2 configs to IPFire
# Phase 2: Core Network Services
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

echo "=== deploy-phase2.sh — Core Network Services === $(date)"

# --- DHCP config (WUI-managed primary; repo has reference copy) ---
if [ -f "$REPO/configs/dhcp/dhcpd.conf.local" ]; then
  backup_and_copy "$REPO/configs/dhcp/dhcpd.conf.local" \
    "/var/ipfire/dhcp/dhcpd.conf.local" "dhcp"
  pass "DHCP config deployed: /var/ipfire/dhcp/dhcpd.conf.local"
else
  echo "SKIP: $REPO/configs/dhcp/dhcpd.conf.local not in repo — DHCP is WUI-managed"
  echo "NOTE: Configure DHCP server settings via WUI > Network > DHCP Server"
fi

# --- DNS forward.conf ---
if [ -f "$REPO/configs/dns/forward.conf" ]; then
  backup_and_copy "$REPO/configs/dns/forward.conf" \
    "/var/ipfire/dns/forward.conf" "dns"
  pass "DNS forward.conf deployed: /var/ipfire/dns/forward.conf"
else
  fail "forward.conf not found: $REPO/configs/dns/forward.conf"
fi

# --- Reload DNS ---
/etc/init.d/unbound restart >/dev/null 2>&1
if [ $? -eq 0 ]; then
  pass "Unbound (DNS resolver) restarted"
else
  fail "Unbound restart failed"
fi

echo ""
echo "NOTE: DHCP server settings, NTP settings, and DNS resolver settings are WUI-managed"
echo "      Configure via WUI > Network > DHCP Server and WUI > Network > DNS Settings"
echo ""
echo "=== Phase 2 complete: $PASS pass, $FAIL fail ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
