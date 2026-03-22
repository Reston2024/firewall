---
phase: 02-core-network-services
plan: 01
subsystem: dhcp-validation
tags: [dhcp, validation, scripts, config-templates]
dependency_graph:
  requires: []
  provides:
    - scripts/validate-phase2.sh
    - configs/dhcp/dhcpd.conf.local
    - configs/dhcp/fixleases.template
    - configs/dhcp/README.md
  affects:
    - Phase 2 Plans 02-03 (validation infrastructure they depend on)
    - Phase 2 deploy runbook (DHCP artifacts are the deploy targets)
tech_stack:
  added: []
  patterns:
    - pass()/fail()/skip() validation script pattern (consistent with Phase 1)
    - Two-file DHCP consistency model (fixleases + dhcpd.conf)
    - dhcpd.conf.local for WUI-override-safe DHCP customizations
key_files:
  created:
    - scripts/validate-phase2.sh
    - configs/dhcp/dhcpd.conf.local
    - configs/dhcp/fixleases.template
    - configs/dhcp/README.md
  modified: []
decisions:
  - validate-phase2.sh uses SKIP (not FAIL) for SVC-02 static leases — no static leases configured yet is a valid state during initial deployment
  - SVC-02 fixleases check is SKIP if file absent — template exists in repo, human deploys during Plan 03 checkpoint
  - SVC-04 wire verification (tcpdump port 53/853) is always SKIP — requires live RED interface and cannot be automated from repo
metrics:
  duration: 7m
  completed_date: 2026-03-22
  tasks_completed: 2
  files_created: 4
  files_modified: 0
---

# Phase 02 Plan 01: DHCP Config Templates and Phase 2 Validation Script Summary

**One-liner:** Phase 2 validation script covering DHCP/DNS/NTP (SVC-01 through SVC-06) plus ready-to-SCP DHCP artifacts using the two-file consistency model.

## What Was Built

### scripts/validate-phase2.sh (154 lines)

The Nyquist Wave 0 validation script for Phase 2. Runs on IPFire. Checks all six requirements:

- **SVC-01:** Verifies `dhcpd.conf` contains correct routers, domain-name-servers, and ntp-servers (all 192.168.1.1). Checks dhcpd service running.
- **SVC-02:** Counts `hardware ethernet` host blocks in `dhcpd.conf`. SKIP (not FAIL) if none — valid initial state.
- **SVC-03:** Uses `drill -D sigok.verteiltesysteme.net` to check AD flag. Checks SERVFAIL for `sigfail.verteiltesysteme.net`. Checks unbound running.
- **SVC-04:** Greps `/etc/unbound/forward.conf` for `forward-tls-upstream: yes`, `@853#` entries, and Cloudflare/Quad9 hostnames. Wire verification is SKIP (needs tcpdump).
- **SVC-05:** Uses `ntpq -p` star-prefix pattern for sync check. Checks `ss -ulnp` for port 123 (serving clients). Checks ntpd running.
- **SVC-06:** Scans `/etc/rc.d/rc3.d/` for `S.*dhcp`, `S.*unbound`, `S.*ntp` symlinks. Reboot persistence is SKIP.

Pattern follows `validate-phase1.sh` exactly: `pass()`, `fail()`, `skip()` functions, header with date, `Results: N pass, N fail` footer, exit 0/1.

### configs/dhcp/dhcpd.conf.local

Ready-to-SCP customization file for `/var/ipfire/dhcp/dhcpd.conf.local` on IPFire. This file survives WUI regeneration and Core Updates. Includes:
- NTP option documentation (option ntp-servers 192.168.1.1)
- Deploy and syntax-check commands
- Commented-out domain-name and log-facility options for easy enabling

### configs/dhcp/fixleases.template

7-field CSV template with full field documentation:
- `MAC,IP,hostname,enabled,nextIP,remark,interface`
- IP range design (statics 192.168.1.2-99, dynamic 192.168.1.100-200)
- Complete deploy steps including CRLF fix (`sed -i 's/\r$//'`)
- WUI toggle requirement documented with warning
- Three example entries with `aa:bb:cc:dd:ee` placeholder MACs

### configs/dhcp/README.md

Two-file DHCP consistency model documentation:
- File roles table (dhcpd.conf vs dhcpd.conf.local vs fixleases)
- Deployment order (6 steps from WUI to validated service)
- IP range design table
- Two-file consistency model explanation including warning signs of inconsistency
- Post-WUI-change export commands for reproducibility

## Key Patterns Documented

### Two-File DHCP Consistency Model

IPFire DHCP requires both `fixleases` (WUI data store) and `dhcpd.conf` (daemon config) to be consistent. Writing `fixleases` alone does NOT make static leases active — the WUI must generate `host` blocks in `dhcpd.conf` by toggling each entry. This is the #1 DHCP pitfall on IPFire and is now explicitly documented in all three DHCP artifacts.

### NTP Warning Pitfall

`option ntp-servers 192.168.1.1` in `dhcpd.conf` must be paired with "Provide time to local network" enabled in WUI > Services > Time Server. Setting the DHCP option without the NTP server generates a WUI WARNING and gives clients a non-functional NTP address.

### CRLF Fix Requirement

Deploying files from Windows to IPFire via SCP introduces CRLF line endings that break CSV parsing. The `sed -i 's/\r$//'` step is documented in `fixleases.template` deploy instructions (Phase 1 lesson preserved).

## What Plan 02 Builds On Top Of

Plan 02 (services deployment runbook) and Plan 03 (checkpoint: deploy to IPFire) use these artifacts:
- `validate-phase2.sh` is the acceptance gate for all Phase 2 work
- `configs/dhcp/dhcpd.conf.local` is deployed during Plan 03 SCP step
- `configs/dhcp/fixleases.template` is edited with real MACs and deployed during Plan 03

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1: DHCP config templates | fabb753 | feat(02-01): add DHCP config templates and README |
| 2: validate-phase2.sh | 1415a0b | feat(02-01): add validate-phase2.sh covering SVC-01 through SVC-06 |

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — all files are complete and executable. The `fixleases.template` example entries use `aa:bb:cc:dd:ee` placeholder MACs by design (template, not deployment artifact). The human populates real MACs during Plan 03.

## Self-Check: PASSED

Files exist:
- scripts/validate-phase2.sh: FOUND
- configs/dhcp/dhcpd.conf.local: FOUND
- configs/dhcp/fixleases.template: FOUND
- configs/dhcp/README.md: FOUND

Commits exist:
- fabb753: FOUND
- 1415a0b: FOUND
