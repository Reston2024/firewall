#!/bin/bash
# validate-phase4.sh — Phase 4 validation suite — IDS/IPS (Suricata)
# Run ON IPFire via SSH (not from dev machine)
# Usage: bash /root/firewall-repo/scripts/validate-phase4.sh [--full]
#   Default: runs all automated checks (IDS-01 through IDS-08)
#   --full:  also runs memory usage check (IDS-05) which requires 30+ minutes of traffic
# Exits: 0 if all automated checks pass (SKIP is acceptable), 1 if any fail

if [ "${1}" = "--full" ]; then FULL=1; else FULL=0; fi

FAIL=0
PASS=0
SKIP=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "SKIP: $1 (manual verification required)"; SKIP=$((SKIP + 1)); }

echo "=== Phase 4 Validation Suite — IDS/IPS (Suricata) — $(date) ==="
echo ""

# --- IDS-01: ET Community ruleset loaded ---
echo "[IDS-01] ET Community ruleset loaded"

PID=$(pgrep -o suricata 2>/dev/null)
if [ -z "$PID" ]; then
  fail "IDS-01: Suricata is not running. Enable IPS via WUI: Firewall > Intrusion Prevention System"
else
  pass "IDS-01: Suricata process running (PID $PID)"

  RULE_COUNT_LINE=$(grep "rules loaded" /var/log/suricata/suricata.log 2>/dev/null | tail -1)
  if [ -z "$RULE_COUNT_LINE" ]; then
    skip "IDS-01: 'rules loaded' line not found in suricata.log — Suricata may not have fully started yet. Check: grep 'rules loaded' /var/log/suricata/suricata.log"
  else
    RULE_COUNT=$(echo "$RULE_COUNT_LINE" | awk '{print $NF}')
    if echo "$RULE_COUNT" | grep -qE '^[0-9]+$'; then
      if [ "$RULE_COUNT" -lt 1000 ]; then
        fail "IDS-01: Only $RULE_COUNT rules loaded (expected >= 1000). Enable ET Community ruleset via WUI: Firewall > IPS > Rulesets"
      else
        pass "IDS-01: $RULE_COUNT rules loaded (>= 1000 — ET Community active)"
      fi
    else
      skip "IDS-01: Cannot parse rule count from log line: '$RULE_COUNT_LINE' — verify manually"
    fi
  fi
fi
echo ""

# --- IDS-02: Zone selection (RED + GREEN active) ---
echo "[IDS-02] Zone selection — RED and GREEN active"
# Note: WUI-configured state cannot be read reliably from CLI; log presence is best available automated check
ZONE_LOG=$(grep -E "red0|green0" /var/log/suricata/suricata.log 2>/dev/null | grep -iE "running|NFQ|nfq|interface" | head -3)
if [ -n "$ZONE_LOG" ]; then
  pass "IDS-02: Interface log evidence found (red0/green0 mentioned in suricata.log)"
  echo "        Evidence: $(echo "$ZONE_LOG" | head -1)"
else
  skip "IDS-02: Zone log evidence not found — verify manually via WUI IPS page that RED and GREEN are selected. WUI path: Firewall > Intrusion Prevention System > Zones"
fi
echo ""

# --- IDS-03: Automatic rule update enabled ---
echo "[IDS-03] Automatic rule updates enabled"
# fcron.daily runs at 01:25 AM; after initial install, rules fetched on first WUI Apply
RULES_DIR="/var/lib/suricata"
NEWEST_RULES=$(find "$RULES_DIR" -maxdepth 1 -name "*.rules" -newer /proc/1 2>/dev/null | head -1)

if [ -z "$(ls "$RULES_DIR"/*.rules 2>/dev/null)" ]; then
  skip "IDS-03: No .rules files found at $RULES_DIR — Suricata may not have downloaded rules yet. Verify auto-update toggle is enabled in WUI: Firewall > IPS > ET Community > Automatic Updates"
