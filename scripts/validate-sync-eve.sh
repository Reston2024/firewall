#!/bin/bash
# validate-sync-eve.sh — Sync-eve pipeline watchdog (v2.0.1 addition)
#
# Detects silent-failure conditions in the IPFire-Suricata → supportTAK
# → Malcolm telemetry path. This is the validator that would have
# caught the dma-loop / broken-cron outage if it had been in place
# before 2026-04-11.
#
# Run from the laptop or from IPFire (both can reach supportTAK via SSH).
#
# Checks:
#   SE-01  heartbeat file exists and is less than 3 minutes old
#   SE-02  failure sentinel file is absent
#   SE-03  destination eve.json exists and has a recent mtime (< 5 min)
#   SE-04  IPFire-side source eve.json mtime is recent (< 5 min)
#   SE-05  the last 20 lines of sync-eve.log have no FAIL entries
#   SE-06  evidence archive-logs.sh has produced a file within last 90 min
#
# Exit: 0 if no FAILs (SKIPs allowed), 1 if any check FAILed.

set -u

FAIL=0; PASS=0; SKIP=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "SKIP: $1"; SKIP=$((SKIP + 1)); }

SSH_TARGET_ST="opsadmin@192.168.1.22"
SSH_TARGET_IPFIRE="root@192.168.1.1"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=yes)
NOW_EPOCH="$(date +%s)"

echo "=== validate-sync-eve — $(date) ==="
echo ""

# --- SE-01: heartbeat fresh ---
echo "[SE-01] Sync-eve heartbeat is fresh (< 180 s)"
HB_AGE="$(ssh "${SSH_OPTS[@]}" "${SSH_TARGET_ST}" \
  'f=$HOME/.sync-eve.heartbeat; if [ -f "$f" ]; then echo $(( $(date +%s) - $(stat -c %Y "$f") )); else echo MISSING; fi' \
  2>/dev/null)"
if [ "${HB_AGE}" = "MISSING" ]; then
  fail "SE-01: heartbeat file \$HOME/.sync-eve.heartbeat missing on supportTAK — sync-eve has never succeeded since cron install"
elif ! [[ "${HB_AGE}" =~ ^[0-9]+$ ]]; then
  fail "SE-01: could not parse heartbeat age (got '${HB_AGE}')"
elif [ "${HB_AGE}" -gt 180 ]; then
  fail "SE-01: heartbeat is ${HB_AGE} s old (> 180 s threshold) — sync-eve has not succeeded in the last 3 minutes"
else
  pass "SE-01: heartbeat age ${HB_AGE} s"
fi
echo ""

# --- SE-02: failure sentinel absent ---
echo "[SE-02] Sync-eve failure sentinel is absent"
FS_OUT="$(ssh "${SSH_OPTS[@]}" "${SSH_TARGET_ST}" \
  'f=$HOME/.sync-eve.failed; if [ -f "$f" ]; then cat "$f"; else echo ABSENT; fi' \
  2>/dev/null)"
if [ "${FS_OUT}" = "ABSENT" ]; then
  pass "SE-02: no failure sentinel"
else
  fail "SE-02: failure sentinel exists: ${FS_OUT}"
fi
echo ""

# --- SE-03: destination eve.json mtime recent ---
echo "[SE-03] Malcolm-side /opt/malcolm/suricata-logs/suricata-ipfire/eve.json mtime < 5 min"
DEST_AGE="$(ssh "${SSH_OPTS[@]}" "${SSH_TARGET_ST}" \
  'f=/opt/malcolm/suricata-logs/suricata-ipfire/eve.json; if [ -f "$f" ]; then echo $(( $(date +%s) - $(stat -c %Y "$f") )); else echo MISSING; fi' \
  2>/dev/null)"
if [ "${DEST_AGE}" = "MISSING" ]; then
  fail "SE-03: destination eve.json missing — sync-eve has not delivered any file"
elif ! [[ "${DEST_AGE}" =~ ^[0-9]+$ ]]; then
  fail "SE-03: could not parse dest mtime age (got '${DEST_AGE}')"
elif [ "${DEST_AGE}" -gt 300 ]; then
  fail "SE-03: destination eve.json mtime is ${DEST_AGE} s old (> 300 s) — pipeline is stalled"
else
  pass "SE-03: destination eve.json mtime age ${DEST_AGE} s"
