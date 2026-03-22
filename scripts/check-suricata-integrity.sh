#!/bin/bash
# Post-Core-Update suricata.yaml integrity check
# Deploy to: /usr/local/bin/check-suricata-integrity.sh on IPFire
# Run after every Core Update via: bash /usr/local/bin/check-suricata-integrity.sh
# Exit codes: 0=OK, 1=FAIL (no baseline or missing file), 2=WARN (hash changed)
#
# Purpose: suricata.yaml is overwritten by every Core Update. This script detects
# when that happens so manual memcap and EVE JSON settings can be re-applied.
# Baseline is created automatically on first run.

YAML="/etc/suricata/suricata.yaml"
BASELINE="/root/suricata-yaml.sha256"

echo "=== Suricata Config Integrity Check ==="

# Check 1 — YAML exists
if [ ! -f "$YAML" ]; then
  echo "FAIL: $YAML does not exist"
  echo "      Suricata may not be installed or enabled. Enable via WUI: Firewall > IPS"
  exit 1
fi

# Check 2 — Baseline present and matches
if [ ! -f "$BASELINE" ]; then
  echo "INFO: No baseline found. Creating now."
  sha256sum "$YAML" > "$BASELINE"
  echo "PASS: Baseline created at $BASELINE"
  echo "      Run this script again after any Core Update to detect changes."
  # Fall through to EVE JSON and memcap checks, then exit 0
else
  if sha256sum -c "$BASELINE" --quiet 2>/dev/null; then
    echo "PASS: suricata.yaml matches baseline hash"
  else
    echo "WARN: suricata.yaml has changed since baseline"
    echo "      Core Update may have overwritten custom configuration"
    echo "      Review EVE JSON settings: grep -A5 'eve-log:' $YAML"
    echo "      Review memcap values: grep -E 'memcap|prealloc|depth' $YAML"
    echo "      After restoring config, update baseline:"
    echo "        sha256sum $YAML > $BASELINE"
    # Continue to checks below before exiting 2
    EVE_CHECK_RESULT=2
  fi
fi

# Check 3 — EVE JSON enabled
if grep -q "eve-log:" "$YAML"; then
  if grep -A2 "eve-log:" "$YAML" | grep -q "enabled: yes"; then
    echo "PASS: EVE JSON output is enabled"
  else
    echo "WARN: eve-log section found but 'enabled: yes' not confirmed in next 2 lines"
    echo "      Check: grep -A5 'eve-log:' $YAML"
  fi
else
  echo "WARN: No eve-log section found in $YAML"
  echo "      EVE JSON output may be absent after Core Update"
  echo "      Expected block: outputs: - eve-log: enabled: yes"
fi

# Check 4 — memcap values present (confirms custom tuning survived)
if grep -q "stream:" "$YAML" && grep -A5 "stream:" "$YAML" | grep -q "memcap:"; then
  STREAM_MEMCAP=$(grep -A5 "stream:" "$YAML" | grep "memcap:" | head -1 | awk '{print $2}')
  echo "PASS: stream.memcap found: $STREAM_MEMCAP"
else
  echo "WARN: stream.memcap not confirmed in $YAML — may need re-application after Core Update"
  echo "      See: configs/suricata/suricata-yaml-memcap-reference.yaml for values to apply"
fi

echo "=== Integrity check complete ==="

# Return exit 2 if hash mismatch was detected (set above)
if [ "${EVE_CHECK_RESULT:-0}" -eq 2 ]; then
  exit 2
fi

exit 0
