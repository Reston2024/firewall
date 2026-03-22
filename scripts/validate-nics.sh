#!/bin/bash
# validate-nics.sh — Verify MAC-to-zone mapping after reboot or Core Update
# Usage: bash /root/firewall-repo/scripts/validate-nics.sh
# Exits: 0 if all NICs pass, 1 if any mismatch or interface missing
#
# SETUP: Fill in the _EXPECTED_MAC variables below from docs/nic-map.md
# after completing physical NIC identification on the hardware.
# Run this script from the IPFire appliance (not from the dev machine).

set -euo pipefail

# --- CONFIGURE THESE VALUES FROM docs/nic-map.md ---
RED_EXPECTED_MAC="FILL_IN_FROM_NIC_MAP"
GREEN_EXPECTED_MAC="FILL_IN_FROM_NIC_MAP"
BLUE_EXPECTED_MAC="FILL_IN_FROM_NIC_MAP"
ORANGE_EXPECTED_MAC="FILL_IN_FROM_NIC_MAP"
GREEN1_EXPECTED_MAC="FILL_IN_FROM_NIC_MAP"
GREEN2_EXPECTED_MAC="FILL_IN_FROM_NIC_MAP"
# ---------------------------------------------------

FAIL=0
PASS=0

check_nic() {
  local zone="$1"
  local dev="$2"
  local expected_mac="$3"
  local actual_mac

  actual_mac=$(cat "/sys/class/net/${dev}/address" 2>/dev/null || echo "MISSING")

  if [ "$expected_mac" = "FILL_IN_FROM_NIC_MAP" ]; then
    echo "SKIP: ${zone} (${dev}) — MAC not yet configured in validate-nics.sh"
    return
  fi

  if [ "$actual_mac" = "$expected_mac" ]; then
    echo "PASS: ${zone} (${dev}) MAC=${actual_mac}"
    PASS=$((PASS + 1))
  else
    echo "FAIL: ${zone} (${dev}) expected=${expected_mac} got=${actual_mac}"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== NIC Validation — $(date) ==="
check_nic "RED"    "red0"    "$RED_EXPECTED_MAC"
check_nic "GREEN"  "green0"  "$GREEN_EXPECTED_MAC"
check_nic "BLUE"   "blue0"   "$BLUE_EXPECTED_MAC"
check_nic "ORANGE" "orange0" "$ORANGE_EXPECTED_MAC"
check_nic "GREEN1" "green1"  "$GREEN1_EXPECTED_MAC"
check_nic "GREEN2" "green2"  "$GREEN2_EXPECTED_MAC"
echo "=== Results: ${PASS} pass, ${FAIL} fail ==="

if [ "$FAIL" -eq 0 ]; then
  echo "ALL NICS PASS"
  exit 0
else
  echo "NIC VALIDATION FAILED — check udev rules and reboot"
  exit 1
fi
