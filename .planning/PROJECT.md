# Firewall Appliance

## What This Is

A fully configured, hardened, reproducible firewall appliance built on an Intel N100-class 6-NIC mini-PC running IPFire. It serves as the primary network gateway with IDS/IPS, network telemetry, threat-tracing dashboards, and automated rebuild capability. All configs, scripts, and validation artifacts live in a Git repo for reproducibility.

## Core Value

A secure, observable network perimeter that can be rebuilt from scratch in minutes — if the box dies, the repo rebuilds it identically.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Platform verified and documented (OS, NICs, services)
- [ ] All 6 NICs mapped persistently to IPFire zones (RED/GREEN/BLUE/ORANGE + Bridge)
- [ ] Native firewall with default-deny inbound, NAT/masquerade, zone policies
- [ ] Anti-lockout protections for management access during all changes
- [ ] Core services: DHCP server, DNS resolver, NTP
- [ ] SSH hardened + brute-force protection (Guardian)
- [ ] IDS/IPS via Suricata with auto-updating rules
- [ ] Network telemetry pipeline (logs → processing → visualization)
- [ ] Threat-tracing dashboard (end-to-end: source IP → alert → action)
- [ ] Off-box telemetry host (Docker Compose: Grafana + Loki + Alloy + Prometheus)
- [ ] System hardening (unused services disabled, permissions locked, audit logging)
- [ ] Full validation suite (interfaces, routing, NAT, DNS, DHCP, firewall, reboot persistence)
- [ ] Reproducible rebuild from repo (scripts, configs, manifests)
- [ ] Rollback procedures for every change category
- [ ] Decision log tracking all architectural choices

### Out of Scope

- VPN server setup — separate project, not core firewall
- WiFi AP management — handled by dedicated APs, not the firewall box
- Mail server/relay — not a firewall function
- Web hosting — firewall is not a web server
- GUI-based configuration tools beyond IPFire WUI — native tools only

## Context

- **Hardware:** Intel N100-class mini-PC with 6 Intel i225/i226 NICs, ~16GB RAM, NVMe storage
- **OS:** IPFire 2.29 Core Update 200 (March 2, 2026) — Suricata 8.0.3, kernel 6.18.7 LTS
- **Current state:** Fresh or near-fresh install, basic WAN+LAN connectivity working
- **Management access:** Web UI at https://192.168.1.1:444, SSH available
- **Network position:** Between ISP modem/ONT and internal network
- **Upstream connectivity:** ISP-provided WAN IP via DHCP (typical home/small office)
- **IPFire-specific:** Uses Pakfire package manager, zone-based networking (GREEN/RED/BLUE/ORANGE), built-in WUI for management

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
| IPFire as base OS | Already installed, purpose-built firewall distro with Pakfire, zones, WUI | — Pending |
| Native firewall over Docker | Core network functions must not depend on container runtime | — Pending |
| Suricata for IDS/IPS | Industry standard, IPFire-native support, active community | — Pending |
| Git-based reproducibility | All configs in repo enables rebuild and audit trail | — Pending |
| Phased log ingest | Prevent resource exhaustion on N100; start with firewall logs, add sources incrementally | — Pending |
| Off-box telemetry | Docker rejected by IPFire devs; telemetry stack on separate host in GREEN zone | — Pending |
| Grafana+Loki over OpenSearch | OpenSearch too heavy for N100; Loki+Alloy is lightweight and purpose-built | — Pending |
| Guardian over fail2ban | fail2ban not in Pakfire; Guardian is IPFire-native with WUI integration | — Pending |

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
*Last updated: 2026-03-21 after research (Docker off-box, zone limits, Guardian, Alloy stack)*