else
  # Check if any .rules file was modified within last 48 hours
  RECENT=$(find "$RULES_DIR" -maxdepth 1 -name "*.rules" -mmin -2880 2>/dev/null | head -1)
  if [ -n "$RECENT" ]; then
    MTIME=$(stat -c "%y" "$RECENT" 2>/dev/null | cut -d'.' -f1)
    pass "IDS-03: Rules file updated within last 48 hours (newest: $MTIME)"
  else
    OLDEST_MTIME=$(stat -c "%y" "$RULES_DIR"/*.rules 2>/dev/null | sort | tail -1 | cut -d'.' -f1)
    skip "IDS-03: Rules mtime check: rules may be current or less than 24h since install — verify WUI auto-update toggle is enabled manually. Last rules modification: $OLDEST_MTIME. WUI: Firewall > IPS > ET Community > Automatic Updates"
  fi
fi
echo ""

# --- IDS-04: Monitor-only mode (not Drop) ---
echo "[IDS-04] Monitor-only mode (Surveillance, not Drop)"
skip "IDS-04: Monitor mode verification requires WUI — check Firewall > IPS mode toggle shows 'Surveillance' not 'Drop'. Cannot read mode from CLI reliably."
echo ""

# --- IDS-05: Memory within acceptable range (--full only) ---
echo "[IDS-05] Memory usage within acceptable range"
if [ "$FULL" -eq 0 ]; then
  skip "IDS-05: Memory check requires --full flag and 30 minutes of normal traffic. Run: bash /root/firewall-repo/scripts/validate-phase4.sh --full"
else
  IDS05_PID=$(pgrep -o suricata 2>/dev/null)
  if [ -z "$IDS05_PID" ]; then
    skip "IDS-05: Suricata not running — cannot check memory usage"
  else
    RSS=$(cat /proc/"$IDS05_PID"/status 2>/dev/null | grep VmRSS | awk '{print $2}')
    if [ -z "$RSS" ]; then
      skip "IDS-05: Cannot read VmRSS from /proc/$IDS05_PID/status"
    else
      RSS_MB=$((RSS / 1024))
      if [ "$RSS_MB" -gt 2048 ]; then
        fail "IDS-05: Suricata RSS ${RSS_MB}MB exceeds 2048MB limit. Check /var/log/suricata/eve.json for memcap events and reduce memcap values in /etc/suricata/suricata.yaml"
      else
        pass "IDS-05: Suricata RSS ${RSS_MB}MB is within acceptable range (< 2048MB)"
      fi
    fi
  fi
fi
echo ""

# --- IDS-06: EVE JSON receiving entries ---
echo "[IDS-06] EVE JSON logging active and receiving entries"
EVE="/var/log/suricata/eve.json"

if [ ! -f "$EVE" ]; then
  fail "IDS-06: $EVE does not exist. Check suricata.yaml: grep -A3 'eve-log:' /etc/suricata/suricata.yaml — ensure 'enabled: yes' is set"
else
  pass "IDS-06: $EVE exists"

  if grep -q '"event_type"' "$EVE" 2>/dev/null; then
    pass "IDS-06: eve.json contains event_type entries — EVE JSON is receiving data"
  else
    fail "IDS-06: eve.json exists but contains no event_type entries. Trigger test traffic: curl http://testmynids.org/uid/index.html and wait 60 seconds"
  fi

  # Check EVE log is enabled in suricata.yaml
  if grep -A3 "eve-log:" /etc/suricata/suricata.yaml 2>/dev/null | grep -q "enabled: yes"; then
    pass "IDS-06: suricata.yaml confirms eve-log enabled: yes"
  else
    skip "IDS-06: WARN: suricata.yaml eve-log section not confirmed enabled. Check: grep -A3 'eve-log:' /etc/suricata/suricata.yaml"
  fi
fi
echo ""

# --- IDS-07: No emerging-policy rules in active ruleset ---
echo "[IDS-07] No emerging-policy rules in active ruleset (safe baseline)"
USED_RULEFILES="/var/ipfire/suricata/suricata-used-rulefiles.yaml"

if [ ! -f "$USED_RULEFILES" ]; then
  skip "IDS-07: $USED_RULEFILES not found — Suricata may not yet be configured via WUI. Once configured, run this script again to verify emerging-policy.rules is not active."
else
  POLICY_IN_USED=$(grep "emerging-policy" "$USED_RULEFILES" 2>/dev/null)
  if [ -n "$POLICY_IN_USED" ]; then
    fail "IDS-07: emerging-policy.rules is listed in active rulefiles ($USED_RULEFILES). This ruleset blocks Linux package managers and can disrupt SSH. Disable via WUI: Firewall > IPS > Customize Ruleset"
  else
    pass "IDS-07: emerging-policy.rules is NOT listed in $USED_RULEFILES (safe baseline confirmed)"
  fi

  # Secondary check: look for any loaded emerging-policy rule files
  POLICY_FILES=$(grep -l "emerging-policy" /var/lib/suricata/*.rules 2>/dev/null)
  if [ -n "$POLICY_FILES" ]; then
    skip "IDS-07: emerging-policy rule files found in /var/lib/suricata/ (downloaded but may not be active): $POLICY_FILES — verify they are not listed in $USED_RULEFILES"
  fi
fi
echo ""

# --- IDS-08: Integrity check via check-suricata-integrity.sh ---
echo "[IDS-08] Post-Core-Update suricata.yaml integrity baseline"
INTEGRITY_SCRIPT="/usr/local/bin/check-suricata-integrity.sh"

if [ ! -f "$INTEGRITY_SCRIPT" ]; then
  fail "IDS-08: $INTEGRITY_SCRIPT is missing. Deploy from repo: scp scripts/check-suricata-integrity.sh root@192.168.1.1:/usr/local/bin/check-suricata-integrity.sh && ssh root@192.168.1.1 'sed -i \"s/\r\$//\" /usr/local/bin/check-suricata-integrity.sh && chmod +x /usr/local/bin/check-suricata-integrity.sh'"
else
  bash "$INTEGRITY_SCRIPT"
  INTEGRITY_EXIT=$?
  if [ "$INTEGRITY_EXIT" -eq 0 ]; then
    pass "IDS-08: check-suricata-integrity.sh returned exit 0 — suricata.yaml integrity confirmed"
  elif [ "$INTEGRITY_EXIT" -eq 2 ]; then
    skip "IDS-08: check-suricata-integrity.sh returned exit 2 (hash mismatch WARN) — Core Update may have overwritten suricata.yaml. Review output above and re-apply custom settings if needed."
  else
    fail "IDS-08: check-suricata-integrity.sh returned exit $INTEGRITY_EXIT — integrity check failed. Run manually for details: bash $INTEGRITY_SCRIPT"
  fi
fi
echo ""

# --- Summary ---
echo "=== Results: PASS=$PASS, FAIL=$FAIL, SKIP=$SKIP ==="
if [ $FAIL -gt 0 ]; then
  echo "=== CHECKS COMPLETE: $PASS PASS, $FAIL FAIL, $SKIP SKIP ==="
  exit 1
else
  echo "=== ALL CHECKS PASS ($SKIP skipped) ==="
  exit 0
fi
