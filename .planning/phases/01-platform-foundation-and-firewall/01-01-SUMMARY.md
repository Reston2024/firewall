---
phase: 01-platform-foundation-and-firewall
plan: 01
subsystem: platform
tags: [git, repo-structure, nic-validation, scripts, docs, bash]
dependency_graph:
  requires: []
  provides: [repo-structure, validate-nics, validate-phase1, nic-map-template, deployment-checklist]
  affects: [01-02, 01-03, 01-04]
tech_stack:
  added: [bash]
  patterns: [mac-based-nic-validation, phase-integration-test-runner]
key_files:
  created:
    - scripts/validate-nics.sh
    - scripts/validate-phase1.sh
    - docs/nic-map.md
    - docs/deployment-checklist.md
    - configs/udev/.gitkeep
    - configs/ethernet/.gitkeep
    - configs/firewall/.gitkeep
    - services/.gitkeep
    - validation/.gitkeep
    - rollback/.gitkeep
    - manifests/.gitkeep
    - decision-log/.gitkeep
    - docs/decisions/.gitkeep
    - .gitignore
    - README.md
  modified: []
key_decisions:
  - Git repo directory structure follows research-prescribed layout with 9 required subdirectories
  - validate-nics.sh uses FILL_IN_FROM_NIC_MAP placeholders — human must populate from hardware before Plan 02
  - validate-phase1.sh sources validate-nics.sh via bash call, checks CUSTOMINPUT (222/444), PLAT-03/05, FW-05/07
  - Driver column added to NIC map table (per NIC map spec from RESEARCH.md)
metrics:
  duration: 10m
  completed: 2026-03-21
  tasks_completed: 3
  files_created: 15
  files_modified: 0
---

# Phase 01 Plan 01: Repository Structure and Validation Scripts Summary

Git repository initialized with 9 required subdirectories, bash validation scripts for NIC MAC-to-zone checking and full Phase 1 integration testing, plus NIC map template and deployment checklist docs.

## What Was Created

### Directory Structure (9 subdirectories)

All required directories created with `.gitkeep` files for git tracking:

| Directory | Purpose |
|-----------|---------|
| `configs/udev/` | udev NIC persistence rules |
| `configs/ethernet/` | IPFire ethernet/settings export |
| `configs/firewall/` | firewall.local and zone policy docs |
| `services/` | Future: DHCP, DNS, NTP configs |
| `validation/` | Future: test artifacts |
| `rollback/` | Future: rollback procedures |
| `manifests/` | Future: Pakfire addon manifest |
| `decision-log/` | Future: ADR index |
| `docs/decisions/` | ADR files |

### Scripts

**`scripts/validate-nics.sh`**
- Checks all 6 NICs (red0, green0, blue0, orange0, green1, green2) by MAC address
- Exits 0 on all pass, exits 1 on any mismatch or missing interface
- Contains `FILL_IN_FROM_NIC_MAP` placeholders for each zone's expected MAC
- Skips unconfigured MACs gracefully (SKIP output, not FAIL)
- Prints "ALL NICS PASS" on success

**`scripts/validate-phase1.sh`**
- Full Phase 1 integration test runner
- Calls `validate-nics.sh` as first check (PLAT-01)
- Checks CUSTOMINPUT iptables rules for ports 222 and 444 (PLAT-02/FW-07)
- Checks repo directory structure (PLAT-03)
- Checks backup include.user for udev + firewall.local paths (PLAT-05)
- Checks firewall drop logging entries (FW-05)
- Checks firewall.local exists and is executable (FW-07)
- Prints "ALL CHECKS PASS" on success

### Documentation

**`docs/nic-map.md`**
- 6-row NIC assignment table with FILL_IN placeholders (MAC, PCIe Bus, Driver)
- IP addressing table with FILL_IN for GREEN, GREEN Bridge x2, BLUE, ORANGE
- Physical port identification commands (ip link, ethtool, lspci, LED blink method)
- Post-reboot verification steps

**`docs/deployment-checklist.md`**
- PLAT-04 steps: hostname, timezone, kernel version (uname -r = 6.18.7)
- NIC identification workflow
- Plan 02 deployment steps (udev rules, firewall.local, backup include)
- Reboot persistence test
- Plan 03 deployment steps (zone policies)
- Sign-off criteria (ALL NICS PASS, ALL CHECKS PASS, port 222/444 access)

### Other Files

- `.gitignore`: OS artifacts, backup files, sensitive keys (.pem, id_rsa)
- `README.md`: Project overview, directory structure table, quick commands

## Commits

| Hash | Message | Files |
|------|---------|-------|
| f86d4da | chore(01-01): initialize repo structure | 11 files (dirs + .gitignore + README.md) |
| 509a4e9 | docs(01-01): add NIC map template and deployment checklist | docs/nic-map.md, docs/deployment-checklist.md |
| 174b947 | feat(01-01): add NIC and Phase 1 validation scripts | scripts/validate-nics.sh, scripts/validate-phase1.sh |

## Placeholders Requiring Human Input

Before Plan 02 can be executed, the human must:

1. **Identify physical NIC-to-zone mapping** using the commands in `docs/nic-map.md`
2. **Fill in the NIC Assignment Table** in `docs/nic-map.md` — all cells marked `FILL_IN`
3. **Update MAC variables in `scripts/validate-nics.sh`** — replace all 6 `FILL_IN_FROM_NIC_MAP` values with real MACs
4. **Update `configs/udev/30-persistent-network.rules`** with real MAC addresses (created in Plan 02)
5. **Update `configs/ethernet/settings`** with real MACs and IPs (created in Plan 02)

## Next Step

Human must complete NIC physical identification (see `docs/nic-map.md` identification commands) before Plan 02 udev rules can be finalized. Plan 02 depends on real MAC addresses being known.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Enhancement] Added Driver column to NIC map table**
- **Found during:** Task 2
- **Issue:** Plan frontmatter specifies `| Port | Zone | Device | MAC | PCIe Bus | Driver |` but initial table omitted Driver column
- **Fix:** Added Driver column with FILL_IN placeholder to NIC assignment table
- **Files modified:** docs/nic-map.md
- **Commit:** 509a4e9

**2. [Rule 2 - Missing content] Added GREEN Bridge rows to IP Addressing table**
- **Found during:** Task 2 verification
- **Issue:** FILL_IN count was 10 (below required 12); IP table was missing green1 and green2 rows
- **Fix:** Added green1 and green2 bridge rows to IP Addressing table
- **Files modified:** docs/nic-map.md
- **Commit:** 509a4e9

## Known Stubs

- `scripts/validate-nics.sh`: All 6 `*_EXPECTED_MAC` variables set to `FILL_IN_FROM_NIC_MAP` — requires human hardware identification to be populated. Script handles stubs gracefully (SKIP, not FAIL). Plan 02 resolves this.
- `docs/nic-map.md`: All 12 table FILL_IN cells — requires physical NIC identification on hardware. Plan 02 resolves this.

These stubs are intentional and documented. They do not prevent Plan 01's goal (repo structure + validation framework), but Plan 02 cannot be fully executed until a human completes the NIC identification.

## Self-Check: PASSED
