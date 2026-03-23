#!/bin/bash
# rsync-eve.sh — Pull Suricata EVE JSON from IPFire to monitoring host
# Run as cron on supportTAK-server: * * * * * /opt/telemetry/scripts/rsync-eve.sh
# Requires: SSH key at /home/opsadmin/.ssh/eve_rsync_ed25519 authorized on IPFire
# Cron setup: crontab -e as opsadmin and add the above line

IPFIRE_IP="192.168.1.1"
IPFIRE_USER="root"
IPFIRE_KEY="/home/opsadmin/.ssh/eve_rsync_ed25519"
REMOTE_PATH="/var/log/suricata/eve.json"
LOCAL_DIR="/var/log/ipfire-eve"
LOCAL_PATH="${LOCAL_DIR}/eve.json"

# Ensure staging directory exists with correct permissions
mkdir -p "${LOCAL_DIR}"
chmod 755 "${LOCAL_DIR}"

# Rsync: --checksum handles logrotate correctly (detects file replacement vs append)
# Do NOT use --append-verify: causes duplicate entries after nightly logrotate on IPFire
rsync -az \
  --checksum \
  --timeout=30 \
  -e "ssh -i ${IPFIRE_KEY} -o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o BatchMode=yes" \
  "${IPFIRE_USER}@${IPFIRE_IP}:${REMOTE_PATH}" \
  "${LOCAL_PATH}" 2>/dev/null

EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  logger -t rsync-eve "WARNING: rsync from ${IPFIRE_IP}:${REMOTE_PATH} failed (exit ${EXIT_CODE})"
  exit $EXIT_CODE
fi

# Log successful sync size (visible in: journalctl -t rsync-eve)
FILE_SIZE=$(stat -c%s "${LOCAL_PATH}" 2>/dev/null || echo "unknown")
logger -t rsync-eve "INFO: sync OK, local eve.json size=${FILE_SIZE} bytes"
exit 0
