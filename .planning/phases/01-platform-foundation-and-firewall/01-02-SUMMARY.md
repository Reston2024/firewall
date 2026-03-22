---
phase: 01-platform-foundation-and-firewall
plan: 02
subsystem: platform-config
tags: [udev, nic-persistence, firewall, anti-lockout, backup]
dependency_graph:
  requires: [01-01]
  provides: [udev-nic-rules, ethernet-settings, firewall-local, backup-include]
  affects: [01-03, 01-04]
tech_stack:
  added: []
  patterns: [udev-mac-anchoring, iptables-custominput, ipfire-backup-include]
key_files:
  created:
    - configs/udev/30-persistent-network.rules
    - configs/ethernet/settings
    - configs/firewall/firewall.local
    - configs/firewall/backup-include.user
  modified: []
decisions:
  - "FILL_IN_FROM_NIC_MAP placeholders used for all MAC addresses — human must populate from hardware before deployment"
  - "firewall.local sources /var/ipfire/ethernet/settings to avoid hardcoded interface names"
  - "check-before-delete pattern (-C before -D) used in stop case to prevent iptables errors on empty chain"
  - "backup-include.user covers /etc/ paths not included in IPFire default backup scope"
metrics:
  duration: "~2 minutes"
  completed_date: "2026-03-22"
  tasks_completed: 3
  files_created: 4
requirements_satisfied: [PLAT-01, PLAT-02, PLAT-05, FW-07]
---

# Phase 01 Plan 02: NIC Persistence and Anti-Lockout Config Artifacts Summary

**One-liner:** Four deployment-ready IPFire config artifacts — MAC-anchored udev NIC rules, zone settings template, CUSTOMINPUT anti-lockout firewall script, and backup include list.

## What Was Created

### 1. `configs/udev/30-persistent-network.rules` — NIC Persistence Rules (PLAT-01)

Anchors all 6 NICs to their zone names by MAC address using udev. Prevents NIC name shuffling across reboots or after hardware changes. Covers all required zones:

| Zone | Device Name | Rule |
|------|-------------|------|
| RED (WAN) | red0 | ACTION=="add", ATTR{address}=="FILL_IN", NAME="red0" |
| GREEN (LAN) | green0 | ACTION=="add", ATTR{address}=="FILL_IN", NAME="green0" |
| BLUE (Wireless) | blue0 | ACTION=="add", ATTR{address}=="FILL_IN", NAME="blue0" |
| ORANGE (DMZ) | orange0 | ACTION=="add", ATTR{address}=="FILL_IN", NAME="orange0" |
| GREEN Bridge 1 | green1 | ACTION=="add", ATTR{address}=="FILL_IN", NAME="green1" |
| GREEN Bridge 2 | green2 | ACTION=="add", ATTR{address}=="FILL_IN", NAME="green2" |

**Deploy:** `scp configs/udev/30-persistent-network.rules root@IPFIRE_IP:/etc/udev/rules.d/`
**Post-deploy:** `udevadm control --reload-rules && udevadm trigger` then full reboot.

### 2. `configs/ethernet/settings` — Zone-to-NIC Configuration (PLAT-01)

IPFire's zone-to-NIC mapping file. Sets CONFIG_TYPE=4 (all four zones active), enables GREEN bridge mode with green1/green2 as slaves.

Key settings:
- `CONFIG_TYPE=4` — all zones active (GREEN+RED+BLUE+ORANGE)
- `GREEN_MODE=Bridge` — bridge mode for extra LAN ports
- `GREEN_SLAVES=green1,green2` — both extra NICs bridged to green0
- `RED_TYPE=DHCP` — ISP uplink via DHCP
- `RED_DRIVER=igc` — Intel i226-V driver (all 6 NICs identical)

**Deploy:** `scp configs/ethernet/settings root@IPFIRE_IP:/var/ipfire/ethernet/settings`
**Post-deploy:** `/etc/init.d/network restart`
**Warning:** Misconfigured ethernet/settings will disrupt networking. Use IPFire `setup` utility as fallback.

### 3. `configs/firewall/firewall.local` — Anti-Lockout Script (PLAT-02, FW-07)

Executable shell script that runs BEFORE the main WUI-managed firewall ruleset via the CUSTOMINPUT chain. Ensures SSH (port 222) and WUI (port 444) remain accessible from GREEN zone regardless of WUI policy changes.

