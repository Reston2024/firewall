#!/bin/bash
# rollback-dns.sh — Restore DNS forwarding config from backup
# Usage: bash rollback-dns.sh [backup-file]
# If no backup-file given, lists available backups and exits
# Run ON IPFire (not from dev machine)
# Per D-07: config-file rollback, not snapshot-based
# Per D-10: full category granularity

ROLLBACK_DIR="/root/rollback"
CONFIG_FILE="/var/ipfire/dns/forward.conf"
CATEGORY="dns"
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

echo "Config restored. Reloading Unbound DNS..."
/etc/init.d/unbound restart
if [ $? -ne 0 ]; then
  echo "ERROR: Unbound restart failed. Config may be invalid."
  exit 1
fi

echo "Rollback complete. Unbound DNS reloaded successfully."
echo "Verify: dig +short example.com @127.0.0.1"
exit 0
