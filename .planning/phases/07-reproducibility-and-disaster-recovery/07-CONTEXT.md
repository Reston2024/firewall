# Phase 7: Reproducibility and Disaster Recovery - Context

**Gathered:** 2026-03-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Every configuration artifact lives in the git repo. A rebuild script applies the full configuration idempotently to a fresh IPFire install. Rollback procedures exist for every change category. A decision log captures all architectural choices in ADR format.

</domain>

<decisions>
## Implementation Decisions

### Rebuild script design (REPO-02)
- **D-01:** Modular architecture — one master `rebuild.sh` orchestrator that calls per-phase deploy scripts in order (phase 1 → 6), not one monolithic script
- **D-02:** Fully automated, non-interactive — no prompts, no pauses. Designed to run unattended after a fresh IPFire install. Exit codes indicate success/failure per phase.
- **D-03:** Deployment method: SCP from dev machine to IPFire (same pattern as existing deployment runbooks), not git clone on IPFire. IPFire doesn't have git installed and shouldn't.
- **D-04:** Secrets handling: SSH keys and certificates are NOT stored in the repo. Rebuild script has a prerequisite step that documents what must be manually provisioned before running (SSH key pair, WUI cert). Script validates prerequisites exist before proceeding.
- **D-05:** Idempotency: every operation must be safe to re-run. Use `cp` with overwrite, `sysctl -p` (already idempotent), `chmod` (already idempotent). No append operations without dedup checks (the sysctl append from Phase 6 must be handled — check if params already exist before appending).
- **D-06:** Final step: run `validate-all.sh` to confirm the rebuilt system passes all checks. Rebuild is not "done" until validation passes.

### Rollback strategy (REPO-05)
- **D-07:** Config-file rollback, not snapshot-based — IPFire doesn't have LVM/ZFS snapshots. Rollback means restoring the previous config file and reloading the service.
- **D-08:** One rollback script per change category: firewall rules, IDS/Suricata config, DNS config, DHCP config, zone/NIC config. Each script restores from a timestamped backup in `/root/rollback/`.
- **D-09:** Rollback procedure: before any change, the deploy script copies current config to `/root/rollback/{category}-{timestamp}.bak`, then applies the new config. Rollback = copy .bak back and reload service.
- **D-10:** Rollback granularity: full category (e.g., all firewall rules), not individual rules. Individual rule rollback is too fragile for IPFire's iptables-based system.
- **D-11:** Each rollback procedure documented in `rollback/README.md` with step-by-step instructions. Scripts are optional automation — the README must be sufficient for manual recovery.

### Drift detection (REPO-04)
- **D-12:** Full file manifest format: `sha256sum` checksums for all managed config files, stored as `manifests/file-manifest.sha256` in the repo.
- **D-13:** Drift detection script: `scripts/check-drift.sh` compares live system files against the manifest. Reports: files changed, files missing, unexpected files.
- **D-14:** Manual execution only — no scheduled cron jobs on IPFire. Run after Core Updates or when investigating issues. IPFire's minimal environment shouldn't have unnecessary daemons.
- **D-15:** The existing `check-integrity.sh` monitors 8 critical files. `check-drift.sh` is broader — it covers ALL managed files (configs, scripts, manifests, docs deployed to IPFire). The two scripts complement each other: integrity = critical subset with baseline, drift = full manifest comparison.

### Decision log / ADRs (REPO-06)
- **D-16:** Lightweight Markdown ADRs in `docs/decisions/` using the standard ADR format: Title, Status, Context, Decision, Consequences.
- **D-17:** Retrospective capture: extract all architectural decisions from PROJECT.md Key Decisions, STATE.md, and deployment runbooks. These are decisions already made — document them as ADRs with status "Accepted".
- **D-18:** ADR numbering: `ADR-001-short-name.md` format. Sequential, never renumbered.
- **D-19:** Minimum ADRs to create: one per major architectural choice — off-box telemetry, ECDSA-only cert, Guardian over fail2ban, Suricata monitor mode, sysctl hardening approach, modular validation scripts, DNS-over-TLS. Approximately 8-12 ADRs.

### Config completeness audit (REPO-01)
- **D-20:** Audit all IPFire config files that the repo should track. Compare what's deployed on IPFire vs what's in `configs/`. Any managed file not in the repo gets added.
- **D-21:** Config files that IPFire auto-generates and manages via WUI (e.g., `/var/ipfire/firewall/config`) are documented but NOT version-controlled — they change via WUI and would cause constant drift. Instead, document the WUI settings needed to recreate them.
- **D-22:** The `configs/firewall/backup-include.user` file is the canonical list of what IPFire's backup system preserves. This must be kept in sync with the file manifest.

### Claude's Discretion
- Exact ADR content and wording
- check-drift.sh implementation details (output format, exit codes)
- Rebuild script internal structure and error handling
- Which specific config files to add during the completeness audit
- Rollback script implementation details

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing deployment patterns
- `docs/hardening-deployment-runbook.md` — SCP-based deployment pattern, CRLF fix, chmod workflow
- `docs/telemetry-deployment-runbook.md` — Off-box deployment pattern
- `docs/ssh-management-runbook.md` — SSH key management, access patterns
- `docs/services-runbook.md` — Core service deployment (DHCP, DNS, NTP)

### Existing validation/integrity scripts
- `scripts/validate-all.sh` — Unified validation orchestrator (rebuild must end with this)
- `scripts/check-integrity.sh` — SHA256 baseline monitoring (8 critical files)
- `scripts/validate-reboot.sh` — Reboot persistence verification pattern

### Config structure
- `configs/` — All 9 config subdirectories (dhcp, dns, ethernet, firewall, hardening, ntp, ssh, suricata, udev)
- `configs/firewall/backup-include.user` — IPFire backup include list
- `manifests/pakfire-manifest.txt` — Live Pakfire package list
- `manifests/pakfire-manifest-expected.txt` — Expected Pakfire packages

### Project context
- `docs/wui-certificate.md` — WUI cert documentation (ECDSA-only finding)
- `docs/zone-policy-runbook.md` — Zone architecture and NIC mapping

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `check-integrity.sh` — SHA256 baseline pattern reusable for full manifest
- `validate-all.sh` — Orchestrator pattern reusable for rebuild script structure
- `hardening-deployment-runbook.md` — SCP + CRLF fix + chmod pattern is the standard deploy workflow
- `backup-include.user` — Canonical list of files IPFire backs up

### Established Patterns
- All scripts use `pass()/fail()/skip()` functions with exit code 0/1
- SSH access: `ssh -i ~/.ssh/ipfire_ed25519 root@192.168.1.1`
- Files deploy to `/root/firewall-repo/` on IPFire
- Windows → IPFire requires CRLF fix: `sed -i 's/\r$//' *.sh`
- Scripts are bash, not sh — IPFire has bash

### Integration Points
- Rebuild script calls existing per-phase deployment patterns
- check-drift.sh extends check-integrity.sh's hash comparison approach
- Rollback scripts must know service reload commands (e.g., `sysctl -p`, `/etc/init.d/apache restart`)
- ADRs reference existing runbooks and PROJECT.md decisions

</code_context>

<specifics>
## Specific Ideas

- Rebuild script should follow the same SCP-based deployment model used in all prior phases
- ADRs should capture the "why" behind decisions already documented in PROJECT.md and deployment runbooks
- Drift detection complements (not replaces) the existing integrity baseline system

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 07-reproducibility-and-disaster-recovery*
*Context gathered: 2026-03-25*
