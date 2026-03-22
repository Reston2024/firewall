<!-- GSD:project-start source:PROJECT.md -->
## Project

**Firewall Appliance**

A fully configured, hardened, reproducible firewall appliance built on an Intel N100-class 6-NIC mini-PC running IPFire. It serves as the primary network gateway with IDS/IPS, network telemetry, threat-tracing dashboards, and automated rebuild capability. All configs, scripts, and validation artifacts live in a Git repo for reproducibility.

**Core Value:** A secure, observable network perimeter that can be rebuilt from scratch in minutes — if the box dies, the repo rebuilds it identically.

### Constraints

- **Platform:** IPFire-native tools and architecture only — no mixing distro paradigms
- **Architecture:** Core firewall/routing/NAT MUST be native; Docker rejected by IPFire — telemetry runs off-box
- **Hardware:** N100 is low-power — telemetry stack must be lightweight or off-boxable
- **Access:** Must preserve management access (anti-lockout) during all network changes
- **Repos:** Only vetted, actively maintained upstream repos (Suricata, Grafana, Loki, Alloy, Prometheus)
- **Zones:** IPFire hard limit of 4 named zones (RED/GREEN/BLUE/ORANGE); extra NICs use Bridge mode
- **Updates:** Core Updates overwrite custom configs — must use backup includes + post-update validation
- **No placeholders:** All configs must be complete and executable, no pseudocode
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Executive Note: Architecture Constraint
## Recommended Stack
### Layer 1: IPFire Core Platform
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| IPFire | 2.29, Core Update 200 | Base OS, firewall, routing, NAT, DNS, DHCP | Purpose-built firewall distro. Zone-based (GREEN/RED/BLUE/ORANGE), WUI at :444, Pakfire for add-ons. Already installed. |
| Linux Kernel | 6.18.7 LTS | Underlying kernel | Ships with CU200 (March 2026). Latest LTS with N100 NIC driver support (Intel i225/i226). |
| Suricata | 8.0.3 | IDS/IPS | Bundled natively in IPFire since Core Update 131. CU200 ships 8.0.3. Managed entirely through WUI. Rule caching, protocol-aware deep inspection. |
| Unbound | 1.24.2 | DNS resolver/DNSSEC | Native IPFire DNS with DNSSEC, multi-threaded since CU200. No extra install needed. |
| IPFire DBL | Beta | Domain blocklist for URL filter + Suricata rules | New in CU200 — replaces retired Shalla list. Free. Works as both proxy URL filter and Suricata ruleset. Block malware/C2 via DNS/TLS/HTTP/QUIC inspection. |
### Layer 2: IPFire Pakfire Add-ons (Install On-Box)
| Package | Pakfire Name | Purpose | Why |
|---------|-------------|---------|-----|
| Guardian | `guardian` | SSH + WUI brute-force protection | IPFire's fail2ban equivalent. Managed via WUI. Detects and blocks brute-force against SSH and the management interface. Updated February 2025. |
| ClamAV | `clamav` | Mail gateway + file scanning | Available via Pakfire. Bundled in core as of CU200 (v1.5.1). |
| Zabbix Agent | `zabbix_agentd` | Host metrics export to external Zabbix server | Available in Pakfire. Exposes DHCP leases, captive portal data, IPFire-specific metrics. Use if you want Zabbix as your monitoring backend. |
| NRPE | `nagios-nrpe` | Nagios/Icinga remote plugin executor | Available in Pakfire. For integrating IPFire into an existing Nagios/Icinga monitoring setup. |
| Lynis | `lynis` | Local system security auditing | Available in Pakfire. Run manually for hardening audits. |
| Arpwatch | `arpwatch` | ARP traffic monitoring / new host detection | Available in Pakfire. Detects new devices joining the network. |
| vnstat | built-in | Per-interface traffic accounting | Built into IPFire core. Powers the native WUI traffic graphs. No install needed. |
| collectd | built-in | System metrics collection (CPU, mem, disk, net) | Built into IPFire core. Feeds the native WUI RRD graphs. No install needed. |
### Layer 3: Suricata IPS Rule Sources
| Ruleset | Cost | Update Frequency | Recommended For | Notes |
|---------|------|-----------------|----------------|-------|
| Emerging Threats Community | Free | Daily | Home / small office | Best free ruleset. No registration. Broad coverage of scanning, C2, malware. Start here. |
| IPFire DBL | Free | Project-maintained | All | New in CU200. Native Suricata rules source. Deep inspection via DNS/TLS/HTTP/QUIC. Enable alongside ET Community. |
| ThreatFox (abuse.ch) | Free | Continuous IOC feed | All | Indicators of compromise. Test in monitor mode first — higher false positive rate. |
| Emerging Threats Pro (Proofpoint) | Paid (~$600/yr commercial) | Daily | Enterprise | 40+ categories, current-day threats. Overkill for home/SOHO. |
| Talos Registered (free tier) | Free | 30-day delayed | Low-risk environments | Snort-native rules may generate errors in Suricata. Delayed feed limits value. |
| OISF Traffic ID | Free | DEAD (last update 2018) | AVOID | Unmaintained. Do not enable. |
### Layer 4: IPS Operating Mode
| Mode | When to Use | Notes |
|------|-------------|-------|
| Monitor Only | Phase 1 (initial deployment, tuning) | Logs alerts but takes no action. Allows baselining legitimate traffic without lockout risk. |
| Active IPS | After tuning complete | Drops matched packets. Requires whitelist tuning first to avoid blocking legitimate traffic (false positives). |
### Layer 5: Log Pipeline (IPS Syslog Forwarding)
| Component | Configuration | Notes |
|-----------|--------------|-------|
| IPFire IPS syslog forward | WUI: Logs > Log Settings > Syslog Server | Sends Suricata alerts to remote syslog. Protocol: UDP, port 514 (default). Non-standard port requires manual `/etc/syslog.conf` edit (reverts on restart — needs scripted persistence). |
| IPFire system syslog | Same WUI setting | General system logs. UDP only natively. TCP forwarding is not yet supported in IPFire's syslog daemon. |
| Suricata EVE JSON | `/var/log/suricata/eve.json` | The canonical Suricata log format. Structured JSON with full alert context (src_ip, dest_ip, signature, category, severity, protocol metadata). **This is the primary data source for dashboards.** |
### Layer 6: Off-Box Telemetry Stack (Separate Machine on LAN/MGMT)
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Grafana | 12.4.1 | Dashboards, alerting, visualization | Latest stable (March 9, 2026). OSS license. Pre-built Suricata dashboard available (ID: 22247). Active development, 12.x adds Git Sync, Drilldown, SQL expressions. |
| Grafana Loki | 3.6.x | Log aggregation (Suricata EVE JSON, system syslog) | Label-based indexing only — much lighter than Elasticsearch. Does not index log content, only metadata labels. N100-class RAM footprint ~250MB. No Kafka/Zookeeper dependencies. |
| Grafana Alloy | 1.14.1 | Log + metrics collection agent (replaces Promtail) | Latest stable (March 17, 2026). Replaces Promtail (EOL February 28, 2026). Supports `loki.source.syslog` (UDP/TCP receiver), file tailing, Prometheus scrape. Single binary. Ships as .deb/.rpm. |
| Prometheus | 3.10.0 | Metrics storage and alerting | Latest stable (February 24, 2026). Scrapes IPFire's collectd-exposed metrics or node_exporter if accessible. |
| Node Exporter | 1.8.x | System metrics from monitoring host | Runs on the monitoring machine. For IPFire host metrics: use collectd bridge or Zabbix agent instead (no node_exporter on IPFire). |
| Docker Compose | v2 | Stack orchestration on monitoring host | Runs on the monitoring machine, NOT on IPFire. Single `docker-compose.yml` for Grafana + Loki + Alloy + Prometheus. |
- **Promtail** — EOL February 28, 2026. Migrate to Alloy. Existing Promtail configs have an automated migration tool.
- **Grafana Agent** — Long-term support ended October 31, 2025. Replaced by Alloy.
- **Elasticsearch/Kibana (ELK stack)** — RAM-intensive (2-4GB+ minimum). Overkill for this use case. Loki is the correct lightweight alternative.
- **OpenSearch** — Same objection as ELK. Heavyweight for SOHO firewall telemetry.
- **InfluxDB v1** — Legacy. If time-series metrics storage beyond Prometheus is needed, use InfluxDB v2 or just Prometheus.
### Layer 7: Dashboard Strategy
| Dashboard | Grafana ID | Source | Covers |
|-----------|-----------|--------|--------|
| Suricata Logs Eve JSON | 22247 | Grafana Labs | Suricata alerts by category, top attacker IPs, alert severity breakdown |
| pfSense Firewall + IDS | 12637 | Grafana Labs | Firewall/IDS panels adaptable to IPFire syslog format (requires relabeling) |
| Node Exporter Full | 1860 | Grafana Labs | System metrics for the monitoring host |
## IPFire-Specific Constraints Summary
| Constraint | Impact | Mitigation |
|-----------|--------|-----------|
| No Docker in Pakfire | Telemetry stack cannot run on IPFire box | Run Grafana/Loki/Alloy/Prometheus on separate machine |
| Syslog UDP only (native) | Cannot use TCP syslog to off-box stack natively | Use Alloy as UDP syslog receiver on monitoring host |
| Non-standard syslog port reverts | Port 514 only reliably supported out-of-box | Use port 514, OR persist `/etc/syslog.conf` edit via boot script |
| IPFire syslog ≠ all logs forwarded | Not all system logs forward via syslog setting | Primary telemetry target should be Suricata EVE JSON via syslog, not full system log |
| No fail2ban in Pakfire | Cannot use fail2ban for SSH protection | Use Guardian (Pakfire) — IPFire's purpose-built brute force protection |
| collectd/vnstat built-in but no exporter | Cannot easily scrape IPFire metrics into Prometheus without a bridge | Options: Zabbix Agent (in Pakfire), SNMP, or collectd-binary-network-protocol-to-Prometheus bridge on monitoring host |
| ReiserFS deprecated | Systems on ReiserFS cannot upgrade to CU200 | Verify filesystem before upgrade. Reinstall if needed. |
## Full Installation Reference
### On IPFire (Pakfire)
# Install via console
# Verify Suricata version
# Check available packages
### Enable IPS via WUI
### On Monitoring Host (Docker Compose)
# docker-compose.yml
### Grafana Alloy Config (alloy-config.alloy) — Syslog Receiver
## Alternatives Considered
| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Log storage | Loki 3.6 | Elasticsearch/OpenSearch | 4-8x higher RAM. Complex schema. Overkill for single-node SOHO. |
| Log storage | Loki 3.6 | InfluxDB (for logs) | Not designed for log storage. Use InfluxDB for metrics only if needed. |
| Log agent | Grafana Alloy 1.14.1 | Promtail | EOL Feb 28, 2026. No further support. |
| Log agent | Grafana Alloy 1.14.1 | Logstash | Java runtime, 512MB+ RAM baseline. Heavy for SOHO. |
| IDS | Suricata 8.0.3 (native) | Snort | Replaced in IPFire since CU131. Not available via Pakfire for IPFire 2.x. |
| IDS | Suricata 8.0.3 (native) | Zeek | Not in Pakfire. Would require manual compilation against IPFire's custom buildroot. High maintenance risk. |
| SSH brute force | Guardian (Pakfire) | fail2ban | fail2ban not in Pakfire. Guardian is the IPFire-native equivalent. |
| Metrics scrape | collectd (built-in) + collectd_exporter | Node Exporter on IPFire | Node Exporter cannot be installed natively on IPFire (no package). collectd is already running; bridge via collectd binary network protocol to Prometheus collectd_exporter on monitoring host. |
| Dashboard | Grafana 12.4.1 | Kibana | Requires Elasticsearch. Heavyweight. No benefit over Grafana+Loki for this use case. |
## Confidence Assessment
| Area | Confidence | Source |
|------|------------|--------|
| IPFire version / Suricata version | HIGH | Official IPFire CU200 release notes (March 2026) |
| Docker NOT available on IPFire | HIGH | Official IPFire developer statement, community forum |
| Guardian replaces fail2ban | HIGH | Official IPFire add-ons docs, community confirmation |
| Pakfire add-on list (completeness) | MEDIUM | Official docs + community searches; not exhaustively verified via live `pakfire list` |
| Suricata EVE JSON → Loki pipeline | MEDIUM | Multiple 2024-2025 community guides, Grafana official docs |
| Syslog UDP-only constraint | MEDIUM | Multiple community reports; may have changed in recent CUs |
| IPS syslog forwarding feature (CU198+) | HIGH | Official CU198 release notes |
| Grafana/Loki/Alloy/Prometheus versions | HIGH | Official GitHub releases, all verified March 2026 |
| Off-box architecture requirement | HIGH | Direct consequence of Docker rejection; IPFire developer guidance |
## Sources
- [IPFire 2.29 Core Update 200 Released](https://www.ipfire.org/blog/ipfire-2-29-core-update-200-released) — official release notes, March 2, 2026
- [IPFire 2.29 Core Update 198 Released — Suricata 8 and IPS syslog](https://linuxiac.com/ipfire-2-29-released-with-suricata-8-and-real-time-ips-email-reporting/) — Linuxiac, 2025
- [IPFire IPS Documentation](https://www.ipfire.org/docs/configuration/firewall/ips) — official
- [IPFire IPS Rulesets Documentation](https://www.ipfire.org/docs/configuration/firewall/ips/rulesets) — official
- [IPFire Guardian Add-on Documentation](https://www.ipfire.org/docs/addons/guardian) — official, updated February 2025
- [IPFire Add-ons Overview](https://www.ipfire.org/docs/addons) — official
- [IPFire Docker Feature Request Thread](https://community.ipfire.org/t/feature-request-docker-support/3527) — developer rejection statement
- [IPFire Log Settings (syslog)](https://wiki.ipfire.org/configuration/logs/logsettings) — official wiki
- [Suricata EVE JSON Output Documentation](https://docs.suricata.io/en/latest/output/eve/eve-json-output.html) — official Suricata docs
- [Grafana Alloy v1.14.1 Release](https://github.com/grafana/alloy/releases) — GitHub, March 17, 2026
- [Grafana 12.4.1 Download](https://grafana.com/grafana/download) — official, March 9, 2026
- [Prometheus v3.10.0 Release](https://github.com/prometheus/prometheus/releases) — GitHub, February 24, 2026
- [Grafana Loki v3.6 Release Notes](https://grafana.com/docs/loki/latest/release-notes/v3-6/) — official
- [Promtail EOL Announcement](https://grafana.com/docs/loki/latest/release-notes/) — Grafana Labs, February 2026
- [Suricata Logs Eve JSON Dashboard #22247](https://grafana.com/grafana/dashboards/22247-suricata-logs-json/) — Grafana Labs community dashboard
- [Network Monitoring and IDS blog post (January 2025)](https://blog.hardill.me.uk/2025/01/11/network-monitoring-and-intrusion-detection/) — Alloy + Loki + Suricata real-world example
- [Grafana Alloy on Raspberry Pi (August 2025)](https://exploding-kitten.com/2025/08-grafana-alloy) — lightweight hardware reference
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd:quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd:debug` for investigation and bug fixing
- `/gsd:execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
