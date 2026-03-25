---
phase: 06-system-hardening-and-validation-suite
plan: "03"
subsystem: infra
tags: [hardening, deployment, runbook, sysctl, permissions, integrity-baseline, wui-certificate, ipfire]

requires:
  - phase: 06-system-hardening-and-validation-suite
    plan: "01"
    provides: sysctl-hardening.conf, check-integrity.sh, validate-reboot.sh, backup-include.user, pakfire-manifest-expected.txt
  - phase: 06-system-hardening-and-validation-suite
    plan: "02"
    provides: validate-phase6.sh, validate-all.sh

provides:
  - Step-by-step hardening deployment runbook covering all 9 phases of IPFire hardening
  - WUI certificate fingerprints (pending human execution)
  - Live pakfire-manifest.txt from IPFire system (pending human execution)
  - validate-phase6.sh passing on live IPFire (pending human execution)

affects:
  - 06-04 (reboot persistence test — requires pre-reboot snapshot from this plan)

tech-stack:
  added: []
  patterns:
    - "Deploy scripts via scp + CRLF fix: Windows-to-IPFire file transfer always needs sed -i 's/\\r$//' fix"
    - "Order constraint for hardening: sysctl -> permissions -> integrity baseline (baseline hashes files after changes)"

key-files:
  created:
    - docs/hardening-deployment-runbook.md
  modified: []

key-decisions:
  - "Hardening order enforced in runbook: sysctl first, then file permissions, then integrity baseline — baseline must hash post-hardening state"

duration: partial (checkpoint reached at Task 2 — human deployment required)
completed: 2026-03-25
---

# Phase 6 Plan 03: Hardening Deployment Runbook Summary

**9-section hardening deployment runbook for IPFire, covering sysctl hardening, file permission lockdown, service audit, WUI certificate documentation, integrity baseline, validate-phase6.sh execution, and pre-reboot snapshot capture**

## Performance

- **Duration:** ~5 min (Task 1 automated; Task 2 is human deployment checkpoint)
- **Started:** 2026-03-25T18:29:40Z
- **Completed:** 2026-03-25 (partial — checkpoint at Task 2)
- **Tasks:** 1 of 2 automated tasks complete; 1 checkpoint awaiting human action

## Accomplishments

- Created `docs/hardening-deployment-runbook.md` (385 lines) with 9 numbered sections covering the full hardening deployment sequence
- Section 0: Prerequisites checklist
- Section 1: Deploy scripts/configs/manifests/docs to IPFire via scp with CRLF fix
- Section 2: Sysctl hardening — append sysctl-hardening.conf to /etc/sysctl.conf, apply with sysctl -p, verify ip_forward=1
- Section 3: File permission lockdown — sshd_config 600, firewall.local 700, .ssh/ 700
- Section 4: Service audit — ss -tlnp expected ports, live Pakfire manifest generation and diff
- Section 5: Backup include list deployment
- Section 6: WUI certificate extraction (openssl commands for RSA and ECDSA certs)
- Section 7: Integrity baseline creation — AFTER all hardening changes
- Section 8: validate-phase6.sh execution with expected results table and failure troubleshooting
- Section 9: Pre-reboot snapshot capture (DO NOT reboot — Plan 04 handles that)
- Sign-off checklist with per-section verification items

## Task Commits

Each task was committed atomically:

1. **Task 1: Create hardening deployment runbook** - `1786f89` (docs)
2. **Task 2: Deploy hardening to IPFire (CHECKPOINT)** - human action required

## Files Created/Modified

- `docs/hardening-deployment-runbook.md` — 9-section runbook for deploying all Phase 6 hardening to live IPFire; order constraint documented (sysctl -> permissions -> baseline)

## Decisions Made

- **Hardening order documented as hard constraint:** sysctl first, file permissions second, integrity baseline LAST — the baseline must hash files in their final hardened state or it will fail on first verify

## Deviations from Plan

None - plan executed exactly as written through Task 1 (automated). Task 2 is a blocking human-verify checkpoint.

## Known Stubs

- `docs/wui-certificate.md` — SHA256 Fingerprint fields remain as placeholders; must be filled during human deployment in Task 2 (Section 6 of runbook)
- `manifests/pakfire-manifest.txt` — live manifest not yet generated; generated during Task 2 (Section 4 of runbook) and must be committed to repo

## Issues Encountered

None.

## User Setup Required

Task 2 requires human execution:
1. SSH to IPFire and follow `docs/hardening-deployment-runbook.md` sections 1 through 9
2. Update `docs/wui-certificate.md` with actual certificate fingerprints from Section 6
3. Copy generated `manifests/pakfire-manifest.txt` back to dev machine and commit
4. Confirm validate-phase6.sh exits 0
5. Signal to orchestrator: "hardening deployed"

## Next Phase Readiness

After human Task 2 completion:
- Pre-reboot snapshot at `/root/reboot-snapshot.txt` will exist on IPFire
- validate-phase6.sh will pass all HARD checks
- Plan 04 (reboot persistence test) can proceed

---

## Self-Check

- [x] `docs/hardening-deployment-runbook.md` exists
- [x] Commit `1786f89` exists

## Self-Check: PASSED

---
*Phase: 06-system-hardening-and-validation-suite*
*Completed (partial): 2026-03-25*
