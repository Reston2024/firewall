# Phase 6: System Hardening and Validation Suite - Context

**Gathered:** 2026-03-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Harden the IPFire appliance by disabling unnecessary services, applying kernel hardening parameters, establishing file integrity monitoring, and documenting the WUI certificate. Then create a comprehensive validation suite that tests every capability from Phases 1-5, including reboot persistence verification. The validation suite runs on IPFire and produces a unified pass/fail report.

</domain>

<decisions>
## Implementation Decisions

### Service Audit (HARD-01)
- **D-01:** Conservative audit approach: document all services, disable only clearly unnecessary ones (avahi, cups, etc. if present). Leave WUI services (httpd ports 81/444/1013), Guardian, NTP, DHCP, unbound, sshd, Suricata running.
- **D-02:** Port 81 (HTTP redirect to HTTPS WUI) stays enabled — standard IPFire behavior, disabling may break WUI bookmarks.
- **D-03:** Create a Pakfire manifest listing all expected installed packages. Flag unexpected installs. This feeds into Phase 7 reproducibility (REPO-03).
- **D-04:** Currently listening on IPFire (known good baseline): unbound:53, sshd:22, httpd:81/444/1013. Anything else is a finding.

### Hardening Baseline (HARD-02, HARD-04)
- **D-05:** CIS-inspired for IPFire: apply CIS Linux benchmark principles where applicable, skip controls that conflict with IPFire's architecture (SysVinit, custom buildroot). Document all deviations with rationale.
- **D-06:** Kernel hardening via sysctl.conf: fix send_redirects=0 (currently 1) and any other missing CIS kernel params. Persist in /etc/sysctl.conf or drop-in file. Verify on reboot (VAL-08).
- **D-07:** Current kernel state (already hardened): accept_source_route=0, accept_redirects=0, rp_filter=1. Only send_redirects=1 needs fixing.

### Audit Logging (HARD-03)
- **D-08:** File integrity monitoring approach: SHA256 hash key config files (firewall.local, syslog.conf, suricata.yaml, sshd_config, ethernet/settings, udev rules, backup include list). Store baseline hashes. Compare on demand to detect unauthorized changes.
- **D-09:** No auditd (likely not in Pakfire). No syscall-level auditing — too heavy for SOHO firewall. File hash comparison is sufficient.

### WUI Certificate (HARD-05)
- **D-10:** Document the self-signed HTTPS certificate on port 444. Verify it exists and has reasonable validity. Add certificate fingerprint to the repo for reference.

### Validation Suite Architecture (VAL-01 through VAL-11)
- **D-11:** Orchestrator pattern: a new validate-all.sh on IPFire calls each existing per-phase script (validate-phase1.sh through validate-phase5.sh) in order, collects results, produces unified pass/fail report.
- **D-12:** validate-all.sh runs on IPFire. For Phase 5 telemetry checks, it SSHes to supportTAK-server (192.168.1.101) to run validate-phase5.sh remotely.
- **D-13:** Per-phase scripts already exist for Phases 1-5. Phase 6 creates validate-phase6.sh (hardening checks) and validate-all.sh (orchestrator).
- **D-14:** No JSON output — console pass/fail is sufficient for v1. Structured output is v2.

### Reboot Verification (VAL-08, VAL-09)
- **D-15:** Snapshot-and-compare approach: script captures pre-reboot state, user reboots manually, script runs again post-reboot and compares.
- **D-16:** Pre-reboot snapshot includes: running services (ss -tlnp output), config file SHA256 hashes, full iptables ruleset dump, sysctl hardened kernel parameter values.
- **D-17:** Manual reboot only — no automated reboot trigger. Script captures pre-state, prints instructions to reboot, user runs comparison mode after reboot.

