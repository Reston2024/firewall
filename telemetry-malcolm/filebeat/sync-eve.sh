#!/bin/bash
# sync-eve.sh — Pull IPFire Suricata eve.json into Malcolm's watched directory.
#
# Cron entry (opsadmin):
#   * * * * * /opt/malcolm/scripts/sync-eve.sh
#
# Do NOT add `>> /var/log/sync-eve.log 2>&1` to the cron line — /var/log is
# root:syslog and opsadmin can't create files there. This script does its
# own self-logging via $HOME/logs + logger(1) so the script output redirect
# is not dependent on /var/log being writable.
#
# Design: byte-offset incremental fetch.
#
#   Every run we ask IPFire for the current size of eve.json. If it's
#   larger than our cursor (last seen offset), we SSH+tail the new bytes
#   since the cursor and APPEND them to the destination file, then
#   advance the cursor. If it's smaller, the source rotated — we reset
#   the cursor and truncate the destination to resync from scratch.
#
#   Why this design, not `scp && mv`:
#     The prior sync-eve.sh used atomic replace (`scp ... .tmp && mv`).
#     Each run gave the destination a NEW inode. Malcolm's Filebeat uses
#     native inode for filestream identity (`fingerprint.enabled: false`
#     in /usr/share/filebeat-logs/filebeat-logs.yml), so every run looked
#     like a new file and Filebeat would re-read the entire 253 MB,
#     duplicating every event every minute. Incremental append keeps the
#     same inode so Filebeat tails ONE file continuously.
#
#   Why not rsync --inplace --append-verify:
#     rsync is not installed on IPFire (the pakfire-native base), so
#     introducing a dependency on the perimeter firewall is avoided.
#
# History: prior to 2026-04-11 a one-liner `scp -q 2>/dev/null && mv` was
# deployed with the cron line above plus `>> /var/log/sync-eve.log 2>&1`.
# The log redirect failed silently because opsadmin can't write /var/log.
# The result: cron ran the redirect path which failed, bash exited 1
# without invoking the script, and sync-eve had never actually run via
# cron. Discovered during v2.0.1 audit on 2026-04-11. See
# .planning/phases/15-audit-remediation-v2.0.1/15-01-SUMMARY.md.

set -uo pipefail

# --- Configuration ---
SRC_HOST="root@192.168.1.1"
SRC_PATH="/var/log/suricata/eve.json"
DEST_DIR="/opt/malcolm/suricata-logs/suricata-ipfire"
DEST="${DEST_DIR}/eve.json"
SSH_KEY="${HOME}/.ssh/eve_rsync_ed25519"
LOG_DIR="${HOME}/logs"
LOG_FILE="${LOG_DIR}/sync-eve.log"
CURSOR="${HOME}/.sync-eve.cursor"
HEARTBEAT="${HOME}/.sync-eve.heartbeat"
FAILURE="${HOME}/.sync-eve.failed"
SCRIPT_NAME="sync-eve"
SSH_OPTS=(-i "${SSH_KEY}" -o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o BatchMode=yes)

# --- Self-logging ---
mkdir -p "${LOG_DIR}" 2>/dev/null || true
exec >> "${LOG_FILE}" 2>&1

log() {
  local msg="$1"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "${ts} ${msg}"
  command -v logger >/dev/null 2>&1 && logger -t "${SCRIPT_NAME}" -- "${msg}" || true
}

log_failure() {
  local msg="$1"
  log "FAIL ${msg}"
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${msg}" > "${FAILURE}"
}

# --- Prerequisites ---
if [ ! -f "${SSH_KEY}" ]; then
  log_failure "ssh key missing: ${SSH_KEY}"
  exit 1
fi

if ! mkdir -p "${DEST_DIR}" 2>/dev/null; then
  log_failure "mkdir failed: ${DEST_DIR}"
  exit 1
fi

