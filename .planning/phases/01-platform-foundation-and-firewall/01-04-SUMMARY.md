---
plan: 01-04
phase: 01-platform-foundation-and-firewall
status: complete
completed: 2026-03-26
duration_minutes: 0
tasks_completed: 3
tasks_total: 3
files_modified:
  - docs/nic-map.md
  - scripts/validate-nics.sh
  - configs/udev/30-persistent-network.rules
  - configs/ethernet/settings
one_liner: "Hardware NIC identification, MAC substitution, udev/firewall deployment, and full Phase 1 acceptance on live IPFire"
---

# Summary: 01-04 — Human Deployment Checkpoint

## What Was Done

All Phase 1 artifacts deployed to live IPFire appliance and verified:

1. **NIC Identification**: All 6 Intel i226-V NICs identified by MAC address (a8:b8:e0:09:83:39-3e) and mapped to zones
2. **MAC Substitution**: FILL_IN_FROM_NIC_MAP placeholders replaced in nic-map.md, validate-nics.sh, udev rules, and ethernet/settings
3. **Deployment**: udev rules, firewall.local, and backup-include.user deployed to IPFire via SCP
4. **Reboot Persistence**: Clean reboot confirmed all 6 NICs retain zone assignments
5. **Zone Policies**: ORANGE/BLUE masquerade enabled, GREEN-to-ORANGE blocked, drop logging active

## Validation Results

```
validate-phase1.sh: 18 pass, 0 fail — ALL CHECKS PASS
```

- PLAT-01: All 6 NICs match expected MAC-to-zone assignments
- PLAT-02/FW-07: CUSTOMINPUT anti-lockout rules for ports 22 and 444
- PLAT-03: Full directory structure verified
- PLAT-05: Backup include list covers udev rules and firewall.local
- FW-05: Firewall drop logging active (DROP/FORWARDFW entries in /var/log/messages)

## Hardware NIC Map

| Zone | Interface | MAC | PCIe Bus |
|------|-----------|-----|----------|
| RED | red0 | a8:b8:e0:09:83:3b | — |
| GREEN | green0 | a8:b8:e0:09:83:39 | — |
| BLUE | blue0 | a8:b8:e0:09:83:3a | — |
| ORANGE | orange0 | a8:b8:e0:09:83:3c | — |
| GREEN1 | green1 | a8:b8:e0:09:83:3d | — |
| GREEN2 | green2 | a8:b8:e0:09:83:3e | — |

## Decisions

- SSH on port 22 (not 222) — matches IPFire default and sshd_config
- CUSTOMINPUT rules for management host 192.168.1.100 on ports 22 and 444

## Sign-off

Phase 1 Platform Foundation and Firewall is complete. All 12 requirements (PLAT-01 through PLAT-05, FW-01 through FW-07) verified operational on live hardware.
