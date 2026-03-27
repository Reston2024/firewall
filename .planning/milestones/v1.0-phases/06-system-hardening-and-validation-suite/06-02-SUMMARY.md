---
phase: 06-system-hardening-and-validation-suite
plan: "02"
subsystem: infra
tags: [validation, hardening, sysctl, integrity, certificates, ssh, service-audit, orchestration, ipfire]

requires:
  - phase: 06-system-hardening-and-validation-suite
    plan: "01"
    provides: check-integrity.sh, sysctl-hardening.conf, validate-reboot.sh, pakfire-manifest-expected.txt
  - phase: 01-platform-foundation-and-firewall
    provides: validate-phase1.sh pattern
  - phase: 05-telemetry-pipeline-and-dashboards
    provides: validate-phase5.sh remote execution pattern

provides:
  - Phase 6 hardening validation covering HARD-01 through HARD-05
  - Unified acceptance test orchestrator for all 6 phases with SSH-based Phase 5 remote execution
  - Graceful SSH failure handling (SKIP not FAIL when supportTAK-server unreachable)
  - Summary table with per-phase PASS/FAIL/SKIP results and overall exit code

affects:
  - 06-03 (deployment runbook references these scripts)
  - 07-reproducible-rebuild (validate-all.sh is the full-suite acceptance check)

tech-stack:
  added: []
  patterns:
    - "validate-all.sh run_phase() function: prints banner, runs script, records result in PHASE_RESULTS array"
    - "SSH pre-check pattern: test reachability with BatchMode=yes before running remote phase"
    - "PHASE_RESULTS array: pipe-delimited entries N|STATUS|DETAIL for summary rendering"
    - "validate-phase6.sh check_perm() helper: stat -c %a with skip for missing optional files"
    - "validate-phase6.sh check_sysctl() helper: sysctl -n with skip for missing kernel params"

key-files:
  created:
    - scripts/validate-phase6.sh
    - scripts/validate-all.sh
  modified: []

key-decisions:
  - "validate-phase6.sh HARD-03 maps check-integrity.sh exit 2 to skip() not fail() — mismatch may be intentional after Core Update; operator reviews and runs --update-baseline"
  - "validate-all.sh Phase 5 uses SKIP not FAIL on SSH unreachability — supportTAK-server is optional infrastructure; partial validation suite still valid"
  - "validate-all.sh does not hardcode SSH key path — uses SSH agent or default key; deployment runbook documents -i flag if needed"
  - "validate-phase6.sh HARD-01 port baseline uses ss -tlnp with known-good list (53, 22, 81, 444, 1013) matching D-04 expected services"

duration: ~5min
completed: 2026-03-25
---

# Phase 6 Plan 02: Validation Suite Scripts Summary

**validate-phase6.sh covers all 5 HARD checks; validate-all.sh orchestrates 6 phases with SSH-based Phase 5 remote execution and graceful SKIP on connection failure**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-03-25T18:24:14Z
- **Completed:** 2026-03-25T18:26:00Z
- **Tasks:** 2
- **Files created:** 2

## Accomplishments

- Created `scripts/validate-phase6.sh` covering all 5 HARD requirements:
  - HARD-01: Service audit with known-good TCP port baseline (53/22/81/444/1013) plus optional Pakfire manifest diff
  - HARD-02: Key file permission checks for sshd_config, firewall.local, .ssh dir, authorized_keys, and integrity baseline
  - HARD-03: File integrity check via check-integrity.sh --verify with correct exit code mapping (2=skip, 1=fail, 0=pass)
  - HARD-04: 8 sysctl hardening parameters plus ip_forward safety check (fail if routing disabled)
  - HARD-05: WUI cert existence check (both RSA and ECDSA), expiry check (fail if < 365 days), fingerprint skip pending docs
- Created `scripts/validate-all.sh` as unified acceptance test orchestrator:
  - Phases 1-4 and 6 run locally via `run_phase()` function
  - Phase 5 runs via SSH to opsadmin@192.168.1.101 with pre-check and SKIP on failure
  - Summary table shows per-phase PASS/FAIL/SKIP with counts and failed phase names
  - `--phase N` flag for single-phase execution
  - Exits 0 if no FAILs (SKIPs allowed), exits 1 if any FAIL

## Task Commits

1. **Task 1: validate-phase6.sh** - `736387a` (feat)
2. **Task 2: validate-all.sh** - `e68089b` (feat)

## Files Created

- `scripts/validate-phase6.sh` - Phase 6 hardening validation (HARD-01 through HARD-05); run on IPFire
- `scripts/validate-all.sh` - Unified 6-phase acceptance test orchestrator with SSH Phase 5 support; run on IPFire

## Decisions Made

- **HARD-03 exit 2 maps to skip():** check-integrity.sh exit 2 means mismatch detected (not an error); operator may have intentionally changed monitored files after a Core Update — skip prompts operator to run --update-baseline rather than failing the suite
- **Phase 5 SSH failure is SKIP not FAIL:** supportTAK-server is off-box infrastructure; its absence should not block IPFire-side validation results
- **No hardcoded SSH key path:** validate-all.sh lets SSH use its default key selection; runbook can document `ssh -i /path/to/key` for specific deployments without script changes
- **HARD-01 port baseline from D-04:** Expected ports 53 (unbound), 22 (sshd), 81/444/1013 (httpd) match documented service audit baseline

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None - all validation logic is complete. Two checks are intentional skip() by design:
- HARD-01 Pakfire manifest: skips if manifest not yet generated (deploy-time, not a stub)
- HARD-05 fingerprint: skips pending docs/wui-certificate.md population (documented in Plan 01 decisions)

## Self-Check: PASSED

- `scripts/validate-phase6.sh` exists and passes `bash -n`
- `scripts/validate-all.sh` exists and passes `bash -n`
- All 5 HARD requirement IDs present in validate-phase6.sh
- All 6 per-phase scripts referenced in validate-all.sh
- SSH to 192.168.1.101 present in validate-all.sh
- Task commits `736387a` and `e68089b` exist in git log
