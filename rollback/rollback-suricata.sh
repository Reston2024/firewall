#!/bin/bash
# rollback-suricata.sh — Restore Suricata IDS/IPS config from backup
# Usage: bash rollback-suricata.sh [backup-file]
# If no backup-file given, lists available backups and exits
# Run ON IPFire (not from dev machine)
# Per D-07: config-file rollback, not snapshot-based
# Per D-10: full category granularity

ROLLBACK_DIR="/root/rollback"
CONFIG_FILE="/etc/suricata/suricata.yaml"
CATEGORY="suricata"
BACKUP_FILE="$1"

if [ -z "$BACKUP_FILE" ]; then
  echo "Available $CATEGORY backups:"
  ls -lt "$ROLLBACK_DIR"/${CATEGORY}-*.bak 2>/dev/null || echo "  None found"
  echo ""
  echo "Usage: bash rollback-${CATEGORY}.sh $ROLLBACK_DIR/${CATEGORY}-YYYYMMDD-HHMMSS.bak"
  exit 0
fi

if [ ! -f "$BACKUP_FILE" ]; then
  echo "ERROR: Backup file not found: $BACKUP_FILE"
  exit 1
fi

echo "Restoring $CATEGORY config from: $BACKUP_FILE"
echo "Target: $CONFIG_FILE"

cp "$BACKUP_FILE" "$CONFIG_FILE"
if [ $? -ne 0 ]; then
  echo "ERROR: Failed to copy backup to $CONFIG_FILE"
  exit 1
fi

echo "Config restored. Reloading Suricata..."
/etc/init.d/suricata restart
if [ $? -ne 0 ]; then
  echo "ERROR: Suricata restart failed. Config may be invalid."
  exit 1
fi

echo "Rollback complete. Suricata reloaded successfully."
echo "Verify: suricata --build-info | head -1"
exit 0
