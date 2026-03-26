---
phase: 08-milestone-gap-closure
plan: "02"
subsystem: scripts-and-docs
tags: [bug-fix, drift-detection, runbook, validate-all, check-drift, telemetry]
dependency_graph:
  requires: []
  provides: [INT-7A-closed, INT-4A-closed, INT-2A-closed]
  affects: [TEL-06, DASH-03, VAL-11, validate-all.sh, check-drift.sh, telemetry-deployment-runbook.md]
tech_stack:
  added: []
  patterns: []
key_files:
  created: []
  modified:
    - scripts/validate-all.sh
    - scripts/check-drift.sh
    - docs/telemetry-deployment-runbook.md
decisions:
  - "INT-7A closed: validate-all.sh line 88 sourced /opt/telemetry/telemetry/.env (double path) — fixed to /opt/telemetry/.env; TEL-06 and DASH-03 Grafana API checks will now find GF_SECURITY_ADMIN_PASSWORD"
  - "INT-4A closed: /var/ipfire/ethernet/settings removed from check-drift.sh MANAGED_FILES; file is WUI-managed per D-21 and caused false-positive drift on any WUI network settings change"
  - "INT-2A closed: telemetry runbook Section 2 rewritten to verify rsyslog IS running (relay role) instead of instructing to stop/disable it; architecture is rsyslog->file->Alloy tailing"
metrics:
  duration: "~3 minutes"
  completed: "2026-03-26T07:57:00Z"
  tasks_completed: 2
  files_modified: 3
---

# Phase 08 Plan 02: Script Wiring Defects and Documentation Errors Summary

Fix three targeted defects identified in the v1.0 milestone audit: a double-path .env source in validate-all.sh (MEDIUM INT-7A), a WUI-managed file in the drift detection array (LOW INT-4A), and an incorrect rsyslog disable instruction in the telemetry runbook (LOW INT-2A).

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Fix validate-all.sh .env path + remove ethernet/settings from check-drift.sh | debea91 | scripts/validate-all.sh, scripts/check-drift.sh |
| 2 | Correct telemetry runbook Section 2 rsyslog instruction | 80cfd50 | docs/telemetry-deployment-runbook.md |

## Changes Made

### Task 1: Script Defect Fixes

**Fix 1 — validate-all.sh line 88 (INT-7A, MEDIUM)**

Changed:
```bash
"source /opt/telemetry/telemetry/.env && sudo -E bash /opt/telemetry/scripts/validate-phase5.sh"
```
To:
```bash
"source /opt/telemetry/.env && sudo -E bash /opt/telemetry/scripts/validate-phase5.sh"
```

The double-path `telemetry/telemetry` caused the `.env` source to silently fail in the SSH command, leaving `GF_SECURITY_ADMIN_PASSWORD` unset. This made the TEL-06 Grafana API check and DASH-03 dashboard check SKIP instead of PASS during every `validate-all.sh` run.

**Fix 2 — check-drift.sh MANAGED_FILES (INT-4A, LOW)**

Removed from MANAGED_FILES array:
```bash
# IPFire ethernet settings (WUI-managed but tracked in integrity baseline)
/var/ipfire/ethernet/settings
```

`/var/ipfire/ethernet/settings` is a WUI-managed file. Including it in drift detection causes false-positive drift whenever a user changes network settings via the IPFire WUI — per decision D-21, WUI-managed files are excluded from the drift manifest. The MANAGED_FILES array now has 11 entries (was 12).

### Task 2: Runbook Section 2 Rewrite (INT-2A, LOW)

The original Section 2 title was "Check for rsyslog Conflict on supportTAK-server (Pre-Flight)" and Step 2.2 instructed to stop and disable rsyslog. This contradicts the deployed architecture where rsyslog acts as a relay (receives UDP 514 from IPFire, writes to `/var/log/ipfire/`, and Alloy tails the output files).

Changes made:
- Section 2 title changed to "Verify rsyslog Relay on supportTAK-server (Pre-Flight)"
- Step 2.1 now checks that rsyslog IS running and bound to UDP 514
- Step 2.2 now starts rsyslog if not running (was: stop and disable)
- Step 2.3 updated to reflect rsyslog presence is the success case
- Section 2 note rewrites relay architecture explanation
- Section 2 checkbox updated to: "rsyslog is running and bound to UDP 514 on supportTAK-server"
- CRITICAL WARNINGS section bullet updated to describe rsyslog as required relay
- Section 5 Note updated (port 514 must have rsyslog relay, not be free)
- Sign-Off Checklist TEL-02 items updated to reflect relay role
- Section 7 troubleshooting table TEL-02 row updated (was: stop rsyslog; now: start rsyslog)

## Verification Results

| Check | Result |
|-------|--------|
| No "telemetry/telemetry" in validate-all.sh | PASS |
| "source /opt/telemetry/.env" present in validate-all.sh | PASS |
| bash -n scripts/validate-all.sh | PASS |
| No "ethernet/settings" in check-drift.sh | PASS |
| bash -n scripts/check-drift.sh | PASS |
| check-drift.sh MANAGED_FILES has 11 entries (was 12) | PASS |
| No "stop rsyslog" in runbook | PASS |
| No "disable rsyslog" in runbook | PASS |
| "rsyslog Relay" in runbook Section 2 title | PASS |
| "start rsyslog" in runbook | PASS |

## Deviations from Plan

**Auto-fixed: Stale runbook references beyond Section 2 and CRITICAL WARNINGS**

The plan specified fixing Section 2 and the CRITICAL WARNINGS bullet. During implementation, additional stale references were discovered that contradicted the corrected architecture:

1. Section 5 Note still said "Port 514 must be free on supportTAK-server" — corrected to explain rsyslog relay role (Rule 1 - Bug)
2. Sign-Off Checklist TEL-02 still said "rsyslog not binding port 514 (disabled if present)" — corrected to reflect relay role (Rule 1 - Bug)
3. Section 7 troubleshooting table TEL-02 still had the old "stop rsyslog && disable rsyslog" command — corrected to "start rsyslog && enable rsyslog" (Rule 1 - Bug)

These were all in-file consistency fixes driven by the same root cause (INT-2A). No architectural changes were made.

## Known Stubs

None — all three defects are fully corrected with no placeholder content.

## Self-Check: PASSED

Files exist:
- scripts/validate-all.sh: FOUND
- scripts/check-drift.sh: FOUND
- docs/telemetry-deployment-runbook.md: FOUND
- .planning/phases/08-milestone-gap-closure/08-02-SUMMARY.md: FOUND

Commits exist:
- debea91: FOUND (Task 1 — fix INT-7A and INT-4A)
- 80cfd50: FOUND (Task 2 — fix INT-2A)
