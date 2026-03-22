# Technology Stack

**Project:** IPFire Firewall Appliance — N100 6-NIC Mini-PC
**Researched:** 2026-03-21
**Research Mode:** Ecosystem

---

## Executive Note: Architecture Constraint

The PROJECT.md states "Docker for non-core services (telemetry, dashboards, reverse proxy)." This is **incompatible with IPFire's platform** as designed. The IPFire development team has explicitly rejected Docker on security grounds — the project lead stated: *"I am absolutely against allowing IPFire users to run arbitrary (i.e. untrusted) Docker containers on their systems."* Docker is not in Pakfire and will not be.

This has a direct impact on the telemetry/dashboard stack architecture: **the Grafana/Loki/Prometheus stack must run off-box** — on a separate machine in the LAN or DMZ — not on the IPFire appliance itself. IPFire's security model treats itself as a sealed appliance. All research below reflects this constraint.

**Confidence:** HIGH — official IPFire developer statement, no workarounds found.

---

## Recommended Stack

### Layer 1: IPFire Core Platform

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| IPFire | 2.29, Core Update 200 | Base OS, firewall, routing, NAT, DNS, DHCP | Purpose-built firewall distro. Zone-based (GREEN/RED/BLUE/ORANGE), WUI at :444, Pakfire for add-ons. Already installed. |
| Linux Kernel | 6.18.7 LTS | Underlying kernel | Ships with CU200 (March 2026). Latest LTS with N100 NIC driver support (Intel i225/i226). |
| Suricata | 8.0.3 | IDS/IPS | Bundled natively in IPFire since Core Update 131. CU200 ships 8.0.3. Managed entirely through WUI. Rule caching, protocol-aware deep inspection. |
| Unbound | 1.24.2 | DNS resolver/DNSSEC | Native IPFire DNS with DNSSEC, multi-threaded since CU200. No extra install needed. |
| IPFire DBL | Beta | Domain blocklist for URL filter + Suricata rules | New in CU200 — replaces retired Shalla list. Free. Works as both proxy URL filter and Suricata ruleset. Block malware/C2 via DNS/TLS/HTTP/QUIC inspection. |

**Confidence:** HIGH — verified via official IPFire release notes for CU200 (March 2, 2026).

---

### Layer 2: IPFire Pakfire Add-ons (Install On-Box)

These are packages available in Pakfire's official repository. Install via WUI or `pakfire install <name>`.

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

**NOT available in Pakfire (verified):** `docker`, `fail2ban`, `zeek`, `netdata` (official). A community-built Netdata package exists at `siosios/Netdata-on-Ipfire` on GitHub but is unofficial and carries maintenance risk.

**Confidence:** HIGH for Guardian, collectd, vnstat (documented). MEDIUM for full add-on list (queried official docs; complete inventory requires `pakfire list` on live system).

---

### Layer 3: Suricata IPS Rule Sources

| Ruleset | Cost | Update Frequency | Recommended For | Notes |
|---------|------|-----------------|----------------|-------|
| Emerging Threats Community | Free | Daily | Home / small office | Best free ruleset. No registration. Broad coverage of scanning, C2, malware. Start here. |
| IPFire DBL | Free | Project-maintained | All | New in CU200. Native Suricata rules source. Deep inspection via DNS/TLS/HTTP/QUIC. Enable alongside ET Community. |
| ThreatFox (abuse.ch) | Free | Continuous IOC feed | All | Indicators of compromise. Test in monitor mode first — higher false positive rate. |
| Emerging Threats Pro (Proofpoint) | Paid (~$600/yr commercial) | Daily | Enterprise | 40+ categories, current-day threats. Overkill for home/SOHO. |
| Talos Registered (free tier) | Free | 30-day delayed | Low-risk environments | Snort-native rules may generate errors in Suricata. Delayed feed limits value. |
| OISF Traffic ID | Free | DEAD (last update 2018) | AVOID | Unmaintained. Do not enable. |

**Recommendation:** Enable **Emerging Threats Community + IPFire DBL** as the standard pair. Add ThreatFox after initial tuning in monitor mode. Avoid OISF Traffic ID entirely.

**Confidence:** HIGH — from official IPFire IPS rulesets documentation.

---

### Layer 4: IPS Operating Mode