fi
echo ""

# --- SE-04: source eve.json on IPFire mtime recent ---
echo "[SE-04] IPFire /var/log/suricata/eve.json mtime < 5 min"
SRC_AGE="$(ssh "${SSH_OPTS[@]}" "${SSH_TARGET_IPFIRE}" \
  'f=/var/log/suricata/eve.json; if [ -f "$f" ]; then echo $(( $(date +%s) - $(stat -c %Y "$f") )); else echo MISSING; fi' \
  2>/dev/null)"
if [ "${SRC_AGE}" = "MISSING" ]; then
  fail "SE-04: source eve.json missing on IPFire — is Suricata running?"
elif ! [[ "${SRC_AGE}" =~ ^[0-9]+$ ]]; then
  fail "SE-04: could not parse source mtime age (got '${SRC_AGE}')"
elif [ "${SRC_AGE}" -gt 300 ]; then
  fail "SE-04: IPFire eve.json mtime is ${SRC_AGE} s old (> 300 s) — Suricata may have crashed again"
else
  pass "SE-04: source eve.json mtime age ${SRC_AGE} s"
fi
echo ""

# --- SE-05: no FAIL lines in recent log ---
echo "[SE-05] Recent sync-eve.log has no FAIL entries"
FAIL_COUNT="$(ssh "${SSH_OPTS[@]}" "${SSH_TARGET_ST}" \
  'f=$HOME/logs/sync-eve.log; if [ -f "$f" ]; then tail -20 "$f" | grep -c "FAIL "; else echo -1; fi' \
  2>/dev/null)"
if [ "${FAIL_COUNT}" = "-1" ]; then
  skip "SE-05: sync-eve.log not yet created (normal on fresh install before first run)"
elif ! [[ "${FAIL_COUNT}" =~ ^[0-9]+$ ]]; then
  skip "SE-05: could not parse fail count"
elif [ "${FAIL_COUNT}" -eq 0 ]; then
  pass "SE-05: last 20 log lines show no FAIL entries"
else
  fail "SE-05: ${FAIL_COUNT} FAIL line(s) in last 20 log lines"
fi
echo ""

# --- SE-06: evidence archive-logs health ---
# archive-logs.sh runs hourly at :00 past the hour (cron: 0 * * * *).
# The most recent file under the Seagate archive path should be less
# than 90 minutes old (hourly + 30 min slack for processing latency).
echo "[SE-06] Evidence archive-logs output < 90 min old"
ARCHIVE_AGE="$(ssh "${SSH_OPTS[@]}" "${SSH_TARGET_ST}" \
  '
  base="/media/opsadmin/Seagate Portable Drive/firewall-archive"
  if [ ! -d "$base" ]; then
    echo MISSING_DIR
    exit 0
  fi
  newest=$(find "$base" -type f -printf "%T@\n" 2>/dev/null | sort -rn | head -1 | cut -d. -f1)
  if [ -z "$newest" ]; then
    echo NO_FILES
  else
    echo $(( $(date +%s) - newest ))
  fi
  ' 2>/dev/null)"
if [ "${ARCHIVE_AGE}" = "MISSING_DIR" ]; then
  fail "SE-06: archive dir not mounted — is the Seagate drive attached?"
elif [ "${ARCHIVE_AGE}" = "NO_FILES" ]; then
  fail "SE-06: archive dir exists but has no files — archive-logs.sh has never succeeded"
elif ! [[ "${ARCHIVE_AGE}" =~ ^[0-9]+$ ]]; then
  skip "SE-06: could not parse archive file age (got '${ARCHIVE_AGE}')"
elif [ "${ARCHIVE_AGE}" -gt 5400 ]; then
  fail "SE-06: newest archive file is ${ARCHIVE_AGE}s old (> 5400s = 90 min) — archive-logs.sh cron may be broken"
else
  pass "SE-06: newest archive file age ${ARCHIVE_AGE}s"
fi
echo ""

# --- Summary ---
echo "=== validate-sync-eve Summary ==="
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo ""
if [ $FAIL -gt 0 ]; then
  echo "=== FAILED: $FAIL check(s) — IPFire telemetry to Malcolm is degraded or broken ==="
  exit $FAIL
else
  echo "=== ALL CHECKS PASS ($SKIP skipped) ==="
  exit 0
fi
