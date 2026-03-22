---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: unknown
stopped_at: Completed 04-01-PLAN.md — validate-phase4.sh, check-suricata-integrity.sh, suricata-ids-runbook.md, suricata config references
last_updated: "2026-03-22T19:15:53.319Z"
progress:
  total_phases: 7
  completed_phases: 0
  total_plans: 11
  completed_plans: 7
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-21)

**Core value:** A secure, observable network perimeter that can be rebuilt from scratch in minutes
**Current focus:** Phase 04 — suricata-ids-ips

## Current Position

Phase: 04 (suricata-ids-ips) — EXECUTING
Plan: 2 of 2

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

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 4 (IDS/IPS): Suricata memcap values for N100 16GB single-channel DDR5 are not documented — require empirical determination during Phase 4
- Phase 5 (Telemetry): EVE JSON file-read path from off-box host (NFS vs rsync vs SSH tunnel) has unresolved security tradeoffs — research-phase recommended before Phase 5 planning
- Phase 5 (Telemetry): collectd metrics to Prometheus bridge via collectd_exporter is non-trivial and unvalidated for CU200 — resolve during Phase 5 planning
- Platform: IPFire DBL is beta in CU200 — monitor for stable promotion before activating in Phase 4

## Session Continuity

Last session: 2026-03-22T19:15:53.314Z
Stopped at: Completed 04-01-PLAN.md — validate-phase4.sh, check-suricata-integrity.sh, suricata-ids-runbook.md, suricata config references
Resume file: None