| Mode | When to Use | Notes |
|------|-------------|-------|
| Monitor Only | Phase 1 (initial deployment, tuning) | Logs alerts but takes no action. Allows baselining legitimate traffic without lockout risk. |
| Active IPS | After tuning complete | Drops matched packets. Requires whitelist tuning first to avoid blocking legitimate traffic (false positives). |

**Recommendation:** Deploy in Monitor mode for the first phase. After establishing a false-positive baseline, switch to Active IPS. Whitelist known-good hosts explicitly before switching.

**Confidence:** HIGH — from official IPFire IPS documentation.

---

### Layer 5: Log Pipeline (IPS Syslog Forwarding)

Since Core Update 198, IPFire's IPS supports native remote syslog forwarding for Suricata alerts.

| Component | Configuration | Notes |
|-----------|--------------|-------|
| IPFire IPS syslog forward | WUI: Logs > Log Settings > Syslog Server | Sends Suricata alerts to remote syslog. Protocol: UDP, port 514 (default). Non-standard port requires manual `/etc/syslog.conf` edit (reverts on restart — needs scripted persistence). |
| IPFire system syslog | Same WUI setting | General system logs. UDP only natively. TCP forwarding is not yet supported in IPFire's syslog daemon. |
| Suricata EVE JSON | `/var/log/suricata/eve.json` | The canonical Suricata log format. Structured JSON with full alert context (src_ip, dest_ip, signature, category, severity, protocol metadata). **This is the primary data source for dashboards.** |

**Critical constraint:** IPFire's built-in syslog only supports UDP (not TCP) for remote forwarding. For reliable log shipping to an off-box stack, the preferred approach is:

1. **Mount `/var/log/suricata/` via NFS/SMB from the monitoring host** — not recommended (security concerns).
2. **Use IPFire's native syslog UDP forward to port 514 on the monitoring host** — viable for real-time alerts.
3. **Have the monitoring stack's log agent open an SSH tunnel and tail `eve.json` directly** — LOW confidence, complex.
4. **Deploy Grafana Alloy on the monitoring host listening on UDP 514 as a syslog receiver** — RECOMMENDED. Alloy's `loki.source.syslog` component accepts RFC 3164 UDP on any port.

**Confidence:** MEDIUM — syslog UDP limitation confirmed by community. IPS syslog forwarding feature confirmed in CU198 release notes. Exact WUI configuration path for IPS-specific syslog not fully documented; requires on-system validation.

---

### Layer 6: Off-Box Telemetry Stack (Separate Machine on LAN/MGMT)

This stack runs on a separate host (physical machine, VM, or Raspberry Pi) on the GREEN or MGMT network segment. Not on IPFire.

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Grafana | 12.4.1 | Dashboards, alerting, visualization | Latest stable (March 9, 2026). OSS license. Pre-built Suricata dashboard available (ID: 22247). Active development, 12.x adds Git Sync, Drilldown, SQL expressions. |
| Grafana Loki | 3.6.x | Log aggregation (Suricata EVE JSON, system syslog) | Label-based indexing only — much lighter than Elasticsearch. Does not index log content, only metadata labels. N100-class RAM footprint ~250MB. No Kafka/Zookeeper dependencies. |
| Grafana Alloy | 1.14.1 | Log + metrics collection agent (replaces Promtail) | Latest stable (March 17, 2026). Replaces Promtail (EOL February 28, 2026). Supports `loki.source.syslog` (UDP/TCP receiver), file tailing, Prometheus scrape. Single binary. Ships as .deb/.rpm. |
| Prometheus | 3.10.0 | Metrics storage and alerting | Latest stable (February 24, 2026). Scrapes IPFire's collectd-exposed metrics or node_exporter if accessible. |
| Node Exporter | 1.8.x | System metrics from monitoring host | Runs on the monitoring machine. For IPFire host metrics: use collectd bridge or Zabbix agent instead (no node_exporter on IPFire). |
| Docker Compose | v2 | Stack orchestration on monitoring host | Runs on the monitoring machine, NOT on IPFire. Single `docker-compose.yml` for Grafana + Loki + Alloy + Prometheus. |

