# Project Research Summary

**Project:** IPFire Firewall Appliance — N100 6-NIC Mini-PC
**Domain:** Hardened firewall appliance with IDS/IPS, zone segmentation, and telemetry pipeline
**Researched:** 2026-03-21
**Confidence:** HIGH

## Executive Summary

This project builds a production-grade firewall appliance on IPFire 2.29 (Core Update 200) running on Intel N100 hardware with 6x i226-V NICs. IPFire is a purpose-built firewall distribution with native zone-based segmentation (GREEN/RED/BLUE/ORANGE), Suricata 8.0.3 IDS/IPS, Unbound DNS resolver with DNSSEC, and a WUI-managed configuration model. The recommended approach treats IPFire as a sealed appliance: all core packet processing runs natively on-box, and non-core services (telemetry, dashboards) run on a separate host in the GREEN zone. The project's primary differentiator over stock IPFire is git-based reproducibility — every configuration lives in a repo and a rebuild script can restore a dead appliance from scratch in minutes.

The architecture has one non-obvious constraint that shapes everything: Docker is explicitly rejected by the IPFire development team on security grounds. This means the Grafana/Loki/Alloy/Prometheus telemetry stack must run off-box on a separate machine, not on the IPFire appliance itself. The log pipeline uses Grafana Alloy (not the EOL Promtail) as a UDP syslog receiver for iptables logs, combined with direct file-read of Suricata's EVE JSON for full alert fidelity — EVE data never appears in syslog on IPFire. The off-box stack runs in Docker Compose on a dedicated monitoring host and communicates with IPFire over the GREEN zone.

The key risks are: (1) NIC interface ordering silently breaking after kernel/Core Updates, exposing the wrong zone to the internet; (2) management lockout from firewall rule changes with no automatic rollback; (3) Suricata RAM/CPU saturation from enabling too many rule categories on the N100's single-channel memory architecture; and (4) Docker iptables rules bypassing IPFire's zone policies if Docker were ever co-located on the firewall host. All four risks are preventable by design if addressed in the correct phase order.

---

## Key Findings

### Recommended Stack

IPFire 2.29 (Core Update 200, shipped March 2, 2026) is the correct base platform. CU200 ships Suricata 8.0.3, a multi-threaded Unbound 1.24.2, and the new IPFire DBL (domain blocklist, beta) that integrates with both the Suricata engine and the URL filter. The kernel is 6.18.7 LTS with full i226-V NIC driver support via the `igc` driver.

The off-box telemetry stack uses current stable releases verified in March 2026: Grafana 12.4.1, Loki 3.6.x, Grafana Alloy 1.14.1, and Prometheus 3.10.0. Promtail is EOL as of February 28, 2026 — Alloy is the mandatory replacement. Elasticsearch/Kibana and OpenSearch are explicitly ruled out: 4-8x higher RAM requirements make them impractical on SOHO hardware.

**Core technologies:**
- **IPFire 2.29 CU200**: Base OS, firewall, NAT, DNS, DHCP, IPS — purpose-built appliance OS with zone model baked in
- **Suricata 8.0.3** (native, Pakfire): Inline IDS/IPS via nfqueue — deploy in monitor mode first, tune to active IPS after baselining
- **Unbound 1.24.2** (native): Recursive DNS with mandatory DNSSEC validation — configure DNS-over-TLS upstream before production
- **Guardian** (Pakfire): SSH and WUI brute-force protection — IPFire's native fail2ban equivalent (fail2ban is not in Pakfire)
- **Grafana Alloy 1.14.1** (off-box): Log collection agent — replaces EOL Promtail; receives UDP syslog on port 514 from IPFire
- **Grafana Loki 3.6.x** (off-box): Label-indexed log storage — 5-10x lighter than ELK stack; ~250 MB RAM at SOHO scale
- **Grafana 12.4.1** (off-box): Dashboards and alerting — pre-built Suricata EVE dashboard ID 22247 available
- **Prometheus 3.10.0** (off-box): Metrics storage — scrapes IPFire collectd metrics via a collectd_exporter bridge

**IPS ruleset recommendation:** Emerging Threats Community + IPFire DBL as baseline. Add ThreatFox (abuse.ch) after initial tuning. Avoid OISF Traffic ID (unmaintained since 2018). Do not enable ET Pro ($600/yr) for SOHO deployment.

### Expected Features