Key implementation details:
- Sources `/var/ipfire/ethernet/settings` to get `${GREEN_DEV}` — no hardcoded interface names
- `start` case appends 2 ACCEPT rules to CUSTOMINPUT
- `stop` case uses `-C` (check) before `-D` (delete) to avoid "Bad rule" errors
- `reload` case calls stop then start
- Executable bit set (`chmod +x`)

**Deploy:**
```bash
scp configs/firewall/firewall.local root@IPFIRE_IP:/etc/sysconfig/firewall.local
chmod +x /etc/sysconfig/firewall.local
/etc/init.d/firewall restart
```
**Verify:** `iptables -L CUSTOMINPUT -n -v | grep -E '(222|444)'`

### 4. `configs/firewall/backup-include.user` — Backup Include List (PLAT-05)

Tells IPFire's backup system to include the two custom files in `/etc/` that are outside the default `/var/ipfire/` backup scope. Without this file, both the udev rules and firewall.local would be lost after a backup-restore cycle (e.g., after a Core Update).

Contents (exactly two paths):
```
/etc/udev/rules.d/30-persistent-network.rules
/etc/sysconfig/firewall.local
```

**Deploy:** `scp configs/firewall/backup-include.user root@IPFIRE_IP:/var/ipfire/backup/include.user`
**Verify:** `backupctrl list | grep -E '(udev|firewall.local)'`

## Placeholder Status

**All four files contain placeholders that MUST be filled in before deploying to hardware.**

| File | Placeholder | Count | Source |
|------|-------------|-------|--------|
| configs/udev/30-persistent-network.rules | FILL_IN_FROM_NIC_MAP | 6 (one per NIC) | docs/nic-map.md |
| configs/ethernet/settings | FILL_IN_FROM_NIC_MAP | 4 (RED/GREEN/BLUE/ORANGE MACs) | docs/nic-map.md |
| configs/ethernet/settings | FILL_IN_IP_ADDRESS | Multiple | Network design decision |
| configs/ethernet/settings | FILL_IN_NETMASK | Multiple | Network design decision |

Steps to fill placeholders:
1. Run identification commands in `docs/nic-map.md` on IPFire console
2. Fill in `docs/nic-map.md` NIC Assignment Table with real MAC addresses
3. Copy MACs into `configs/udev/30-persistent-network.rules`
4. Copy MACs into `configs/ethernet/settings`
5. Decide on IP addressing scheme for GREEN/BLUE/ORANGE zones
6. Fill IP addresses and netmasks in `configs/ethernet/settings`
7. Commit all updates to git

## Commits

| Hash | Task | Description |
|------|------|-------------|
| dcfd5e5 | Task 1 | feat(01-02): add udev NIC persistence rules template (PLAT-01) |
| 9a245af | Task 2 | feat(01-02): add ethernet/settings template (PLAT-01) |
| e385fd8 | Task 3 | feat(01-02): add firewall.local anti-lockout script and backup include list (PLAT-02, PLAT-05, FW-07) |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed FILL_IN_FROM_NIC_MAP comment count mismatch in udev rules**
- **Found during:** Task 1 verification
- **Issue:** Comment header in udev rules file contained "FILL_IN_FROM_NIC_MAP" string, causing `grep -c 'FILL_IN_FROM_NIC_MAP'` to return 7 instead of expected 6
- **Fix:** Changed comment to say "Replace every placeholder MAC value" without repeating the placeholder string
- **Files modified:** configs/udev/30-persistent-network.rules
- **Commit:** dcfd5e5

**2. [Rule 1 - Bug] Fixed FILL_IN_FROM_NIC_MAP comment count mismatch in ethernet/settings**
- **Found during:** Task 2 verification
- **Issue:** Comment header in ethernet/settings contained "FILL_IN_FROM_NIC_MAP" string, causing `grep -c 'FILL_IN_FROM_NIC_MAP'` to return 5 instead of expected 4
- **Fix:** Changed comment to say "Replace each MAC placeholder value" without repeating the placeholder string
- **Files modified:** configs/ethernet/settings
- **Commit:** 9a245af

## Next Step

**Human action required:** Fill in MAC addresses from hardware identification, then Plan 03 creates zone policy runbook for IPFire WUI firewall rules configuration.

## Known Stubs

None — all files are complete with explicit FILL_IN placeholders. Stubs are intentional and documented in the "Placeholder Status" section above. The placeholder strings are searchable strings the human operator will replace from docs/nic-map.md before deployment.

## Self-Check: PASSED
