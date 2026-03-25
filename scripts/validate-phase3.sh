#!/bin/bash
# validate-phase3.sh — Phase 3 SSH Hardening and Management Security validation
# Usage: bash /root/firewall-repo/scripts/validate-phase3.sh
# Run on IPFire appliance (not dev machine)
# Exits: 0 if all automated checks pass, 1 if any fail

FAIL=0
PASS=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "SKIP: $1 (manual verification required)"; }

echo "=== Phase 3 Validation Suite — $(date) ==="
echo ""

# --- SSH-01: Key-only authentication enforced ---
echo "[SSH-01] Key-only authentication enforced"
if grep -E "PasswordAuthentication no" /etc/ssh/sshd_config >/dev/null 2>&1; then
  pass "SSH-01: PasswordAuthentication no found in sshd_config"
else
  fail "SSH-01: PasswordAuthentication no NOT found — uncheck 'Allow password based authentication' in WUI: System > SSH Access"
fi

if grep -E "PubkeyAuthentication yes" /etc/ssh/sshd_config >/dev/null 2>&1; then
  pass "SSH-01: PubkeyAuthentication yes found in sshd_config"
else
  fail "SSH-01: PubkeyAuthentication yes NOT found — check 'Allow public key based authentication' in WUI: System > SSH Access"
fi

if grep -E "^Port 22" /etc/ssh/sshd_config >/dev/null 2>&1; then
  pass "SSH-01: Port 22 confirmed in sshd_config"
else
  fail "SSH-01: Port 22 NOT found — confirm SSH port is 22 in WUI: System > SSH Access"
fi

if ls /root/.ssh/authorized_keys >/dev/null 2>&1; then
  pass "SSH-01: /root/.ssh/authorized_keys exists"
else
  fail "SSH-01: /root/.ssh/authorized_keys does NOT exist — deploy public key before disabling password auth"
fi

AUTH_KEYS_PERMS=$(stat -c "%a" /root/.ssh/authorized_keys 2>/dev/null)
if [ "$AUTH_KEYS_PERMS" = "600" ]; then
  pass "SSH-01: authorized_keys permissions are 600"
else
  fail "SSH-01: authorized_keys permissions are ${AUTH_KEYS_PERMS} (expected 600) — run: chmod 600 /root/.ssh/authorized_keys"
fi

SSH_DIR_PERMS=$(stat -c "%a" /root/.ssh 2>/dev/null)
if [ "$SSH_DIR_PERMS" = "700" ]; then
  pass "SSH-01: /root/.ssh directory permissions are 700"
else
  fail "SSH-01: /root/.ssh directory permissions are ${SSH_DIR_PERMS} (expected 700) — run: chmod 700 /root/.ssh"
fi

skip "SSH-01: Live key-login test must be run from management host: ssh -i ~/.ssh/ipfire_ed25519 -o PasswordAuthentication=no root@192.168.1.1"
echo ""

# --- SSH-02: SSH access restricted to management subnet ---
echo "[SSH-02] SSH access restricted to management subnet"
RULES=$(iptables -L CUSTOMINPUT -n 2>/dev/null)

if echo "$RULES" | grep "dpt:22" | grep -q "ACCEPT"; then
  pass "SSH-02: CUSTOMINPUT has ACCEPT rule for port 22 (management host allow rule present)"
else
  fail "SSH-02: CUSTOMINPUT has NO ACCEPT rule for port 22 — deploy updated firewall.local"
fi

. /var/ipfire/ethernet/settings 2>/dev/null
HAVE_ORANGE="${ORANGE_DEV:-}"
HAVE_BLUE="${BLUE_DEV:-}"

if echo "$RULES" | grep "dpt:22" | grep -q "DROP"; then
  pass "SSH-02: CUSTOMINPUT has DROP rule for port 22 (non-management zones blocked)"
elif [ -z "$HAVE_ORANGE" ] && [ -z "$HAVE_BLUE" ]; then
  pass "SSH-02: No ORANGE/BLUE zones configured — DROP rules not needed (firewall.local will activate them when zones are added)"
elif grep -q 'ORANGE_DEV.*DROP.*dpt.*22\|BLUE_DEV.*DROP.*dpt.*22' /etc/sysconfig/firewall.local 2>/dev/null; then
  pass "SSH-02: DROP rules present in firewall.local — will activate when ORANGE/BLUE zones are configured"
else
  fail "SSH-02: CUSTOMINPUT has NO DROP rules for port 22 — ORANGE/BLUE zone restrictions not applied"
fi

skip "SSH-02: Live test requires host on ORANGE or BLUE zone — attempt SSH from non-GREEN host"
echo ""

