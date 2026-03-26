---
phase: 07-reproducibility-and-disaster-recovery
plan: "05"
subsystem: infra
tags: [deployment, verification, manifest, drift-detection, validation]

requires:
  - phase: 07-reproducibility-and-disaster-recovery
    plan: "01"
    provides: check-drift.sh, file-manifest.sha256 placeholder
  - phase: 07-reproducibility-and-disaster-recovery
    plan: "04"
    provides: rebuild.sh, deploy-phase scripts

provides:
  - Live file manifest with real SHA256 hashes from 12 managed files
  - Zero drift confirmed on freshly baselined system
  - All Phase 7 artifacts deployed and verified on IPFire
  - validate-all.sh passing (5 PASS, 0 FAIL, 1 SKIP)
  - 7 rollback scripts present and executable on IPFire
  - 12 ADR files accessible on deployed system

key-files:
  created: []
  modified:
    - manifests/file-manifest.sha256
    - scripts/check-drift.sh

deviations:
  - "forward.conf path corrected from /var/ipfire/dns/forward.conf to /etc/unbound/forward.conf (actual IPFire location)"

self-check:
  status: PASSED
  evidence:
    - check-drift.sh --generate baselined 12/12 files (0 skipped)
    - check-drift.sh --verify shows 12 ok, 0 changed, 0 missing
    - validate-all.sh exits 0 (5 PASS, 0 FAIL, 1 SKIP)
    - 7 rollback scripts confirmed on IPFire
    - 12 ADR files confirmed on IPFire
    - file-manifest.sha256 committed with real hashes
---

## Summary

Deployed all Phase 7 artifacts to IPFire and generated the live file manifest. Corrected the forward.conf path from `/var/ipfire/dns/forward.conf` to `/etc/unbound/forward.conf` (actual IPFire location). Generated real SHA256 hashes for all 12 managed files, confirmed zero drift on the freshly baselined system, verified 7 rollback scripts and 12 ADRs are in place, and confirmed the full validation suite continues to pass.
