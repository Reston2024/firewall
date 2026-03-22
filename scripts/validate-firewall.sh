#!/bin/bash
# validate-firewall.sh — Automated firewall configuration checks
# Usage: bash /root/firewall-repo/scripts/validate-firewall.sh
# Exits: 0 if all automated checks pass, 1 if any fail
#
# Covers automated-verifiable aspects of: FW-05, FW-06, FW-07, PLAT-02
# The following require manual verification from external hosts (see docs/zone-policy-runbook.md):
#   FW-01: nmap from external against WAN IP
#   FW-02: curl checkip.amazonaws.com from GREEN/ORANGE/BLUE hosts
#   FW-03: ping from GREEN to ORANGE (must timeout)
#   FW-04: curl to DNAT port from external host
#
# Run this script from the IPFire appliance (not from the dev machine).

FAIL=0
PASS=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "SKIP: $1"; }

echo "=== Firewall Validation — $(date) ==="
echo ""

# --- FW-07 / PLAT-02: CUSTOMINPUT anti-lockout rules ---
echo "[FW-07/PLAT-02] CUSTOMINPUT anti-lockout rules"

if iptables -L CUSTOMINPUT -n -v 2>/dev/null | grep -q "dpt:22"; then
  pass "SSH port 22 ACCEPT rule present in CUSTOMINPUT"
else
  fail "SSH port 22 ACCEPT rule MISSING from CUSTOMINPUT"
  echo "  Fix: deploy configs/firewall/firewall.local to /etc/sysconfig/firewall.local"
  echo "       then run: /etc/init.d/firewall restart"
fi

if iptables -L CUSTOMINPUT -n -v 2>/dev/null | grep -q "dpt:444"; then
  pass "WUI port 444 ACCEPT rule present in CUSTOMINPUT"
else
  fail "WUI port 444 ACCEPT rule MISSING from CUSTOMINPUT"
  echo "  Fix: deploy configs/firewall/firewall.local then: /etc/init.d/firewall restart"
fi
echo ""

# --- FW-07 / PLAT-02: firewall.local file exists and is executable ---
echo "[FW-07/PLAT-02] firewall.local file"

if [ -f "/etc/sysconfig/firewall.local" ]; then
  pass "firewall.local exists at /etc/sysconfig/firewall.local"
else
  fail "firewall.local MISSING at /etc/sysconfig/firewall.local"
  echo "  Fix: scp configs/firewall/firewall.local root@IPFIRE:/etc/sysconfig/"
fi

if [ -x "/etc/sysconfig/firewall.local" ]; then
  pass "firewall.local is executable"
else
  fail "firewall.local is NOT executable"
  echo "  Fix: chmod +x /etc/sysconfig/firewall.local"
fi
echo ""

# --- FW-05: Drop logging active in /var/log/messages ---
echo "[FW-05] Drop logging"

if grep -qE '(FORWARDFW|DROP_INPUT|DROP_NEWNOTSYN|DROP_CTINVALID)' /var/log/messages 2>/dev/null; then
  ENTRY_COUNT=$(grep -cE '(FORWARDFW|DROP_INPUT|DROP_NEWNOTSYN|DROP_CTINVALID)' /var/log/messages 2>/dev/null || echo 0)
  pass "Firewall log entries found in /var/log/messages (${ENTRY_COUNT} entries)"
else
  skip "FW-05: No firewall log entries in /var/log/messages yet"
  echo "  To verify: trigger a blocked connection, then re-run this script"
  echo "  Enable logging: WUI > Firewall > Firewall Options > Log dropped packets"
fi
echo ""

# --- FW-06: Firewall init script exists (persistence mechanism) ---
echo "[FW-06] Firewall persistence mechanism"

if [ -f "/etc/init.d/firewall" ]; then
  pass "IPFire firewall init script exists at /etc/init.d/firewall"
else
  fail "/etc/init.d/firewall MISSING — firewall persistence compromised"
fi

# Check that the firewall service is in the default runlevel
if ls /etc/rc3.d/S*firewall 2>/dev/null | grep -q firewall; then
  pass "Firewall service is in default runlevel (rc3.d)"
else
  # On IPFire, runlevels may differ — check rc.d or systemd-like init
  if ls /etc/rc.d/rc3.d/S*firewall 2>/dev/null | grep -q firewall || \
     ls /etc/runlevels/default/firewall 2>/dev/null | grep -q firewall; then
    pass "Firewall service is in default runlevel"
  else
    skip "FW-06: Cannot confirm firewall runlevel symlink — verify reboot persistence manually"
  fi
fi
echo ""

# --- WUI-managed rules summary ---
echo "[INFO] WUI-managed rule counts (informational)"
FORWARD_RULES=$(iptables -L FORWARDFW -n 2>/dev/null | grep -c "^[A-Z]" || echo 0)
INPUT_RULES=$(iptables -L INPUT -n 2>/dev/null | grep -c "^[A-Z]" || echo 0)
echo "INFO: FORWARDFW chain rule count: ${FORWARD_RULES}"
echo "INFO: INPUT chain rule count: ${INPUT_RULES}"
echo ""

# --- Masquerade check (informational only — requires zone knowledge) ---
echo "[INFO] Masquerade / NAT rules (informational)"
if iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -q MASQUERADE; then
  MASQ_COUNT=$(iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -c MASQUERADE || echo 0)
  echo "INFO: ${MASQ_COUNT} MASQUERADE rule(s) active in nat POSTROUTING"
  echo "      Verify: GREEN, ORANGE, and BLUE zones should each have a rule"
else
  echo "INFO: No MASQUERADE rules found — verify via WUI: Firewall > Masquerade"
fi
echo ""

# --- Summary ---
echo "=== Results: ${PASS} pass, ${FAIL} fail ==="
if [ "$FAIL" -eq 0 ]; then
  echo "FIREWALL CHECKS PASS"
  echo ""
  echo "Manual verifications still required (see docs/zone-policy-runbook.md):"
  echo "  FW-01: nmap from external against WAN IP — all ports must be filtered"
  echo "  FW-02: curl checkip.amazonaws.com from GREEN/ORANGE/BLUE clients"
  echo "  FW-03: ping ORANGE_IP from GREEN client — must timeout"
  echo "  FW-04: curl to DNAT port from external client"
  exit 0
else
  echo "FIREWALL VALIDATION FAILED — resolve failures above"
  exit 1
fi
