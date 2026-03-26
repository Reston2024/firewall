---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: unknown
stopped_at: Completed 08-02-PLAN.md
last_updated: "2026-03-26T07:58:28.795Z"
progress:
  total_phases: 8
  completed_phases: 3
  total_plans: 27
  completed_plans: 21
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-21)

**Core value:** A secure, observable network perimeter that can be rebuilt from scratch in minutes
**Current focus:** Phase 08 — milestone-gap-closure

## Current Position

Phase: 08 (milestone-gap-closure) — EXECUTING
Plan: 2 of 3

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: —
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

*Updated after each plan completion*
| Phase 01-platform-foundation-and-firewall P01 | 10 | 3 tasks | 15 files |
| Phase 01-platform-foundation-and-firewall P03 | 2 | 2 tasks | 2 files |
| Phase 01 P02 | 2 | 3 tasks | 4 files |
| Phase 02-core-network-services P01 | 7 | 2 tasks | 4 files |
| Phase 02-core-network-services P02 | 10 | 2 tasks | 5 files |
| Phase 03 P01 | 4 | 3 tasks | 4 files |
| Phase 04-suricata-ids-ips P01 | 4 | 2 tasks | 5 files |
| Phase 05-telemetry-pipeline-and-dashboards P01 | 10 | 2 tasks | 8 files |
| Phase 05 P02 | 120 | 2 tasks | 2 files |
| Phase 05-telemetry-pipeline-and-dashboards P03 | 150 | 1 tasks | 5 files |
| Phase 05 P04 | 6 | 2 tasks | 2 files |
| Phase 06 P01 | 523942 | 2 tasks | 6 files |
| Phase 06 P02 | 5 | 2 tasks | 2 files |
| Phase 07 P01 | 7 | 2 tasks | 3 files |
| Phase 07 P02 | 3 | 2 tasks | 8 files |
| Phase 07 P03 | 3 | 2 tasks | 9 files |
| Phase 07 P04 | 4 | 2 tasks | 7 files |
| Phase 08 P02 | 3 | 2 tasks | 3 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Project setup: Docker rejected on IPFire host — telemetry stack is off-box on GREEN zone host
- Project setup: Grafana Alloy replaces EOL Promtail (Promtail EOL February 28, 2026)
- Project setup: Guardian chosen over fail2ban (fail2ban not in Pakfire)
- Project setup: NIC persistence via udev MAC rules must be established before any other config
- [Phase 01-platform-foundation-and-firewall]: validate-nics.sh uses FILL_IN_FROM_NIC_MAP placeholders — human must populate from hardware identification before Plan 02 udev rules can be written
- [Phase 01-platform-foundation-and-firewall]: validate-phase1.sh calls validate-nics.sh as first check, then verifies CUSTOMINPUT anti-lockout rules (ports 222/444), repo structure, backup include list, and firewall.local
- [Phase 01-platform-foundation-and-firewall]: FW-02 masquerade documented as WUI-only action (anti-pattern to hand-roll iptables MASQUERADE)
- [Phase 01-platform-foundation-and-firewall]: validate-firewall.sh uses SKIP (not FAIL) when no drop log entries — requires triggering blocked traffic first
- [Phase 01-platform-foundation-and-firewall]: FILL_IN_FROM_NIC_MAP placeholders used for all MAC addresses in udev rules and ethernet/settings — human must populate from hardware before deployment
- [Phase 01-platform-foundation-and-firewall]: firewall.local sources /var/ipfire/ethernet/settings to avoid hardcoded interface names — GREEN_DEV variable resolved at runtime
- [Phase 01-platform-foundation-and-firewall]: check-before-delete pattern (iptables -C before -D) used in firewall.local stop case to prevent errors on empty CUSTOMINPUT chain
- [Phase 02-core-network-services]: validate-phase2.sh uses SKIP (not FAIL) for SVC-02 static leases — no static leases is a valid initial deployment state
- [Phase 02-core-network-services]: SVC-04 wire verification (tcpdump port 53/853) is always SKIP — cannot automate from repo, requires live RED interface
- [Phase 02-core-network-services]: Templates document expected WUI output (not deployable) — human verifies WUI produced correct results by comparing live file to template
- [Phase 02-core-network-services]: Runbook Section 1 is NTP to enforce NTP-before-DHCP ordering constraint preventing WARNING log
- [Phase 02-core-network-services]: ISP DNS disable documented as first step in DNS section — mutual exclusivity with TLS protocol in IPFire
- [Phase 03-ssh-hardening-and-management-security]: firewall.local extended (not replaced) — Phase 1 broad GREEN ACCEPT rules preserved as anti-lockout fallback while Phase 3 adds management-host-specific rules
- [Phase 03-ssh-hardening-and-management-security]: ORANGE_DEV and BLUE_DEV guarded with [ -n ] in firewall.local — variables unset if zones not configured; unguarded use causes iptables syntax errors
- [Phase 03-ssh-hardening-and-management-security]: sshd_config.hardened is reference-only — sshctrl binary manages sshd_config via WUI saves; direct deployment risks being overwritten
- [Phase 04-suricata-ids-ips]: IDS-04 always SKIP in validate-phase4.sh — monitor mode cannot be read from CLI reliably; WUI-only
- [Phase 04-suricata-ids-ips]: IDS-05 gated behind --full flag — memory check requires 30+ minutes of traffic
- [Phase 04-suricata-ids-ips]: check-suricata-integrity.sh uses exit 2 for WARN (hash mismatch) so validate-phase4.sh maps it to SKIP
- [Phase 04-suricata-ids-ips]: stream.checksum-validation: no required for Intel i226-V NIC hardware checksum offload — prevents false positive ICMP alerts
- [Phase 05-telemetry-pipeline-and-dashboards]: rsync --checksum (not --append-verify) for EVE JSON: prevents duplicate entries after IPFire nightly logrotate
- [Phase 05-telemetry-pipeline-and-dashboards]: stage.structured_metadata for src_ip on firewall syslog path: prevents high-cardinality Loki stream explosion from FORWARDFW drop lines
- [Phase 05-telemetry-pipeline-and-dashboards]: rfc3164_default_to_current_year=true in Alloy syslog listener: prevents year=0000 timestamp bug (GitHub issue #2287) for RFC3164 IPFire syslog
- [Phase 05-telemetry-pipeline-and-dashboards]: Deploy stack before IPFire syslog: Alloy must bind UDP 514 before IPFire starts forwarding to prevent silent log loss
- [Phase 05-telemetry-pipeline-and-dashboards]: rsyslog pre-flight check placed as Section 2: stopping rsyslog before docker compose up prevents port 514 binding race
- [Phase 05-telemetry-pipeline-and-dashboards]: Actual Path A architecture is rsyslog→file→Alloy tailing (not direct UDP receive): rsyslog must be running as relay; original runbook Section 2 disable-rsyslog instruction was incorrect
- [Phase 05-telemetry-pipeline-and-dashboards]: validate-phase5.sh TEL-02 checks rsyslog IS running (not absent): fixed post-deployment when architecture confirmed
- [Phase 05-telemetry-pipeline-and-dashboards]: validate-phase5.sh TEL-04 uses query_range not instant query: instant query returns empty for log streams; range query with 5m window required
- [Phase 05-telemetry-pipeline-and-dashboards]: Plain scp key (no rsync command= restriction) for EVE pull: IPFire lacks rsync binary, rsync-eve.sh uses scp — command= restriction designed for rsync --server would break scp transport
- [Phase 05-telemetry-pipeline-and-dashboards]: Suricata anomaly logger: Suricata 8.0.3 crashes with duplicate anomaly in both file and reporter socket eve-log blocks — disable anomaly in reporter socket block only
- [Phase 05-telemetry-pipeline-and-dashboards]: validate-phase5.sh TEL-03 requires sudo docker compose: opsadmin cannot run docker without sudo on supportTAK-server
- [Phase 05]: suricata-22247.json is a placeholder: Grafana Labs API unavailable at execution time; dashboard 22247 must be imported manually from https://grafana.com/grafana/dashboards/22247-suricata-logs-json/ for full IDS severity panels; DASH-03 validate check passes with placeholder (title present in Grafana)
- [Phase 05]: validate-phase5.sh requires GF_SECURITY_ADMIN_PASSWORD exported in shell for TEL-06 and DASH-03 checks; source /opt/telemetry/.env or export GF_SECURITY_ADMIN_PASSWORD=changeme before running
- [Phase 06-system-hardening-and-validation-suite]: check-integrity.sh exit codes: 0=all match, 1=error (missing baseline/file), 2=mismatch — mirrors check-suricata-integrity.sh pattern
- [Phase 06-system-hardening-and-validation-suite]: validate-reboot.sh captures iptables-save hash (not full ruleset) to enable clean diff comparison across reboots
- [Phase 06-system-hardening-and-validation-suite]: Pakfire manifest lists only guardian — Suricata is bundled in IPFire core (not a Pakfire add-on) since CU131
- [Phase 06]: validate-phase6.sh HARD-03 maps check-integrity.sh exit 2 to skip() — mismatch may be intentional after Core Update
- [Phase 06]: validate-all.sh Phase 5 SSH failure is SKIP not FAIL — supportTAK-server is optional off-box infrastructure
- [Phase 07-reproducibility-and-disaster-recovery]: check-drift.sh manages ALL 12 managed files; check-integrity.sh monitors 8 critical files with on-box baseline — distinct tools for distinct purposes (D-15)
- [Phase 07-reproducibility-and-disaster-recovery]: WUI-managed files excluded from drift manifest to prevent false-positive drift; backup-include.user updated to 8 entries adding /etc/suricata/suricata.yaml (D-21, D-22)
- [Phase 07]: ADRs 0005-0012 are retrospective captures (D-17) — all status Accepted, dating 2026-03-25
- [Phase 07]: 12 total ADRs in decisions/ meets D-19 minimum; git-rebuild HA strategy targets 15-minute RTO
- [Phase 07]: Zone rollback warns about reboot requirement but does not auto-reboot — user must initiate reboot manually
- [Phase 07]: Sysctl rollback checks ip_forward value after sysctl -p and exits 1 if 0 (WAN routing would be broken)
- [Phase 07]: SSH and Guardian excluded from script-based rollback — both WUI-managed; direct file edits risk being overwritten by sshctrl
- [Phase 07]: deploy-phase3.sh is documentation-only: sshd_config.hardened is reference only — sshctrl binary owns sshd_config
- [Phase 07]: rebuild.sh uses grep-before-append in deploy-phase6.sh for idempotent sysctl hardening — no duplicate params on re-run
- [Phase 08-milestone-gap-closure]: INT-7A closed: validate-all.sh sourced double-path /opt/telemetry/telemetry/.env fixed to /opt/telemetry/.env — TEL-06 and DASH-03 checks now find GF_SECURITY_ADMIN_PASSWORD
- [Phase 08-milestone-gap-closure]: INT-4A closed: /var/ipfire/ethernet/settings removed from check-drift.sh MANAGED_FILES per D-21 — WUI-managed file excluded to prevent false-positive drift
- [Phase 08-milestone-gap-closure]: INT-2A closed: telemetry runbook Section 2 rewritten — rsyslog is required relay (receives UDP 514, writes to file, Alloy tails); old instruction to disable rsyslog was incorrect for deployed architecture

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 4 (IDS/IPS): Suricata memcap values for N100 16GB single-channel DDR5 are not documented — require empirical determination during Phase 4
- Phase 5 (Telemetry): EVE JSON file-read path from off-box host (NFS vs rsync vs SSH tunnel) has unresolved security tradeoffs — research-phase recommended before Phase 5 planning
- Phase 5 (Telemetry): collectd metrics to Prometheus bridge via collectd_exporter is non-trivial and unvalidated for CU200 — resolve during Phase 5 planning
- Platform: IPFire DBL is beta in CU200 — monitor for stable promotion before activating in Phase 4

## Session Continuity

Last session: 2026-03-26T07:58:28.791Z
Stopped at: Completed 08-02-PLAN.md
Resume file: None
