#!/bin/bash
# deploy-phase5.sh — Deploy Phase 5 configs to IPFire
# Phase 5: Telemetry Syslog
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

echo "=== deploy-phase5.sh — Telemetry Syslog === $(date)"

# --- syslog.conf — check multiple candidate locations ---
SYSLOG_SRC=""
if [ -f "$REPO/configs/syslog.conf" ]; then
  SYSLOG_SRC="$REPO/configs/syslog.conf"
elif [ -f "$REPO/configs/logging/syslog.conf" ]; then
  SYSLOG_SRC="$REPO/configs/logging/syslog.conf"
elif [ -f "$REPO/configs/telemetry/syslog.conf" ]; then
  SYSLOG_SRC="$REPO/configs/telemetry/syslog.conf"
fi

if [ -n "$SYSLOG_SRC" ]; then
  backup_and_copy "$SYSLOG_SRC" "/etc/syslog.conf" "syslog"
  pass "syslog.conf deployed: /etc/syslog.conf (source: $SYSLOG_SRC)"

  # Restart syslog daemon
  if [ -f "/etc/init.d/sysklogd" ]; then
    /etc/init.d/sysklogd restart >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      pass "sysklogd restarted"
    else
      fail "sysklogd restart failed"
    fi
  else
    fail "sysklogd service not found at /etc/init.d/sysklogd"
  fi
else
  echo "SKIP: No syslog.conf found in repo — syslog forwarding may need WUI configuration"
  echo "      Checked: $REPO/configs/syslog.conf"
  echo "               $REPO/configs/logging/syslog.conf"
  echo "               $REPO/configs/telemetry/syslog.conf"
fi

echo ""
echo "NOTE: Syslog remote forwarding destination is configured via WUI > Logs > Log Settings"
echo "      Set remote syslog server to 192.168.1.22 (supportTAK monitoring host), port 514"
echo ""
echo "NOTE: Off-box telemetry stack (Grafana/Loki/Alloy) is deployed separately on the"
echo "      monitoring host at 192.168.1.22 — see docs/telemetry-deployment-runbook.md"
echo ""
echo "=== Phase 5 complete: $PASS pass, $FAIL fail ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