touch "${DEST}" 2>/dev/null || {
  log_failure "cannot touch destination: ${DEST}"
  exit 1
}

# --- Read cursor (bytes already fetched) ---
OFFSET=0
if [ -f "${CURSOR}" ]; then
  OFFSET="$(cat "${CURSOR}" 2>/dev/null || echo 0)"
  case "${OFFSET}" in
    ''|*[!0-9]*) OFFSET=0 ;;
  esac
fi

# Guard: if the destination file size is less than the cursor, the file
# was cleaned up out-of-band (e.g. Malcolm restart wiped it). Reset.
DEST_SIZE="$(stat -c '%s' "${DEST}" 2>/dev/null || echo 0)"
if [ "${DEST_SIZE}" -lt "${OFFSET}" ]; then
  log "RESYNC dest_size=${DEST_SIZE} < cursor=${OFFSET}; destination was pruned; resetting"
  OFFSET=0
  : > "${DEST}"
fi

# --- Query source size ---
NEW_SIZE="$(ssh "${SSH_OPTS[@]}" "${SRC_HOST}" "stat -c %s ${SRC_PATH}" 2>&1)"
SSH_RC=$?
if [ ${SSH_RC} -ne 0 ] || ! [[ "${NEW_SIZE}" =~ ^[0-9]+$ ]]; then
  log_failure "remote stat failed rc=${SSH_RC} out=${NEW_SIZE}"
  exit 1
fi

# --- Handle rotation (source shrank) ---
if [ "${NEW_SIZE}" -lt "${OFFSET}" ]; then
  log "ROTATED source=${NEW_SIZE} < cursor=${OFFSET}; truncating dest and resetting"
  : > "${DEST}"
  OFFSET=0
fi

# --- Nothing new ---
if [ "${NEW_SIZE}" -eq "${OFFSET}" ]; then
  printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${HEARTBEAT}"
  rm -f "${FAILURE}" 2>/dev/null || true
  log "NOOP source_size=${NEW_SIZE} unchanged"
  exit 0
fi

# --- Fetch and append new bytes ---
# Pipe SSH stdout directly to the destination file. Bash command
# substitution `$(...)` cannot be used here because it strips NUL bytes
# from the captured stdout, which would corrupt any eve.json line that
# contains a NUL (observed warning during v2.0.1 testing).
#
# We cannot rely on the pre-fetch NEW_SIZE as the new cursor because
# the source may have grown between our stat() and our tail(). Instead,
# we record the destination file size AFTER the append completes. The
# invariant we maintain: destination is a byte-exact prefix of the
# source, and cursor == destination size. The next run's tail starts
# from cursor+1 which is the next unseen source byte.

START_BYTE=$(( OFFSET + 1 ))
BEFORE="$(stat -c '%s' "${DEST}" 2>/dev/null || echo 0)"

# `tail -c +N` is 1-indexed from the start of the file.
ssh "${SSH_OPTS[@]}" "${SRC_HOST}" \
  "tail -c +${START_BYTE} ${SRC_PATH}" >> "${DEST}" 2>/tmp/sync-eve.stderr.$$
SSH_RC=$?
STDERR="$(cat /tmp/sync-eve.stderr.$$ 2>/dev/null || true)"
rm -f /tmp/sync-eve.stderr.$$ 2>/dev/null || true

if [ ${SSH_RC} -ne 0 ]; then
  log_failure "remote tail failed rc=${SSH_RC} stderr=${STDERR}"
  exit 1
fi

AFTER="$(stat -c '%s' "${DEST}" 2>/dev/null || echo 0)"
DELTA=$(( AFTER - BEFORE ))

# Advance cursor to the actual destination size (always == bytes we wrote).
printf '%s\n' "${AFTER}" > "${CURSOR}"
printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${HEARTBEAT}"
rm -f "${FAILURE}" 2>/dev/null || true

log "OK appended=${DELTA}B offset=${AFTER} dest=${DEST}"
exit 0
