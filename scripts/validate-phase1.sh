#!/bin/bash
# validate-phase1.sh — Full Phase 1 integration test suite
# Usage: bash /root/firewall-repo/scripts/validate-phase1.sh
# Exits: 0 if all checks pass, 1 if any fail
# Runtime: ~15 seconds (excluding reboot persistence test)
#
# Run this script from the IPFire appliance (not from the dev machine).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAIL=0
PASS=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "SKIP: $1 (manual verification required)"; }

echo "=== Phase 1 Validation Suite — $(date) ==="
echo ""

# --- PLAT-01: NIC MAC-to-zone mapping ---
echo "[PLAT-01] NIC MAC-to-zone mapping"
if bash "${SCRIPT_DIR}/validate-nics.sh" > /tmp/nic-validate-output.txt 2>&1; then
  pass "All NIC MACs match expected zone assignments"
else
  fail "NIC validation failed — see /tmp/nic-validate-output.txt"
  cat /tmp/nic-validate-output.txt
fi
echo ""

# --- PLAT-02 / FW-07: Anti-lockout rules in CUSTOMINPUT ---
echo "[PLAT-02/FW-07] CUSTOMINPUT anti-lockout rules"
if iptables -L CUSTOMINPUT -n -v 2>/dev/null | grep -q ":22 "; then
  pass "SSH (port 22) ACCEPT rule present in CUSTOMINPUT"
else
  fail "SSH (port 22) ACCEPT rule MISSING from CUSTOMINPUT — run: /etc/init.d/firewall restart"
fi

if iptables -L CUSTOMINPUT -n -v 2>/dev/null | grep -q ":444 "; then
  pass "WUI (port 444) ACCEPT rule present in CUSTOMINPUT"
else
  fail "WUI (port 444) ACCEPT rule MISSING from CUSTOMINPUT — run: /etc/init.d/firewall restart"
fi
echo ""

# --- PLAT-03: Repo directory structure ---
echo "[PLAT-03] Git repository structure"
REPO_BASE="/root/firewall-repo"
for dir in configs/udev configs/ethernet configs/firewall scripts docs services validation rollback manifests decision-log; do
  if [ -d "${REPO_BASE}/${dir}" ]; then
    pass "Directory exists: ${dir}"
  else
    fail "Directory MISSING: ${REPO_BASE}/${dir}"
  fi
done
echo ""

# --- PLAT-05: Backup include list ---
echo "[PLAT-05] Backup include list"
INCLUDE_FILE="/var/ipfire/backup/include.user"
if grep -q "/etc/udev/rules.d/30-persistent-network.rules" "$INCLUDE_FILE" 2>/dev/null; then
  pass "udev rules path present in include.user"
else
  fail "udev rules path MISSING from ${INCLUDE_FILE}"
fi

if grep -q "/etc/sysconfig/firewall.local" "$INCLUDE_FILE" 2>/dev/null; then
  pass "firewall.local path present in include.user"
else
  fail "firewall.local path MISSING from ${INCLUDE_FILE}"
fi
echo ""

# --- FW-05: Drop logging active ---
echo "[FW-05] Firewall drop logging"
if grep -qE '(DROP|FORWARDFW)' /var/log/messages 2>/dev/null; then
  pass "Firewall log entries found in /var/log/messages (DROP/FORWARDFW prefix)"
else
  skip "FW-05: No drop log entries yet — trigger a blocked connection then re-run, OR enable logging via WUI Firewall Options"
fi
echo ""

# --- FW-07: firewall.local file exists ---
echo "[FW-07] firewall.local file"
if [ -f "/etc/sysconfig/firewall.local" ]; then
  pass "firewall.local exists at /etc/sysconfig/firewall.local"
else
  fail "firewall.local MISSING at /etc/sysconfig/firewall.local"
fi

if [ -x "/etc/sysconfig/firewall.local" ]; then
  pass "firewall.local is executable"
else
  fail "firewall.local is NOT executable — run: chmod +x /etc/sysconfig/firewall.local"
fi
echo ""

# --- Manual-only checks (not automated) ---
echo "[MANUAL] The following require external test hosts:"
skip "FW-01: Inbound from RED blocked — nmap from external against RED IP"
skip "FW-02: GREEN reaches internet — curl checkip.amazonaws.com from GREEN host"
skip "FW-03: GREEN cannot reach ORANGE — ping ORANGE IP from GREEN host (must timeout)"
skip "PLAT-04: Hostname/timezone/updates — check hostname and date on console"
echo ""

# --- Summary ---
echo "=== Results: ${PASS} pass, ${FAIL} fail ==="
if [ "$FAIL" -eq 0 ]; then
  echo "ALL CHECKS PASS"
  exit 0
else
  echo "PHASE 1 VALIDATION FAILED — resolve failures above"
  exit 1
fi
