#!/bin/bash
# rollback-zone.sh — Restore zone/NIC config from backup
# Usage: bash rollback-zone.sh [backup-file]
# If no backup-file given, lists available backups and exits
# Run ON IPFire (not from dev machine)
# Per D-07: config-file rollback, not snapshot-based
# Per D-10: full category granularity

ROLLBACK_DIR="/root/rollback"
CONFIG_FILE="/etc/udev/rules.d/30-persistent-network.rules"
CATEGORY="zone"
BACKUP_FILE="$1"

if [ -z "$BACKUP_FILE" ]; then
  echo "Available $CATEGORY backups:"
  ls -lt "$ROLLBACK_DIR"/${CATEGORY}-*.bak 2>/dev/null || echo "  None found"
  echo ""
  echo "Also check for ethernet settings backups:"
  ls -lt "$ROLLBACK_DIR"/ethernet-*.bak 2>/dev/null || echo "  None found"
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

# Also restore ethernet settings if a matching backup exists
TIMESTAMP=$(basename "$BACKUP_FILE" | sed 's/zone-\(.*\)\.bak/\1/')
ETHERNET_BACKUP="$ROLLBACK_DIR/ethernet-${TIMESTAMP}.bak"
if [ -f "$ETHERNET_BACKUP" ]; then
  echo "Found matching ethernet settings backup: $ETHERNET_BACKUP"
  echo "Restoring to: /var/ipfire/ethernet/settings"
  cp "$ETHERNET_BACKUP" /var/ipfire/ethernet/settings
  if [ $? -ne 0 ]; then
    echo "WARNING: Failed to restore ethernet settings backup."
  else
    echo "Ethernet settings restored."
  fi
else
  echo "No matching ethernet settings backup found at: $ETHERNET_BACKUP"
  echo "If you have a separate ethernet backup, restore it manually:"
  echo "  cp /root/rollback/ethernet-YYYYMMDD-HHMMSS.bak /var/ipfire/ethernet/settings"
fi

echo ""
echo "WARNING: Zone/NIC changes require a REBOOT to take full effect."
echo "udevadm trigger may work for hotplug devices, but reboot is the safe path."
echo "Run: reboot"
echo ""
echo "Verify after reboot: ip link show"
exit 0
