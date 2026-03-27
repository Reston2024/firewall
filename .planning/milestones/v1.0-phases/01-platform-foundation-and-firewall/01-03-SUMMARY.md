---
phase: 01-platform-foundation-and-firewall
plan: 03
subsystem: firewall-policy
tags: [firewall, zone-policy, runbook, validation, iptables, masquerade, nat, drop-logging]
dependency_graph:
  requires: [01-01]
  provides: [zone-policy-runbook, validate-firewall-script]
  affects: [01-04]
tech_stack:
  added: []
  patterns: [bash-validation-scripts, wui-runbook-pattern, iptables-CUSTOMINPUT]
key_files:
  created:
    - docs/zone-policy-runbook.md
    - scripts/validate-firewall.sh
  modified: []
decisions:
  - "FW-02 masquerade: documented as WUI-only action (anti-pattern to hand-roll iptables MASQUERADE)"
  - "FW-05 drop logging: script uses SKIP (not FAIL) when no log entries found — pre-condition requires triggering blocked traffic first"
  - "FW-06 persistence: validated via /etc/init.d/firewall existence + runlevel check, not by running a reboot"
metrics:
  duration_minutes: 2
  completed_date: "2026-03-22"
  tasks_completed: 2
  files_created: 2
  files_modified: 0
---

# Phase 01 Plan 03: Zone Policy Runbook and Firewall Validation Summary

**One-liner:** WUI runbook for IPFire zone policies (FW-01 through FW-06) with automated bash validation of CUSTOMINPUT, firewall.local, and drop logging.

## What Was Created

### docs/zone-policy-runbook.md

Step-by-step WUI navigation instructions for all 6 firewall requirements:

- **Default posture table** — documents what IPFire provides correctly by default (RED inbound blocked, GREEN masquerade enabled, conntrack active) vs. what requires explicit action (ORANGE/BLUE masquerade disabled, GREEN-to-ORANGE OPEN)
- **FW-01** — stateful firewall verification (nmap from external)
- **FW-02** — ORANGE and BLUE masquerade enable steps with WUI path (`Firewall > Masquerade`) and checkip.amazonaws.com verification for all 3 zones
- **FW-03** — block GREEN-to-ORANGE with critical warning ("OPEN by default"), pinhole rule pattern, zone isolation verification
- **FW-04** — DNAT/port-forwarding test rule via `Firewall > Port Forwarding`
- **FW-05** — drop logging via `Firewall > Firewall Options` with FORWARDFW log prefix documentation
- **FW-06** — reboot persistence verification steps
- **Verification matrix** — post-configuration test table for all requirements

### scripts/validate-firewall.sh

Automated bash script (executable, exits 0/1) checking the locally-verifiable subset of firewall requirements:

- `CUSTOMINPUT` chain check for `dpt:222` (SSH) and `dpt:444` (WUI) ACCEPT rules
- `/etc/sysconfig/firewall.local` existence and executability
- `/var/log/messages` FORWARDFW/DROP log entries (SKIP if none — requires traffic trigger)
- `/etc/init.d/firewall` persistence mechanism existence + runlevel check
- Informational MASQUERADE rule count and FORWARDFW chain size
- Clearly documents which FW requirements (FW-01, FW-02, FW-03, FW-04) require manual verification from external hosts

## Requirements Addressed

| Requirement | Coverage | Verification Method |
|-------------|----------|---------------------|
| FW-01 | Runbook only | nmap from external (manual) |
| FW-02 | Runbook + MASQUERADE info check | curl checkip.amazonaws.com (manual) |
| FW-03 | Runbook only | ping GREEN→ORANGE (manual) |
| FW-04 | Runbook only | curl to DNAT port (manual) |
| FW-05 | Automated | grep FORWARDFW in /var/log/messages |
| FW-06 | Automated (partial) | /etc/init.d/firewall + runlevel check |
| FW-07/PLAT-02 | Automated | CUSTOMINPUT dpt:222 and dpt:444 |

## Manual-Only Requirements (FW-01, FW-02, FW-03, FW-04)

These requirements cannot be verified locally on IPFire — they require live network clients:

- **FW-01:** nmap from an external host against the WAN IP — all ports must show `filtered`
- **FW-02:** `curl http://checkip.amazonaws.com` from GREEN, ORANGE, and BLUE hosts — must return WAN IP
- **FW-03:** `ping ORANGE_HOST_IP` from a GREEN host — must time out
- **FW-04:** `curl http://WAN_IP:8080` from an external host to reach the DNAT target

Complete instructions with exact WUI steps are in `docs/zone-policy-runbook.md`.

## Next Steps

Plans 01-02 and 01-03 are both Wave 2 (parallel). Once both complete, proceed to:

- **Plan 04 (01-04):** Human deployment checkpoint — the human applies all WUI actions from this runbook, deploys firewall.local and udev rules to the live IPFire box, and runs `validate-phase1.sh` and `validate-firewall.sh` to confirm Phase 1 completion.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — both files are complete and functional. The runbook contains `YOUR_WAN_IP` and `ORANGE_HOST_IP` placeholders by design (these are network-specific values the human fills in during execution).

## Self-Check: PASSED

- `docs/zone-policy-runbook.md` — FOUND
- `scripts/validate-firewall.sh` — FOUND
- Commit `baa7ba5` (zone-policy-runbook) — FOUND
- Commit `30f3c67` (validate-firewall.sh) — FOUND
