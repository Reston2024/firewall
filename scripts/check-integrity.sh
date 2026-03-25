#!/bin/bash
# Multi-file integrity baseline check for IPFire hardening artifacts
# Deploy to: /usr/local/bin/check-integrity.sh on IPFire
# Usage:
#   bash check-integrity.sh --create-baseline   Create initial SHA256 baseline
#   bash check-integrity.sh --verify            Verify files against baseline (default)
#   bash check-integrity.sh --update-baseline   Regenerate baseline after intentional changes
#
# Exit codes: 0=all match, 1=error (missing baseline or file), 2=mismatch detected
#
# Monitored files align with backup-include.user (D-08, D-09)
# Run after every Core Update or config change to detect unintended modifications.

BASELINE="/root/integrity-baseline.sha256"

# Files to monitor — must align with configs/firewall/backup-include.user
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

PASS=0
FAIL=0
WARN=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
warn() { echo "WARN: $1"; WARN=$((WARN + 1)); }

MODE="${1:---verify}"

echo "=== Multi-File Integrity Check === $(date)"
echo "Baseline: $BASELINE"
echo "Mode: $MODE"
echo ""

# ------------------------------------------------------------------
# create-baseline mode: hash all monitored files and write baseline
# ------------------------------------------------------------------
if [ "$MODE" = "--create-baseline" ] || [ "$MODE" = "--update-baseline" ]; then
  if [ "$MODE" = "--update-baseline" ] && [ -f "$BASELINE" ]; then
    echo "INFO: Updating existing baseline at $BASELINE"
  else
    echo "INFO: Creating new baseline at $BASELINE"
  fi

  > "$BASELINE"

  ANY_MISSING=0
  for FILE in "${MONITORED_FILES[@]}"; do
    if [ ! -f "$FILE" ]; then
      warn "File not found — skipping from baseline: $FILE"
      ANY_MISSING=1
    else
      sha256sum "$FILE" >> "$BASELINE"
      pass "Baselined: $FILE"
    fi
  done

  echo ""
  if [ "$ANY_MISSING" -eq 1 ]; then
    echo "WARN: Baseline created with missing files — re-run after deploying all configs"
    echo "      Results: ${PASS} baselined, ${WARN} skipped"
    exit 1
  fi

  echo "INFO: Baseline written to $BASELINE"
  echo "      Run 'bash check-integrity.sh --verify' after any Core Update to detect changes."
  echo "      Results: ${PASS} baselined, ${WARN} skipped"
  exit 0
fi

# ------------------------------------------------------------------
# verify mode (default): check each file against baseline
# ------------------------------------------------------------------
if [ ! -f "$BASELINE" ]; then
  echo "FAIL: No baseline found at $BASELINE"
  echo "      Run: bash check-integrity.sh --create-baseline"
  exit 1
fi

MISMATCH=0
MISSING_FILE=0

for FILE in "${MONITORED_FILES[@]}"; do
  if [ ! -f "$FILE" ]; then
    fail "File missing (not on system): $FILE"
    MISSING_FILE=1
    continue
  fi

  # Check if this file is in the baseline
  if ! grep -q " $FILE$" "$BASELINE" 2>/dev/null; then
    warn "File not in baseline (added after baseline creation?): $FILE"
    continue
  fi

  # Verify hash
  EXPECTED_LINE=$(grep " $FILE$" "$BASELINE")
  ACTUAL_HASH=$(sha256sum "$FILE" 2>/dev/null | awk '{print $1}')
  EXPECTED_HASH=$(echo "$EXPECTED_LINE" | awk '{print $1}')

  if [ "$ACTUAL_HASH" = "$EXPECTED_HASH" ]; then
    pass "Hash matches baseline: $FILE"
  else
    warn "Hash CHANGED since baseline: $FILE"
    echo "      Expected: $EXPECTED_HASH"
    echo "      Actual:   $ACTUAL_HASH"
    echo "      Core Update may have overwritten this file — review and re-apply changes"
    MISMATCH=1
  fi
done

echo ""
echo "=== Integrity check complete === Results: ${PASS} pass, ${WARN} warn, ${FAIL} fail"

if [ "$MISSING_FILE" -eq 1 ]; then
  echo "ERROR: Missing files — check deployment status"
  exit 1
fi

if [ "$MISMATCH" -eq 1 ]; then
  echo "WARN: Hash mismatches detected — review changed files above"
  echo "      After restoring config, update baseline:"
  echo "        bash check-integrity.sh --update-baseline"
  exit 2
fi

exit 0
