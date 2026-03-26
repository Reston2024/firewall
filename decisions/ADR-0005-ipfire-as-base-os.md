# ADR-0005: IPFire as Base OS

- **Date:** 2026-03-25
- **Status:** Accepted

## Context

Needed a firewall OS for an Intel N100 6-NIC mini-PC to serve as a home/SOHO network gateway. Options evaluated were pfSense (FreeBSD-based), OPNsense (pfSense fork), IPFire (purpose-built Linux firewall), or bare Linux with iptables/nftables. The hardware was already delivered with IPFire 2.29 Core Update 200 installed.

## Decision

Use IPFire 2.29 (Core Update 200) as the base operating system.

## Rationale

- Purpose-built firewall distribution with zone-based architecture (GREEN/RED/BLUE/ORANGE) matching the 6-NIC hardware layout
- Built-in WUI management interface at port 444 — no separate management plane needed
- Pakfire package manager provides add-ons (Guardian, Lynis) in a controlled, tested ecosystem
- Native Suricata IDS/IPS bundled since Core Update 131 (version 8.0.3 in CU200) — no manual installation or maintenance
- Unbound DNS resolver with DNSSEC support built in since CU200 (version 1.24.2)
- Designed for appliance use cases — SysVinit-based, minimal footprint, no unnecessary services
- CU200 ships kernel 6.18.7 LTS with full Intel i225/i226 NIC driver support for the N100 hardware
- Already installed on hardware — switching to another OS would require reinstall and lose the validated baseline

## Consequences

- Limited to 4 named zones (RED/GREEN/BLUE/ORANGE) — additional NICs must use bridge mode
- No Docker support — IPFire developers have explicitly rejected Docker in Pakfire; telemetry stack must run off-box on a GREEN zone host
- Telemetry stack (Grafana, Loki, Alloy, Prometheus) runs on a separate machine, not on the firewall appliance itself
- All customization must work within IPFire's SysVinit and custom buildroot environment — no systemd units, no standard package managers
- Core Updates may overwrite custom configs — all customizations must use backup includes and post-update validation
