---
phase: 06-system-hardening-and-validation-suite
plan: "01"
subsystem: infra
tags: [sysctl, hardening, cis, integrity, sha256, reboot-validation, backup, pakfire, ipfire, openssl]

requires:
  - phase: 04-suricata-ids-ips
    provides: check-suricata-integrity.sh pattern used as model for check-integrity.sh
  - phase: 01-platform-foundation-and-firewall
    provides: backup-include.user base file extended with Phase 6 entries

provides:
  - CIS-safe sysctl hardening config for IPFire router (send_redirects fixed, rp_filter, syncookies)
  - Multi-file SHA256 integrity baseline script covering 8 critical config files
  - Pre/post reboot state snapshot and comparison script for persistence verification
  - WUI certificate documentation with extraction commands and fingerprint placeholder
  - Pakfire expected package manifest (guardian) with diff workflow for REPO-03
  - Extended backup include list covering all hardening-related config files

affects:
  - 06-02 (validates these artifacts)
  - 06-03 (deploys these artifacts)
  - 07-reproducible-rebuild (REPO-03 consumes pakfire-manifest-expected.txt)

tech-stack:
  added: []
  patterns:
    - "Multi-file SHA256 baseline: --create-baseline / --verify / --update-baseline modes with exit codes 0/1/2"
    - "Reboot persistence: --snapshot before reboot, --compare after, capture_state() shared function"
    - "Backup include list: one absolute path per line, comment sections per phase"

key-files:
  created:
    - configs/hardening/sysctl-hardening.conf
    - scripts/check-integrity.sh
    - scripts/validate-reboot.sh
    - docs/wui-certificate.md
    - manifests/pakfire-manifest-expected.txt
  modified:
    - configs/firewall/backup-include.user

key-decisions:
  - "check-integrity.sh exit codes: 0=all match, 1=error (missing baseline/file), 2=mismatch — mirrors check-suricata-integrity.sh pattern"
  - "validate-reboot.sh captures iptables hash (not full ruleset) to enable diff-based comparison"
  - "WUI certificate fingerprint left as placeholder — filled during deployment checkpoint (live system required)"
  - "Pakfire manifest lists only guardian — Suricata is bundled in IPFire core and does not appear as Pakfire add-on"
  - "backup-include.user extended with Phase 6 comment section preserving Phase 1 entries"

patterns-established:
  - "capture_state() shared function in validate-reboot.sh: ensures --snapshot and --compare capture identical data formats"
  - "Monitored file list in check-integrity.sh aligned with backup-include.user entries for consistent scope"

requirements-completed: [HARD-01, HARD-02, HARD-03, HARD-04, HARD-05]

duration: 15min
completed: 2026-03-25
---

# Phase 6 Plan 01: System Hardening Artifacts Summary

**CIS-safe sysctl hardening config, 8-file SHA256 integrity monitor, reboot persistence validator, WUI certificate docs, and extended backup scope — all 6 hardening artifacts created for Phase 6 deployment**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-03-25T18:20:00Z
- **Completed:** 2026-03-25T18:35:00Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Created `configs/hardening/sysctl-hardening.conf` with CIS Level 1 router-safe params fixing the send_redirects=1 observation (D-07) and setting rp_filter, syncookies, accept_redirects, accept_source_route for both IPv4 and IPv6
- Created `scripts/check-integrity.sh` extending the check-suricata-integrity.sh pattern to monitor 8 critical config files with --create-baseline, --verify, and --update-baseline modes and correct exit codes (0/1/2)
- Created `scripts/validate-reboot.sh` with --snapshot and --compare modes using a shared capture_state() function to snapshot sysctl values, listening services, iptables hash, and config file hashes before and after reboot
- Created `docs/wui-certificate.md` documenting cert locations, extraction commands (RSA, ECDSA, live TLS), and fingerprint placeholder section for deployment-time population
- Created `manifests/pakfire-manifest-expected.txt` listing guardian as the expected add-on with diff workflow instructions for REPO-03 in Phase 7
- Extended `configs/firewall/backup-include.user` with Phase 6 additions: sysctl.conf, syslog.conf, sshd_config, integrity-baseline.sha256, and pakfire-manifest.txt

## Task Commits

Each task was committed atomically:

1. **Task 1: Sysctl hardening config, integrity script, and reboot snapshot script** - `83dd871` (feat)
2. **Task 2: WUI certificate docs, Pakfire manifest, and extended backup include list** - `36bd0e7` (feat)

**Plan metadata:** _(docs commit hash — recorded after state update)_

## Files Created/Modified

- `configs/hardening/sysctl-hardening.conf` - CIS-safe kernel hardening parameters for IPFire router; deploy via `cat >> /etc/sysctl.conf && sysctl -p`
- `scripts/check-integrity.sh` - Multi-file SHA256 baseline for 8 critical config files; --create-baseline / --verify / --update-baseline
- `scripts/validate-reboot.sh` - Pre/post reboot state snapshot and diff comparison; --snapshot before reboot, --compare after
- `docs/wui-certificate.md` - WUI HTTPS cert documentation with extraction commands and fingerprint placeholder
- `manifests/pakfire-manifest-expected.txt` - Expected Pakfire add-on list (guardian) with diff workflow for REPO-03
- `configs/firewall/backup-include.user` - Extended with Phase 6 entries: sysctl.conf, syslog.conf, sshd_config, integrity baseline, pakfire manifest

## Decisions Made

- **check-integrity.sh exit codes mirror check-suricata-integrity.sh:** 0=all match, 1=error (missing baseline or file), 2=mismatch — consistent exit code convention across integrity scripts
- **validate-reboot.sh captures iptables-save hash (not full ruleset):** Enables clean diff — full ruleset changes with interface names across reboots; hash is stable for identical rulesets
- **WUI certificate fingerprint is a fill-in placeholder:** Cert is on live appliance only; fingerprint must be extracted during deployment checkpoint and recorded here
- **guardian is the only Pakfire add-on listed:** Suricata is bundled in IPFire core since CU131 and does not appear in /opt/pakfire/db/installed/; manifest is accurate as written
- **backup-include.user extended with comment section:** Preserves Phase 1 entries (udev rules, firewall.local) while adding Phase 6 entries under separate comment block for traceability

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required. WUI certificate fingerprint placeholder must be populated during Phase 6 Plan 03 deployment checkpoint.

## Next Phase Readiness

All 6 hardening artifacts are ready for Plan 02 (validation suite) and Plan 03 (deployment):

- `configs/hardening/sysctl-hardening.conf` — ready for validate-phase6.sh HARD-01 check
- `scripts/check-integrity.sh` — ready for validate-phase6.sh HARD-02 syntax check
- `scripts/validate-reboot.sh` — ready for validate-phase6.sh HARD-03 syntax check
- `docs/wui-certificate.md` — ready for validate-phase6.sh HARD-04 existence check
- `manifests/pakfire-manifest-expected.txt` — ready for validate-phase6.sh HARD-05 content check
- `configs/firewall/backup-include.user` — ready for validate-phase6.sh backup scope check

No blockers. All scripts pass `bash -n` syntax check.

---
*Phase: 06-system-hardening-and-validation-suite*
*Completed: 2026-03-25*
