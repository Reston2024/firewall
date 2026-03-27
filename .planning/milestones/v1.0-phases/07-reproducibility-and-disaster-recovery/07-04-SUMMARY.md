---
phase: 07-reproducibility-and-disaster-recovery
plan: 04
subsystem: infra
tags: [bash, rebuild, deploy, scp, ssh, rollback, idempotent, pakfire]

# Dependency graph
requires:
  - phase: 07-01
    provides: check-drift.sh --generate for manifest generation in rebuild.sh
  - phase: 07-03
    provides: rollback/ directory and rollback scripts deployed via SCP in rebuild.sh
  - phase: 06-system-hardening-and-validation-suite
    provides: check-integrity.sh --create-baseline called by deploy-phase6.sh
  - phase: 01-06-all
    provides: validate-all.sh called as acceptance gate in rebuild.sh

provides:
  - rebuild.sh: master rebuild orchestrator running from dev machine via SCP/SSH
  - deploy-phase1.sh through deploy-phase6.sh: per-phase config deployment on IPFire
  - REPO-02: rebuild script that restores fresh IPFire install from git repo
  - REPO-03: Pakfire manifest verification during rebuild

affects:
  - scripts/: 7 new scripts added (rebuild.sh + 6 deploy-phase scripts)
  - manifests/file-manifest.sha256: pulled back to repo after rebuild run

# Tech stack
tech_stack:
  added: []
  patterns:
    - backup_and_copy function: backup-before-overwrite pattern in all deploy scripts
    - grep-before-append: idempotent sysctl hardening in deploy-phase6.sh
    - CRLF fix via sed: applied after SCP from Windows dev machine to IPFire
    - conditional service restart: check service exists before restarting (Suricata, sysklogd)
    - WUI-only documentation: deploy-phase3.sh documents non-automatable SSH steps

# Key files
key_files:
  created:
    - scripts/rebuild.sh
    - scripts/deploy-phase1.sh
    - scripts/deploy-phase2.sh
    - scripts/deploy-phase3.sh
    - scripts/deploy-phase4.sh
    - scripts/deploy-phase5.sh
    - scripts/deploy-phase6.sh
  modified: []

# Decisions
decisions:
  - deploy-phase3.sh is documentation-only: sshd_config.hardened is reference, not deployed — sshctrl binary owns sshd_config and WUI saves would overwrite direct edits
  - deploy-phase5.sh checks multiple syslog.conf locations: configs/syslog.conf, configs/logging/syslog.conf, configs/telemetry/syslog.conf — gracefully skips if none found
  - deploy-phase6.sh uses check-integrity.sh exit 0 or non-zero: non-zero (partial baseline) is acceptable and noted, not failed — some files may not be present on a fresh deploy
  - rebuild.sh uses set -euo pipefail in sections but phases continue on individual fail: FAIL_TOTAL tracked, non-zero exits at end
  - Pakfire manifest verification (Section 9) is informational: packages cannot be auto-installed reliably; WUI step documented

# Metrics
metrics:
  duration: "4 minutes"
  completed_date: "2026-03-26"
  tasks_completed: 2
  files_created: 7
  files_modified: 0
---

# Phase 07 Plan 04: Rebuild Scripts Summary

Master rebuild orchestrator and 6 per-phase deploy scripts that restore a full IPFire configuration from the git repo via SCP/SSH from the dev machine.

## What Was Built

**rebuild.sh** — Master orchestrator that runs from the dev machine. Validates SSH prerequisites, deploys the entire repo to IPFire via SCP, calls each deploy-phase script in order via SSH, verifies the Pakfire manifest, generates the drift manifest, runs validate-all.sh as the final acceptance gate, and prints WUI manual steps.

**6 deploy-phase scripts** — Each runs on IPFire (called via SSH). Each creates `/root/rollback/{category}-{timestamp}.bak` before overwriting any config file, then deploys the relevant configs and reloads services.

| Script | Phase | Key Config | Service Reload |
|--------|-------|------------|----------------|
| deploy-phase1.sh | Platform Foundation | udev rules, firewall.local, backup-include.user | /etc/init.d/firewall restart |
| deploy-phase2.sh | Core Network Services | DNS forward.conf (+ DHCP if present) | /etc/init.d/unbound restart |
| deploy-phase3.sh | SSH Hardening | WUI-only (no file deployment) | none |
| deploy-phase4.sh | Suricata IDS/IPS | suricata.yaml | /etc/init.d/suricata restart (conditional) |
| deploy-phase5.sh | Telemetry Syslog | syslog.conf (multi-path search) | /etc/init.d/sysklogd restart |
| deploy-phase6.sh | System Hardening | sysctl append (idempotent) | sysctl -p + integrity baseline |

## Key Design Patterns

**Rollback backups before every overwrite:** The `backup_and_copy()` function in each script copies the existing destination file to `/root/rollback/{category}-{timestamp}.bak` before deploying the new version. Rollback is manual (use scripts in `rollback/`).

**Idempotent sysctl append (deploy-phase6.sh):** Uses `grep -q "net.ipv4.conf.all.send_redirects" /etc/sysctl.conf` before appending. Safe to re-run — no duplicate params.

**Non-interactive design (D-02):** rebuild.sh uses `BatchMode=yes` in all SSH/SCP calls. No `read`, `select`, or `pause` anywhere. Exit codes indicate success/failure.

**CRLF fix post-SCP:** All `.sh` files get `sed -i "s/\r$//"` applied after SCP from the Windows dev machine to prevent bash parse errors on IPFire.

**WUI-only phase (deploy-phase3.sh):** SSH config is owned by `sshctrl` binary. The script documents the required WUI steps and verifies firewall.local was deployed in Phase 1 — it does NOT copy `sshd_config.hardened` to `/etc/ssh/sshd_config`.

**ip_forward safety check:** deploy-phase6.sh verifies `net.ipv4.ip_forward=1` after `sysctl -p`. If it's 0, WAN routing is broken and the script exits with FAIL + recovery instruction.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1: rebuild.sh | f851dea | feat(07-04): create rebuild.sh master rebuild orchestrator |
| Task 2: deploy-phase1-6.sh | 26b161a | feat(07-04): create 6 per-phase deploy scripts for IPFire rebuild |

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — all scripts are complete and executable with no placeholder content.

## Self-Check: PASSED

Files verified:
- FOUND: scripts/rebuild.sh
- FOUND: scripts/deploy-phase1.sh
- FOUND: scripts/deploy-phase2.sh
- FOUND: scripts/deploy-phase3.sh
- FOUND: scripts/deploy-phase4.sh
- FOUND: scripts/deploy-phase5.sh
- FOUND: scripts/deploy-phase6.sh

Commits verified:
- FOUND: f851dea (rebuild.sh)
- FOUND: 26b161a (deploy scripts)