# --- SSH-03: Guardian installed and running ---
echo "[SSH-03] Guardian installed and running"
if which guardian >/dev/null 2>&1 || test -f /usr/sbin/guardian; then
  pass "SSH-03: Guardian binary found — Guardian is installed"
else
  fail "SSH-03: Guardian NOT installed — run: pakfire install guardian"
fi

if /etc/init.d/guardian status 2>/dev/null | grep -qi "running\|started"; then
  pass "SSH-03: Guardian service is running"
else
  fail "SSH-03: Guardian service is NOT running — enable Guardian in WUI: System > Guardian"
fi

if test -f /var/log/guardian/guardian.log; then
  pass "SSH-03: Guardian log file exists at /var/log/guardian/guardian.log"
else
  fail "SSH-03: Guardian log file does NOT exist — Guardian may not have started yet"
fi

if test -f /var/ipfire/guardian/guardian.conf; then
  pass "SSH-03: Guardian config exists at /var/ipfire/guardian/guardian.conf"
else
  fail "SSH-03: Guardian config does NOT exist — configure Guardian in WUI: System > Guardian"
fi

if grep -q "192.168.1.100\|192.168.1.0/24" /var/ipfire/guardian/guardian.conf /var/ipfire/guardian/ignored 2>/dev/null; then
  pass "SSH-03: Management host (192.168.1.100) is in Guardian ignore list — lockout prevention confirmed"
else
  fail "SSH-03: Management host NOT in Guardian ignore list — CRITICAL: add 192.168.1.100 to Guardian ignored hosts (WUI: System > Guardian)"
fi

skip "SSH-03: Brute-force block test requires simulated failed logins from non-whitelisted host"
echo ""

# --- SSH-04: WUI access restricted (ORANGE/BLUE blocked on port 444) ---
echo "[SSH-04] WUI access restricted (ORANGE/BLUE blocked on port 444)"
if echo "$RULES" | grep "dpt:444" | grep -q "ACCEPT"; then
  pass "SSH-04: CUSTOMINPUT has ACCEPT rule for port 444 (management host WUI allow rule present)"
else
  fail "SSH-04: CUSTOMINPUT has NO ACCEPT rule for port 444 — deploy updated firewall.local"
fi

if echo "$RULES" | grep "dpt:444" | grep -q "DROP"; then
  pass "SSH-04: CUSTOMINPUT has DROP rule for port 444 (non-management zones blocked from WUI)"
elif [ -z "$HAVE_ORANGE" ] && [ -z "$HAVE_BLUE" ]; then
  pass "SSH-04: No ORANGE/BLUE zones configured — DROP rules not needed (firewall.local will activate them when zones are added)"
elif grep -q 'ORANGE_DEV.*DROP.*dpt.*444\|BLUE_DEV.*DROP.*dpt.*444' /etc/sysconfig/firewall.local 2>/dev/null; then
  pass "SSH-04: DROP rules present in firewall.local — will activate when ORANGE/BLUE zones are configured"
else
  fail "SSH-04: CUSTOMINPUT has NO DROP rules for port 444 — ORANGE/BLUE WUI restrictions not applied"
fi

skip "SSH-04: Live test from ORANGE/BLUE zone required — attempt https://192.168.1.1:444 from non-GREEN host"
echo ""

# --- SSH-05: SSH 15-minute expiry documented ---
echo "[SSH-05] SSH 15-minute expiry documented"
if test -f /root/firewall-repo/docs/ssh-management-runbook.md; then
  pass "SSH-05: ssh-management-runbook.md exists at /root/firewall-repo/docs/"
else
  fail "SSH-05: ssh-management-runbook.md does NOT exist — deploy docs from repo to /root/firewall-repo/docs/"
fi

if grep -q "15.min\|15-min\|15 min" /root/firewall-repo/docs/ssh-management-runbook.md 2>/dev/null; then
  pass "SSH-05: 15-minute expiry mode is documented in the runbook"
else
  fail "SSH-05: 15-minute expiry mode NOT documented in runbook — check docs/ssh-management-runbook.md"
fi

skip "SSH-05: 15-minute expiry functional test is manual — click 'Stop SSH Daemon in 15 minutes' in WUI, wait 15 min, confirm sshd stops while existing session remains"
echo ""

# --- Summary ---
echo "=== Results: ${PASS} pass, ${FAIL} fail ==="
if [ "$FAIL" -eq 0 ]; then
  echo "ALL CHECKS PASS"
  exit 0
else
  echo "PHASE 3 VALIDATION FAILED — resolve failures above"
  exit 1
fi