**Must have (table stakes) — production-readiness blockers:**
- Stateful firewall, default-deny inbound, NAT/masquerade — base security posture
- All 6 NICs persistently mapped via udev rules — foundation for everything else
- Zone segmentation: GREEN/RED/ORANGE/BLUE — inter-zone policies enforced by default-deny
- DHCP server on GREEN (and optionally BLUE) — static leases committed to repo
- Unbound DNS + DNSSEC + DNS-over-TLS — mandatory DNSSEC, DoT upstream configured
- NTP service — accurate log timestamps required for alert correlation
- SSH hardened + Guardian brute-force protection — key-only auth, IP allowlist
- Suricata IDS/IPS with auto-updating rulesets — zone-selected, monitor-only tuning phase first
- Remote syslog forwarding (UDP 514) to telemetry collector
- Telemetry pipeline: Loki + Grafana on off-box Docker host
- Threat-tracing dashboard — source IP to IPS alert to action in one view
- Full validation suite — scripted pass/fail tests for every capability
- Git repo with rebuild scripts and rollback procedures — the primary project deliverable

**Should have (differentiators over stock IPFire):**
- IPS alert email + PDF reports (CU200 native, requires SMTP configuration)
- IPFire DBL domain blocklist activation (currently beta in CU200)
- Additional OPT zone policies for DMZ pinholes when services are deployed
- GeoIP dashboards — IPS alert heatmaps by country once telemetry pipeline is stable
- Decision log (ADR format) — all architectural choices recorded in repo

**Defer (v2+):**
- VPN server (IPsec/OpenVPN/WireGuard) — separate project, all protocols natively supported by IPFire when needed
- Internal PKI — separate discipline, deferred until mTLS requirements emerge
- SNAT for multi-IP WAN — only relevant when ISP provides multiple IPs

**Anti-features (explicitly not building):**
- Docker on IPFire host — rejected by IPFire developers; telemetry stack is off-box only
- Squid web proxy / TLS inspection — DNS-layer blocking via IPFire DBL covers the use case without MitM complexity
- ELK/OpenSearch on-box — RAM cost disqualifies it; Loki is the correct lightweight alternative
- AI/ML threat detection — N100 is not dimensioned for real-time inference on wire-speed traffic
- High-availability cluster failover — git-based rebuild is the HA strategy; accept ~15 min RTO

### Architecture Approach

