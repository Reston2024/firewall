---
phase: 07-reproducibility-and-disaster-recovery
plan: 01
subsystem: infra
tags: [bash, sha256, drift-detection, backup, manifests]

# Dependency graph
requires:
  - phase: 06-system-hardening-and-validation-suite
    provides: check-integrity.sh pass/fail/warn pattern and exit code conventions

provides:
  - check-drift.sh: full-manifest drift detection script for all 12 managed files
  - file-manifest.sha256: placeholder manifest template with all managed file paths
  - backup-include.user: updated to cover all managed files outside /var/ipfire/ scope

affects:
  - 07-02 (deploy runbook — uses check-drift.sh --generate to baseline after deploy)
  - 07-03 (disaster recovery — file-manifest.sha256 is the recovery validation artifact)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "check-drift.sh follows same pass()/fail()/warn() and exit 0/1/2 convention as check-integrity.sh"
    - "WUI-managed files excluded from manifests to prevent false-positive drift"
    - "Placeholder manifests with 0000... hashes committed to repo; real hashes generated on IPFire"

key-files:
  created:
    - scripts/check-drift.sh
    - manifests/file-manifest.sha256
  modified:
    - configs/firewall/backup-include.user

key-decisions:
  - "check-drift.sh manages ALL 12 managed files; check-integrity.sh monitors 8 critical files with on-box baseline — distinct tools for distinct purposes (D-15)"
  - "WUI-managed files (firewall/config, dhcpd.conf, guardian.conf, time/settings) excluded from drift manifest — they change via WUI and would cause constant false-positive drift (D-21)"
  - "backup-include.user updated to 8 entries by adding /etc/suricata/suricata.yaml — /var/ipfire/ paths excluded as IPFire backs them up natively (D-22)"
  - "Placeholder hashes (0000...0000) committed to repo; real hashes must be generated ON IPFire to avoid CRLF false mismatches"

patterns-established:
  - "Script header includes Deploy-to path, Usage, and Exit codes — matches check-integrity.sh pattern"
  - "MANAGED_FILES array is the single source of truth for what the repo manages"

requirements-completed: [REPO-01, REPO-04]

# Metrics
duration: 7min
completed: 2026-03-26
---

# Phase 07 Plan 01: Drift Detection Infrastructure Summary

**sha256-based full-manifest drift detection script (check-drift.sh) with --verify/--generate modes, placeholder manifest for all 12 managed files, and backup-include.user updated to 8 entries covering all /etc/ and /root/ managed configs**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-26T06:03:59Z
- **Completed:** 2026-03-26T06:06:25Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Created check-drift.sh with full MANAGED_FILES array (12 files), --verify default mode, --generate mode, pass()/fail()/warn() functions, exit codes 0/1/2 — consistent with check-integrity.sh conventions
- Created file-manifest.sha256 placeholder with 12 managed file paths and 0000... hashes for repo visibility; real hashes must be generated on IPFire after deployment
- Updated backup-include.user from 7 to 8 entries by adding /etc/suricata/suricata.yaml (Phase 4 Suricata config was missing from backup coverage)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create check-drift.sh and file-manifest.sha256** - `48f7fce` (feat)
2. **Task 2: Update backup-include.user to cover all managed configs** - `df5424b` (feat)

**Plan metadata:** (docs commit below)

## Files Created/Modified
- `scripts/check-drift.sh` - Full-manifest drift detection; reads file-manifest.sha256, supports --verify and --generate modes
- `manifests/file-manifest.sha256` - Placeholder manifest with all 12 managed file paths; real hashes generated on IPFire via --generate
- `configs/firewall/backup-include.user` - Added /etc/suricata/suricata.yaml; now 8 entries covering all managed files outside /var/ipfire/

## Decisions Made
- WUI-managed files excluded from MANAGED_FILES array — firewall/config, dhcpd.conf, guardian.conf, time/settings change via WUI and would trigger constant false-positive drift alerts
- backup-include.user restricted to /etc/ and /root/ paths only — /var/ipfire/ files backed up natively by IPFire, adding them would be redundant
- Placeholder hashes committed to allow repo to show manifest structure; actual hashing deferred to IPFire to prevent CRLF-induced false mismatches

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
On IPFire after deployment, run:
```bash
bash /root/firewall-repo/scripts/check-drift.sh --generate
```
This populates file-manifest.sha256 with real hashes. Without this step, --verify mode will report all files as CHANGED (placeholder hashes will not match live files).

## Next Phase Readiness
- Drift detection infrastructure complete; check-drift.sh and file-manifest.sha256 are ready for deploy runbook (07-02)
- backup-include.user in sync with full managed file set
- No blockers for remaining 07-xx plans

---
*Phase: 07-reproducibility-and-disaster-recovery*
*Completed: 2026-03-26*
