# Firewall Appliance

## What This Is

A fully configured, hardened, reproducible firewall appliance built on an Intel N100-class 6-NIC mini-PC running IPFire 2.29 (CU200). It serves as the primary network gateway with IDS/IPS (Suricata), network telemetry (Alloy+Loki+Grafana), threat-tracing dashboards, and automated rebuild capability. All configs, scripts, and validation artifacts live in a Git repo — rebuild from scratch in under 15 minutes.

## Core Value

A secure, observable network perimeter that can be rebuilt from scratch in minutes — if the box dies, the repo rebuilds it identically.

## Requirements

### Validated

- ✓ All 6 NICs mapped persistently to IPFire zones via MAC-based udev rules — v1.0
- ✓ Anti-lockout protections (firewall.local CUSTOMINPUT rules) — v1.0
- ✓ Git repository with full directory structure and backup include list — v1.0
- ✓ Stateful firewall with default-deny, NAT/masquerade, zone segmentation, drop logging — v1.0
- ✓ DHCP server on GREEN with gateway/DNS/NTP options — v1.0
- ✓ DNS resolver with DNSSEC validation and DNS-over-TLS enforcement — v1.0
- ✓ NTP synchronized and serving clients — v1.0
- ✓ SSH key-only auth with IP allowlisting — v1.0
- ✓ Guardian brute-force protection with management host whitelist — v1.0
- ✓ Suricata IDS/IPS with ET Community rules, EVE JSON, N100-tuned memcap — v1.0
- ✓ Off-box telemetry pipeline: rsyslog→Alloy→Loki for syslog, SCP→Alloy→Loki for EVE JSON — v1.0
- ✓ Grafana dashboards with threat-tracing (source IP → IDS alert → firewall action) — v1.0
- ✓ System hardening (sysctl, permissions, service audit, integrity baseline) — v1.0
- ✓ Full validation suite (validate-all.sh covering 6 phases) — v1.0
- ✓ Rebuild script (rebuild.sh) restoring fresh IPFire from repo — v1.0
- ✓ Rollback procedures for 7 change categories — v1.0
- ✓ Decision log (12 ADRs) tracking all architectural choices — v1.0

### Active

(None — next milestone requirements defined via `/gsd:new-milestone`)

### Out of Scope

- VPN server setup — separate project, not core firewall
- WiFi AP management — handled by dedicated APs
- Mail server/relay — not a firewall function
- Web hosting — firewall is not a web server
- GUI tools beyond IPFire WUI — native tools only
- Docker on IPFire host — officially rejected by IPFire developers
- High-availability clustering — git-based rebuild is the HA strategy (15 min RTO)
- AI/ML threat detection — N100 not dimensioned for real-time ML inference

## Context

- **Hardware:** Intel N100 mini-PC, 6x Intel i226-V NICs (a8:b8:e0:09:83:39-3e), 16GB DDR5, NVMe
- **OS:** IPFire 2.29 Core Update 200, kernel 6.18.7 LTS, Suricata 8.0.3
- **Shipped:** v1.0 on 2026-03-26 (6-day build, 124 commits, 192 files, ~31K lines)
- **Codebase:** ~3,045 LOC shell scripts, ~2,357 LOC config/yaml, ~3,515 LOC markdown docs
- **Architecture:** IPFire on-box (firewall, routing, IDS) + Docker Compose off-box on supportTAK-server (Grafana, Loki, Alloy, Prometheus)
- **Management:** SSH key-only (ed25519) on port 22 from 192.168.1.100, WUI at :444
- **Telemetry:** 112,769+ syslog entries in Loki, EVE JSON pulling every 60s via SCP cron
- **Known tech debt:** Suricata dashboard 22247 is placeholder (manual import needed), collectd→Prometheus bridge not wired

## Constraints

- **Platform:** IPFire-native tools and architecture only — no mixing distro paradigms
- **Architecture:** Core firewall/routing/NAT MUST be native; Docker rejected by IPFire — telemetry runs off-box
- **Hardware:** N100 is low-power — telemetry stack must be lightweight or off-boxable
- **Access:** Must preserve management access (anti-lockout) during all network changes
- **Repos:** Only vetted, actively maintained upstream repos (Suricata, Grafana, Loki, Alloy, Prometheus)
- **Zones:** IPFire hard limit of 4 named zones (RED/GREEN/BLUE/ORANGE); extra NICs use Bridge mode
- **Updates:** Core Updates overwrite custom configs — must use backup includes + post-update validation
- **No placeholders:** All configs must be complete and executable, no pseudocode

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| IPFire as base OS | Already installed, purpose-built firewall distro with Pakfire, zones, WUI | ✓ Good |
| Native firewall over Docker | Core network functions must not depend on container runtime | ✓ Good |
| Suricata for IDS/IPS | Industry standard, IPFire-native support, active community | ✓ Good |
| Git-based reproducibility | All configs in repo enables rebuild and audit trail | ✓ Good — 15 min RTO achieved |
| Phased log ingest | Prevent resource exhaustion on N100; start with firewall logs, add sources incrementally | ✓ Good — syslog first, then EVE |
| Off-box telemetry | Docker rejected by IPFire devs; telemetry stack on separate host in GREEN zone | ✓ Good — supportTAK-server running full stack |
| Grafana+Loki over OpenSearch | OpenSearch too heavy for N100; Loki+Alloy is lightweight and purpose-built | ✓ Good — Loki runs at ~250MB RAM |
| Guardian over fail2ban | fail2ban not in Pakfire; Guardian is IPFire-native with WUI integration | ✓ Good |
| rsyslog→file→Alloy (not direct UDP) | rsyslog must relay; Alloy tails the file rsyslog writes | ✓ Good — discovered during Phase 5 deployment |
| SCP pull for EVE JSON (not rsync) | IPFire lacks rsync binary; scp works with existing SSH key | ✓ Good — 60s cron with --checksum |
| checksum-validation: no in Suricata | Intel i226-V hardware checksum offload causes false positive ICMP alerts | ✓ Good |
| Sysctl hardening preserves ip_forward | ip_forward=1 is required for routing; grep-before-append for idempotent deploys | ✓ Good |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-03-26 after v1.0 milestone*