The architecture enforces a strict two-layer boundary: the IPFire host is a sealed appliance handling all packet processing, zone enforcement, and core network services natively; a separate telemetry host on the GREEN zone handles all Docker-based observability services. This boundary is non-negotiable based on IPFire developer policy. The log flow uses two patterns in parallel: Suricata EVE JSON read directly from `/var/log/suricata/eve.json` (file-read via the monitoring host, since EVE data never enters IPFire's syslog), and IPFire system/firewall logs forwarded via UDP syslog to Alloy on port 514. Suricata sits before iptables in the packet path (via nfqueue), meaning malicious packets are dropped by Suricata before the firewall engine processes them.

**Major components:**
1. **IPFire host (native)**: Netfilter/iptables zone enforcement, Suricata IPS inline via nfqueue, Unbound DNS, DHCP, NTP, SSH, WUI — all managed via `/var/ipfire/` config files committed to git
2. **udev NIC persistence layer**: `/etc/udev/rules.d/30-persistent-network.rules` anchors each NIC by MAC address to its zone interface name (green0, red0, blue0, orange0) — must be established before any other configuration
3. **Telemetry host (Docker Compose, off-box on GREEN)**: Grafana Alloy (UDP syslog receiver + log pipeline), Loki (log storage), Grafana (dashboards), Prometheus (metrics) — isolated from firewall data plane
4. **Git repo**: Canonical source of truth for all configs, udev rules, validation scripts, rebuild automation, ADRs, and rollback procedures
5. **Validation suite**: Shell scripts that prove every capability (NIC binding, zone routing, NAT, DNS, DHCP, IPS rule load, firewall hit/drop, reboot persistence, lockout resistance) — lives in repo, runs after every rebuild

### Critical Pitfalls

1. **NIC interface ordering breaks after kernel/Core Updates** — On 6-NIC hardware, boot probe order for i226-V NICs can change after a kernel upgrade, silently swapping zone assignments. Mitigation: write udev rules anchoring each NIC to its zone name by MAC address (or PCIe address for stronger guarantees) in Phase 1, before any other configuration. Run a post-update validation script after every Core Update.

2. **Management lockout from firewall rule changes** — IPFire applies rules immediately with no rollback window. Enabling "Outgoing Blocked" or a geoblocking rule without exceptions cuts off WUI and SSH. Mitigation: maintain a hardcoded management allow rule in `firewall.local` (survives WUI changes), always have physical console access before structural rule changes.

3. **Suricata rule overload saturates the N100** — Enabling all Emerging Threats categories consumes 1 GB+ RAM and pegs CPU cores. The N100's single-channel DDR5 memory architecture is a hidden bandwidth bottleneck. Mitigation: enable only policy/malware/exploit categories initially; set `memcap` limits in `suricata.yaml`; deploy in monitor mode before blocking mode; measure CPU/RAM headroom before committing to active IPS.

4. **Docker bypasses IPFire zone firewall rules** — Docker inserts iptables chains that override IPFire's zone policies, potentially exposing container ports to the WAN. Mitigation: do not run Docker on the IPFire host (run it on the off-box telemetry host). If Docker must ever run on-box, set `"iptables": false` in Docker daemon.json.

5. **Core Updates overwrite custom configuration files** — IPFire Core Updates have confirmed history of overwriting `suricata.yaml` and other package-owned files, resetting custom EVE logging configuration. Mitigation: never modify package-owned files directly; use drop-in include mechanisms; add all custom files to the IPFire backup include list; run a post-update validation script. Store all custom iptables rules in `firewall.local` only (explicitly preserved across updates).

---

## Implications for Roadmap

Based on research, the architecture has hard sequential dependencies that dictate phase order. Services cannot be safely configured before NIC persistence is verified. Suricata cannot be tuned before zones are stable. The telemetry pipeline has no value before Suricata is emitting EVE JSON. Reproducibility cannot be validated until all configurations are stable.

### Phase 1: Platform Foundation and NIC Persistence

**Rationale:** Every subsequent capability depends on correct, stable NIC-to-zone assignment. Zone swap after a kernel update is the single highest-consequence failure mode on this hardware. This must be resolved first with zero shortcuts.
**Delivers:** All 6 NICs persistently mapped via udev rules; zone assignments survive reboot and kernel updates; baseline MAC-to-PCIe mapping documented; i226-V link stability confirmed; anti-lockout `firewall.local` rule in place before any zone policies are configured.
**Addresses:** Stateful firewall, NAT/masquerade, zone segmentation (GREEN/RED/ORANGE/BLUE), anti-lockout policy
**Avoids:** Pitfall 1 (NIC ordering), Pitfall 2 (management lockout)
**Research flag:** Standard patterns, well-documented in IPFire docs. Skip research-phase.

### Phase 2: Core Network Services

**Rationale:** DHCP, DNS, and NTP are infrastructure services that must function before any application layer can be tested. DNS-over-TLS and DNSSEC should be configured here rather than retrofitted, since they affect all downstream clients.
**Delivers:** DHCP server on GREEN (and BLUE if wireless is needed); Unbound DNS with DNSSEC validation and DNS-over-TLS upstream; NTP service serving all zones; static DHCP leases committed to repo.
**Addresses:** DHCP per zone, DNS resolver + DNSSEC + DoT, NTP service
**Avoids:** Pitfall 2 (rule changes breaking DNS/NTP needed by IPFire itself before "Outgoing Blocked" is enabled)
**Research flag:** Standard patterns. Skip research-phase.

### Phase 3: SSH Hardening and Management Security

**Rationale:** SSH hardening is a prerequisite for safe remote administration during all subsequent phases. Must be in place before Suricata IPS is enabled (to prevent IPS rules from accidentally blocking SSH management traffic).
**Delivers:** Key-only SSH authentication; IP allowlist restricting SSH to management subnet; Guardian installed and active; WUI access restricted to management zone; 15-minute SSH auto-disable configured.
**Addresses:** SSH hardening, brute-force protection, management anti-lockout
**Avoids:** Pitfall 2 (lockout), security mistake of SSH accessible from all GREEN hosts
**Research flag:** Standard patterns. Skip research-phase.

### Phase 4: Suricata IDS/IPS

**Rationale:** IPS must be deployed in monitor-only mode first to establish a false-positive baseline on this specific network before enabling blocking. Rule category selection is critical on N100 hardware — the wrong approach causes resource exhaustion. This phase must measure CPU/RAM impact before committing to any rule category.
**Delivers:** Suricata enabled on RED (and GREEN for lateral movement detection); ET Community + IPFire DBL rulesets; monitor-only mode with documented baselining period; EVE JSON confirming alert output to `/var/log/suricata/eve.json`; Suricata memcap limits configured; transition to active IPS after baselining.
**Addresses:** IDS/IPS with auto-updating rulesets, IPS alert forwarding, domain blocklist
**Avoids:** Pitfall 3 (rule overload), anti-pattern of enabling IPS on all zones without tuning
**Research flag:** IPS rule tuning for home/SOHO traffic profile may benefit from a research-phase. The IPS-to-monitor-mode workflow is well-documented; specific rule category selection for N100 is less documented.

### Phase 5: Telemetry Pipeline

**Rationale:** Telemetry depends on Suricata emitting EVE JSON (Phase 4) and on stable routing to the off-box monitoring host (Phase 2). EVE JSON is the primary data source — without IPS active, the dashboard is empty. The off-box Docker architecture is mandatory.
**Delivers:** Grafana Alloy on monitoring host receiving IPFire UDP syslog on port 514; EVE JSON ingested via file-read path (NFS mount or rsync from IPFire); Loki storing labeled log data; Grafana 12.4.1 with Suricata dashboard ID 22247 imported; Prometheus scraping IPFire collectd metrics; threat-tracing dashboard operational.
**Uses:** Grafana Alloy 1.14.1, Loki 3.6.x, Grafana 12.4.1, Prometheus 3.10.0, Docker Compose v2 (all on monitoring host)
**Implements:** Off-box telemetry architecture; EVE JSON file-read path (Pattern A); UDP syslog path (Pattern B)
**Avoids:** Anti-pattern 4 (relying on UDP syslog for EVE alerts — EVE only in file), Pitfall 4 (Docker on IPFire host)
**Research flag:** EVE JSON file-read path from off-box host (NFS vs rsync vs other) needs validation on the live system. Alloy configuration for IPFire's specific syslog format may require iteration. Recommend a research-phase for this phase.

### Phase 6: System Hardening and Validation Suite

**Rationale:** System hardening and the validation suite can only be finalized once all services are stable. The validation suite proves every capability works — it is the mechanism that validates the rebuild goal. Cannot be written until the happy path is established.
**Delivers:** Unused services disabled; Lynis security audit completed and findings addressed; IPFire backup include list covering all custom files; post-update validation script that checks NIC order, Suricata config, firewall.local, and zone assignments; full scripted validation suite with pass/fail output; system hardening applied per IPFire security hardening guide.
**Addresses:** System hardening, full validation suite, anti-lockout verification
**Avoids:** Pitfall 5 (Core Updates overwriting configs), "looks done but isn't" failures from the pitfalls checklist
**Research flag:** Standard patterns for IPFire hardening (documented in official wiki). Validation script content is project-specific. Skip research-phase.

### Phase 7: Reproducibility and Disaster Recovery

**Rationale:** The project's core value proposition is "rebuild from repo in minutes." This phase proves that claim. It can only be validated after all configurations are stable and committed.
**Delivers:** All `/var/ipfire/` configurations exported and committed to repo; udev rules in repo; Pakfire add-on install list in repo; rebuild script that applies full configuration to a fresh IPFire install idempotently; rollback procedures documented per change category (firewall rules, IPS rules, DNS, DHCP, zone config); decision log (ADRs) committed; test rebuild executed on a clean IPFire install to verify.
**Addresses:** Git-based reproducibility, rollback procedures, decision log
**Avoids:** Pitfall 5 (backup restore version incompatibility), technical debt of ad-hoc configs outside version control
**Research flag:** Standard git and shell scripting patterns. IPFire-specific config file locations are well-documented. Skip research-phase.

### Phase Ordering Rationale

- **NIC persistence precedes all configuration** (Phase 1 before everything): Zone swap is an irreversible security failure. The one-time cost of establishing correct udev anchors before any zone config is the safest possible sequencing.
- **Core services before security overlays** (Phase 2 before Phase 3-4): IPS rules that block DNS or NTP would lock IPFire out of its own updates. DHCP and DNS must be operational and verified before adding layers that could interfere.
- **SSH hardening before IPS activation** (Phase 3 before Phase 4): IPS rules in the `emerging-policy` category are documented to block Linux package manager traffic. Hardened management access ensures that even if IPS causes issues, recovery remains possible.
- **IPS before telemetry** (Phase 4 before Phase 5): The telemetry pipeline's primary value is Suricata EVE JSON. An empty dashboard during setup obscures whether the pipeline itself is working. IPS must be confirmed emitting alerts before the pipeline is worth building.
- **Hardening and validation after all services are stable** (Phase 6 after Phases 1-5): The validation suite tests the complete system. It cannot be written until all components are known. Post-update validation scripts cannot be tested until there is something to update.
- **Reproducibility last** (Phase 7): Rebuild scripts can only be written after configurations are finalized. Committing half-complete configs to repo and then continuing to iterate creates confusion. Phase 7 is the "freeze and package" step.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 4 (IDS/IPS):** IPS rule category selection tuned to home/SOHO traffic on N100 hardware is not well-documented in one place. The interaction between IPFire DBL (beta), ET Community, and ThreatFox requires empirical tuning. Recommend a research-phase for optimal memcap settings and rule category selection for this hardware class.
- **Phase 5 (Telemetry Pipeline):** The EVE JSON file-read path from an off-box host has multiple implementation options (NFS mount, rsync pull, SSH tunnel + tail) with different security tradeoffs. Alloy's pipeline stage configuration for IPFire's specific syslog format is not fully documented and requires live system validation. Recommend a research-phase for the Alloy configuration and log ingestion path.

Phases with standard patterns (skip research-phase):
- **Phase 1 (NIC Persistence):** udev rule syntax and IPFire ethernet settings files are well-documented in official IPFire docs and community.
- **Phase 2 (Core Services):** DHCP, Unbound, DoT, and NTP configuration are fully documented in IPFire's official documentation.
- **Phase 3 (SSH Hardening):** Guardian, sshd_config hardening, and `firewall.local` syntax are standard patterns with official documentation.
- **Phase 6 (Hardening + Validation):** IPFire security hardening guide exists in official wiki. Lynis is a standard tool. Backup include list syntax is documented.
- **Phase 7 (Reproducibility):** Git + shell scripting. IPFire config file locations are documented. No novel patterns required.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All technology versions verified from official GitHub releases and Grafana docs (March 2026). Promtail EOL confirmed. Docker rejection confirmed by IPFire lead developer statement. |
| Features | HIGH | IPFire feature set verified against CU199 and CU200 official release notes. Feature boundaries (anti-features) grounded in stated project constraints. |
| Architecture | HIGH (core), MEDIUM (telemetry log path) | Zone model, NIC mapping, Docker boundary: HIGH confidence from official IPFire docs and developer statements. EVE JSON file-read path from off-box host: MEDIUM — multiple community approaches exist; exact implementation requires live system validation. |
| Pitfalls | HIGH | All 5 critical pitfalls corroborated by IPFire community forum threads with specific Core Update version references, plus cross-platform corroboration from OpenWrt, Proxmox, and pfSense issue trackers for the i226-V NIC ordering issue. |

**Overall confidence:** HIGH

### Gaps to Address

- **EVE JSON ingestion path (off-box):** The exact mechanism for the monitoring host to read `/var/log/suricata/eve.json` from IPFire (NFS mount, rsync, SSH tunnel) has security tradeoffs not fully resolved in research. NFS is flagged as a security concern in STACK.md. rsync-pull is the safest but requires SSH key from monitoring host to IPFire. Resolve during Phase 5 planning via research-phase.
- **IPFire DBL beta stability:** The domain blocklist is in beta as of CU200 (March 2026). Its readiness for production activation without causing false positives in Suricata is unknown. Defer DBL activation to Phase 1.x (after initial IPS tuning confirms DBL is stable) or monitor the IPFire blog for a beta-to-stable promotion announcement.
- **Suricata memcap values for N100:** Specific recommended memcap values (`flow-memcap`, `stream-memcap`, `defrag-memcap`) for an N100 with 16 GB single-channel DDR5 running a SOHO ruleset are not documented in IPFire official docs. These need to be empirically determined during Phase 4.
- **collectd metrics to Prometheus bridge:** Pulling IPFire's collectd metrics into Prometheus requires a `collectd_exporter` bridge on the monitoring host using the binary network protocol. This is a non-trivial integration path that has not been validated for IPFire CU200's specific collectd version. An alternative (Zabbix agent via Pakfire) exists but adds a monitoring tool dependency. Resolve during Phase 5 planning.
- **Syslog configuration path for IPS-specific forwarding:** The exact WUI configuration path for forwarding IPS-specific (Suricata) alerts via syslog (vs. general system syslog) was noted as requiring on-system validation in STACK.md. Confirm during Phase 4 setup.

---

## Sources

### Primary (HIGH confidence)
- [IPFire 2.29 Core Update 200 Released](https://www.ipfire.org/blog/ipfire-2-29-core-update-200-released) — CU200 feature set, Suricata version, kernel version, IPFire DBL introduction
- [IPFire IPS Documentation](https://www.ipfire.org/docs/configuration/firewall/ips) — Suricata inline mode, zone selection, monitor vs. active mode
- [IPFire IPS Rulesets Documentation](https://www.ipfire.org/docs/configuration/firewall/ips/rulesets) — ruleset sources, recommendations, OISF deprecation
- [IPFire Docker Feature Request Thread](https://community.ipfire.org/t/feature-request-docker-support/3527) — lead developer rejection statement
- [IPFire Guardian Add-on Documentation](https://www.ipfire.org/docs/addons/guardian) — brute-force protection, updated February 2025
- [IPFire Zone Configuration](https://www.ipfire.org/docs/configuration/network/zoneconf) — zone model, 4-zone hard limit, NIC assignment
- [IPFire firewall.local Documentation](https://www.ipfire.org/docs/configuration/firewall/firewall-local) — safe customization path, preserved across updates
- [Grafana Alloy v1.14.1 Release](https://github.com/grafana/alloy/releases) — current stable, March 17, 2026
- [Grafana 12.4.1](https://grafana.com/grafana/download) — current stable, March 9, 2026
- [Prometheus v3.10.0 Release](https://github.com/prometheus/prometheus/releases) — current stable, February 24, 2026
- [Grafana Loki v3.6 Release Notes](https://grafana.com/docs/loki/latest/release-notes/v3-6/) — current stable
- [Promtail EOL Announcement](https://grafana.com/docs/loki/latest/release-notes/) — EOL confirmed February 28, 2026
- [Suricata EVE JSON Output Documentation](https://docs.suricata.io/en/latest/output/eve/eve-json-output.html) — EVE JSON format and output configuration

### Secondary (MEDIUM confidence)
- [IPFire Community: i226-V rev 04 rate adaptation](https://community.ipfire.org/t/i226-v-rev-04-rate-adaptation/15363) — NIC ordering and link stability
- [IPFire Community: Core Update 194 overwrote suricata.yaml](https://community.ipfire.org/t/ipfire-2-29-core-update-194-overwrote-suricata-yaml/14133) — confirmed Core Update overwrite behavior
- [IPFire Community: Suricata problems CU199-200](https://community.ipfire.org/t/suricata-problems/15532) — IPS instability patterns
- [Network Monitoring and IDS blog post (January 2025)](https://blog.hardill.me.uk/2025/01/11/network-monitoring-and-intrusion-detection/) — Alloy + Loki + Suricata real-world pipeline example
- [IPFire Community: CWWK N100/N150 hardware](https://community.ipfire.org/t/cwwk-n100-n150-is-a-good-option/13811) — N100 zone/NIC configuration in practice
- [Docker Docs: Packet filtering and firewalls](https://docs.docker.com/engine/network/packet-filtering-firewalls/) — Docker iptables bypass documented
- [OpenWrt GitHub: i226 interface naming order changes after upgrade](https://github.com/openwrt/openwrt/issues/17955) — cross-platform corroboration of NIC ordering pitfall

### Tertiary (LOW confidence, requires live validation)
- IPFire syslog UDP-only constraint — multiple community reports; may have changed in recent CUs; requires verification on live system
- Specific Suricata memcap values for N100 with 16 GB single-channel DDR5 — inferred from general Suricata performance guidance; not documented for this specific hardware
- EVE JSON file-read path implementation (NFS vs. rsync vs. SSH tunnel) from off-box host — multiple approaches referenced in community; tradeoffs not fully resolved

---
*Research completed: 2026-03-21*
*Ready for roadmap: yes*
