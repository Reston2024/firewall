#!/bin/bash
# deploy-phase3.sh — Deploy Phase 3 configs to IPFire
# Phase 3: SSH Hardening
# Run ON IPFire (called by rebuild.sh via SSH)
# Per D-05: All operations are idempotent (safe to re-run)
# Per D-09: Creates /root/rollback/{category}-{timestamp}.bak before overwriting
#
# NOTE: sshd_config is managed by sshctrl (IPFire WUI binary).
#       The repo contains sshd_config.hardened as a REFERENCE ONLY.
#       DO NOT copy sshd_config.hardened to /etc/ssh/sshd_config — it would
#       be overwritten by WUI saves and could break SSH access.
#       Configure SSH via WUI > System > SSH Access.

REPO="/root/firewall-repo"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== deploy-phase3.sh — SSH Hardening === $(date)"

# --- firewall.local already deployed in Phase 1 ---
# firewall.local contains both Phase 1 anti-lockout rules and Phase 3
# management-host-specific rules in a single combined file.
if [ -f "/etc/sysconfig/firewall.local" ]; then
  pass "firewall.local management restrictions already deployed (Phase 1)"
else
  fail "firewall.local not found at /etc/sysconfig/firewall.local — run Phase 1 first"
fi

echo ""
echo "NOTE: SSH key-only auth and port config are WUI-managed"
echo "      Configure via WUI > System > SSH Access:"
echo "        - Enable SSH: Yes"
echo "        - Allow password-based authentication: No"
echo "        - Allow public key authentication: Yes"
echo "        - Allow SSH logins for root: Yes"
echo ""
echo "NOTE: sshd_config.hardened is a REFERENCE only — sshctrl binary manages sshd_config"
echo "      Direct edits to /etc/ssh/sshd_config are overwritten on WUI saves"
echo "      Review $REPO/configs/ssh/sshd_config.hardened for expected hardening settings"
echo ""
echo "NOTE: firewall.local management restrictions already deployed in Phase 1"
echo "      Phase 3 management-host-specific rules are included in the same firewall.local"
echo ""
echo "=== Phase 3 complete: $PASS pass, $FAIL fail ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