**What NOT to use:**
- **Promtail** — EOL February 28, 2026. Migrate to Alloy. Existing Promtail configs have an automated migration tool.
- **Grafana Agent** — Long-term support ended October 31, 2025. Replaced by Alloy.
- **Elasticsearch/Kibana (ELK stack)** — RAM-intensive (2-4GB+ minimum). Overkill for this use case. Loki is the correct lightweight alternative.
- **OpenSearch** — Same objection as ELK. Heavyweight for SOHO firewall telemetry.
- **InfluxDB v1** — Legacy. If time-series metrics storage beyond Prometheus is needed, use InfluxDB v2 or just Prometheus.

**Confidence:** HIGH — all versions verified from official GitHub releases and Grafana documentation. Promtail EOL confirmed from Grafana official announcement.

---

### Layer 7: Dashboard Strategy

| Dashboard | Grafana ID | Source | Covers |
|-----------|-----------|--------|--------|
| Suricata Logs Eve JSON | 22247 | Grafana Labs | Suricata alerts by category, top attacker IPs, alert severity breakdown |
| pfSense Firewall + IDS | 12637 | Grafana Labs | Firewall/IDS panels adaptable to IPFire syslog format (requires relabeling) |
| Node Exporter Full | 1860 | Grafana Labs | System metrics for the monitoring host |

**Recommendation:** Start with dashboard 22247 for Suricata. Customize label extraction in Alloy's `loki.source.syslog` pipeline stage to enrich logs with `src_ip`, `dest_ip`, `signature`, `category`, `severity` as Loki labels.

**Confidence:** MEDIUM — dashboard IDs verified in search results. Actual compatibility with IPFire's exact syslog format requires validation.

---

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

---

## Full Installation Reference

### On IPFire (Pakfire)

```bash
# Install via console
pakfire install guardian
pakfire install lynis
pakfire install arpwatch
pakfire install zabbix_agentd   # if using Zabbix for metrics

# Verify Suricata version
suricata --build-info | head -5

# Check available packages
pakfire list
```

### Enable IPS via WUI

1. Navigate to: Firewall > Intrusion Prevention System
2. Enable IPS
3. Set mode: Monitor Traffic Only (initially)
4. Select zones: RED (WAN-facing), optionally GREEN
5. Enable rulesets: Emerging Threats Community + IPFire DBL
6. Configure remote syslog: Logs > Log Settings > Syslog Server = `<monitoring-host-ip>`, Protocol = UDP, Port = 514

### On Monitoring Host (Docker Compose)

```yaml
# docker-compose.yml
version: "3.8"
services:
  loki:
    image: grafana/loki:3.6.0
    container_name: loki
    ports:
      - "3100:3100"
    command: -config.file=/etc/loki/loki-config.yml
    volumes:
      - ./loki-config.yml:/etc/loki/loki-config.yml
      - loki-data:/loki
    restart: unless-stopped

  alloy:
    image: grafana/alloy:v1.14.1
    container_name: alloy
    ports:
      - "514:514/udp"    # syslog receiver from IPFire
      - "12345:12345"    # Alloy UI
    volumes:
      - ./alloy-config.alloy:/etc/alloy/config.alloy
    restart: unless-stopped

  prometheus:
    image: prom/prometheus:v3.10.0
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    restart: unless-stopped

  grafana:
    image: grafana/grafana:12.4.1
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=changeme
    volumes:
      - grafana-data:/var/lib/grafana
    restart: unless-stopped

volumes:
  loki-data:
  prometheus-data:
  grafana-data:
```

### Grafana Alloy Config (alloy-config.alloy) — Syslog Receiver

```alloy
// Receive syslog from IPFire on UDP 514
loki.source.syslog "ipfire" {
  listener {
    address  = "0.0.0.0:514"
    protocol = "udp"
  }
  forward_to = [loki.process.suricata.receiver]
}

// Parse Suricata EVE JSON fields for labeling
loki.process "suricata" {
  stage.json {
    expressions = {
      event_type   = "event_type",
      src_ip       = "src_ip",
      dest_ip      = "dest_ip",
      proto        = "proto",
      alert        = "alert",
    }
  }
  stage.labels {
    values = {
      event_type = "event_type",
      src_ip     = "src_ip",
      proto      = "proto",
    }
  }
  forward_to = [loki.write.default.receiver]
}

loki.write "default" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}
```

---

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

---

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

---

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