### Claude's Discretion
- Exact CIS controls to apply (choose appropriate subset for IPFire)
- File integrity hash storage format and location
- validate-all.sh output formatting (colors, sections, summary table)
- Which config files to include in integrity baseline (beyond the obvious ones)
- How to handle validate-phase5.sh SSH key from IPFire to supportTAK-server (key already deployed)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing validation scripts (reuse patterns)
- `scripts/validate-phase1.sh` — NIC mapping, CUSTOMINPUT rules, repo structure, firewall.local
- `scripts/validate-phase2.sh` — DHCP options, DNSSEC, DoT, NTP sync, boot symlinks
- `scripts/validate-phase3.sh` — SSH key-only, Guardian, CUSTOMINPUT DROP rules, management runbook
- `scripts/validate-phase4.sh` — Suricata process, rules, EVE JSON, integrity check
- `scripts/validate-phase5.sh` — Docker containers, Loki, Grafana, syslog path, EVE path
- `scripts/check-suricata-integrity.sh` — SHA256 baseline for suricata.yaml (pattern for file integrity monitoring)

### Firewall config
- `configs/firewall/firewall.local` — CUSTOMINPUT rules structure, source /var/ipfire/ethernet/settings pattern
- `configs/firewall/backup-include.user` — Backup include list (must be extended for hardening configs)

### Prior phase summaries (what was deployed)
- `.planning/phases/05-telemetry-pipeline-and-dashboards/05-02-SUMMARY.md` — Stack deployment details, rsyslog architecture
- `.planning/phases/05-telemetry-pipeline-and-dashboards/05-03-SUMMARY.md` — EVE JSON pipeline, SSH key setup

### Deployment runbooks (operational context)
- `docs/telemetry-deployment-runbook.md` — Telemetry stack deployment procedure
- `docs/suricata-ids-runbook.md` — IDS deployment procedure
- `docs/ssh-management-runbook.md` — SSH management and 15-min expiry

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `check-suricata-integrity.sh`: SHA256 baseline pattern — reuse for file integrity monitoring (HARD-03)
- Per-phase validate scripts: pass/fail/skip pattern with colored output — reuse in validate-phase6.sh and validate-all.sh
- `/var/ipfire/ethernet/settings` sourcing pattern: used in firewall.local for dynamic interface names

### Established Patterns
- All validate scripts use: `pass()`, `fail()`, `skip()` functions with counters
- Scripts print section headers with `[REQ-ID]` prefix
- Exit code 0 = all pass, 1 = any fail
- SKIP is used for manual-only checks (WUI, live traffic, external tests)
- validate-phase5.sh requires `GF_SECURITY_ADMIN_PASSWORD` env var for Grafana API checks
- validate-phase5.sh requires `sudo` for docker compose on supportTAK-server

### Integration Points
- validate-all.sh must SSH to supportTAK-server for Phase 5 checks: `ssh opsadmin@192.168.1.101`
- IPFire SSH key for supportTAK-server access: `/root/.ssh/` or needs to be deployed
- validate-phase5.sh needs env var passed via SSH: `ssh ... "export GF_SECURITY_ADMIN_PASSWORD=changeme && sudo -E bash ..."`

</code_context>

<specifics>
## Specific Ideas

- Follow CIS Linux Level 1 benchmark principles adapted for IPFire's non-standard environment (SysVinit, custom buildroot, no systemd)
- File integrity monitoring should hash the same files that backup-include.user covers — alignment between "what we back up" and "what we monitor for changes"
- The Pakfire manifest created here (HARD-01/D-03) directly feeds REPO-03 in Phase 7
- Reboot snapshot should be storable (write to file) so it can be compared days later, not just immediately after reboot

</specifics>

<deferred>
## Deferred Ideas

- Full auditd syscall-level auditing — too heavy for SOHO, revisit if compliance requirements change
- JSON/HTML structured validation output — v2 enhancement
- Automated reboot testing — risk of reboot loops, manual is safer for v1
- Scheduled integrity checks (cron) — consider for Phase 7 or v2

</deferred>

---

*Phase: 06-system-hardening-and-validation-suite*
*Context gathered: 2026-03-25*
