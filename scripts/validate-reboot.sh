#!/bin/bash
# Reboot persistence validator — pre/post reboot state snapshot and comparison
# Deploy to: /usr/local/bin/validate-reboot.sh on IPFire
# Usage:
#   bash validate-reboot.sh --snapshot    Capture pre-reboot state to snapshot file
#   bash validate-reboot.sh --compare     Compare current state against stored snapshot
#
# Exit codes (--compare mode): 0=identical, 1=state changed
#
# Workflow:
#   1. bash validate-reboot.sh --snapshot
#   2. reboot
#   3. bash validate-reboot.sh --compare
#
# Purpose: Verify that sysctl hardening, iptables rules, listening services,
# and config file hashes survive a system reboot (D-15, D-16, D-17).
# NOTE: This script does NOT trigger a reboot — reboot is manual only.

SNAPSHOT_FILE="/root/reboot-snapshot.txt"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# Sysctl parameters from sysctl-hardening.conf — must survive reboot
SYSCTL_PARAMS=(
  net.ipv4.conf.all.send_redirects
  net.ipv4.conf.default.send_redirects
  net.ipv4.conf.all.accept_source_route
  net.ipv4.conf.default.accept_source_route
  net.ipv4.conf.all.accept_redirects
  net.ipv4.conf.default.accept_redirects
  net.ipv4.conf.all.rp_filter
  net.ipv4.conf.default.rp_filter
  net.ipv4.tcp_syncookies
  net.ipv6.conf.all.accept_redirects
  net.ipv6.conf.default.accept_redirects
)

# Config files to hash for persistence check
MONITORED_FILES=(
  /etc/udev/rules.d/30-persistent-network.rules
  /etc/sysconfig/firewall.local
  /etc/ssh/sshd_config
  /etc/suricata/suricata.yaml
  /var/ipfire/ethernet/settings
  /var/ipfire/backup/include.user
  /etc/sysctl.conf
  /etc/syslog.conf
)

# ------------------------------------------------------------------
# capture_state: write current system state to a file descriptor or stdout
# ------------------------------------------------------------------
capture_state() {
  local OUTPUT_FILE="$1"
  {
    echo "=== Reboot Persistence Snapshot ==="
    echo "Captured: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo ""

    echo "--- Sysctl Hardening Parameters ---"
    for PARAM in "${SYSCTL_PARAMS[@]}"; do
      VALUE=$(sysctl -n "$PARAM" 2>/dev/null || echo "ERROR: not found")
      echo "${PARAM} = ${VALUE}"
    done
    echo ""

    echo "--- Listening Services (ss -tlnp) ---"
    ss -tlnp 2>/dev/null || echo "ERROR: ss command unavailable"
    echo ""

    echo "--- Iptables Ruleset Hash ---"
    IPTABLES_HASH=$(iptables-save 2>/dev/null | sha256sum | awk '{print $1}')
    echo "iptables-save | sha256sum = ${IPTABLES_HASH}"
    echo ""

    echo "--- Config File Hashes ---"
    for FILE in "${MONITORED_FILES[@]}"; do
      if [ -f "$FILE" ]; then
        sha256sum "$FILE"
      else
        echo "MISSING: $FILE"
      fi
    done
    echo ""

    echo "=== End of snapshot ==="
  } > "$OUTPUT_FILE"
}

# ------------------------------------------------------------------
# --snapshot mode: capture pre-reboot state
# ------------------------------------------------------------------
if [ "$1" = "--snapshot" ]; then
  echo "=== Reboot Snapshot === $(date)"
  echo "Capturing pre-reboot system state to: $SNAPSHOT_FILE"
  echo ""

  capture_state "$SNAPSHOT_FILE"

  echo "Snapshot written to: $SNAPSHOT_FILE"
  echo ""
  echo "INFO: Snapshot captures:"
  echo "  - Sysctl hardening values (${#SYSCTL_PARAMS[@]} parameters)"
  echo "  - Listening services (ss -tlnp)"
  echo "  - Iptables ruleset hash"
  echo "  - Config file hashes (${#MONITORED_FILES[@]} files)"
  echo ""
  echo "Now reboot: reboot"
  echo "After reboot run: bash validate-reboot.sh --compare"
  exit 0
fi

# ------------------------------------------------------------------
# --compare mode: compare current state against stored snapshot
# ------------------------------------------------------------------
if [ "$1" = "--compare" ]; then
  echo "=== Reboot Persistence Comparison === $(date)"

  if [ ! -f "$SNAPSHOT_FILE" ]; then
    echo "FAIL: No snapshot found at $SNAPSHOT_FILE"
    echo "      Run 'bash validate-reboot.sh --snapshot' before rebooting"
    exit 1
  fi

  echo "Snapshot file: $SNAPSHOT_FILE"
  echo "Snapshot timestamp: $(grep '^Captured:' "$SNAPSHOT_FILE" | head -1 | sed 's/Captured: //')"
  echo ""

  CURRENT_SNAPSHOT="/tmp/reboot-current-state.txt"
  capture_state "$CURRENT_SNAPSHOT"

  echo "--- State Comparison ---"
  DIFF_OUTPUT=$(diff "$SNAPSHOT_FILE" "$CURRENT_SNAPSHOT" 2>/dev/null)

  if [ -z "$DIFF_OUTPUT" ]; then
    pass "System state identical after reboot"
    echo ""
    echo "=== Reboot persistence verified ==="
    echo "Results: ${PASS} pass, ${FAIL} fail"
    rm -f "$CURRENT_SNAPSHOT"
    exit 0
  else
    fail "State changed after reboot — review diff above"
    echo ""
    echo "--- Diff (pre-reboot vs post-reboot) ---"
    echo "$DIFF_OUTPUT"
    echo ""
    echo "=== Reboot persistence FAILED ==="
    echo "Results: ${PASS} pass, ${FAIL} fail"
    echo ""
    echo "Investigate changes above. Common causes:"
    echo "  - sysctl params not in /etc/sysctl.conf (only applied via sysctl -p, not persistent)"
    echo "  - firewall.local not executed at boot (check /etc/init.d/firewall)"
    echo "  - Services changed listening ports after reboot"
    rm -f "$CURRENT_SNAPSHOT"
    exit 1
  fi
fi

# ------------------------------------------------------------------
# No valid mode — print usage
# ------------------------------------------------------------------
echo "Usage: $0 [--snapshot | --compare]"
echo ""
echo "  --snapshot   Capture current state before rebooting"
echo "  --compare    Compare current state against stored snapshot (run after reboot)"
echo ""
echo "Workflow:"
echo "  1. bash $0 --snapshot"
echo "  2. reboot"
echo "  3. bash $0 --compare"
exit 1
