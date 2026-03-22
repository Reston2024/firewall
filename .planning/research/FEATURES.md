# Feature Research

**Domain:** Hardened firewall appliance — IPFire on Intel N100 6-NIC mini-PC, production home/small-office
**Researched:** 2026-03-21
**Confidence:** HIGH (IPFire-specific claims verified against official docs; comparative claims verified against multiple sources)

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features whose absence makes the appliance not production-ready. No credit for having them; immediate failure for missing them.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Stateful firewall with default-deny inbound** | The entire purpose of a firewall gateway; any packet filter without stateful inspection is not a firewall | LOW | IPFire native: Netfilter/SPI engine, default policy drops unsolicited inbound. Configured via WUI Firewall Rules. |
| **NAT / IP masquerade on WAN (RED)** | Required to share a single ISP-assigned IP across all internal hosts | LOW | IPFire native: masquerade enabled per zone. All GREEN/BLUE/ORANGE clients NAT through RED automatically. Config at `wiki.ipfire.org/configuration/firewall/masquerading`. |
| **Port forwarding (DNAT)** | Any hosted service (remote desktop, game server, NAS) requires inbound DNAT | LOW | IPFire native: Firewall Rules → New Rule → NAT → DNAT. External port optionally differs from internal. |
| **Zone-based network segmentation** | Physical multi-NIC hardware only has value if zones are isolated by policy | MEDIUM | IPFire native: GREEN (LAN), RED (WAN), ORANGE (DMZ), BLUE (WiFi/IoT). Default inter-zone policy is deny; pinholes must be explicitly created. |
| **DHCP server per zone** | Hosts on each zone need automatic IP assignment | LOW | IPFire native: DHCP server per interface (GREEN, BLUE). Supports static leases, PXE, NTP injection. Config stored at `/var/ipfire/dhcp/dhcpd.conf`. |
| **Recursive DNS resolver with DNSSEC** | All internal clients resolve through the firewall; DNSSEC mandatory for integrity | LOW | IPFire native: Unbound replaces dnsmasq. DNSSEC validation is mandatory and cannot be disabled. Multi-threaded as of Core Update 200 (one thread per CPU core). |
| **NTP service** | All hosts need synchronized time; mismatched clocks break TLS, auth, and log correlation | LOW | IPFire native: NTP server built in, syncs to upstream pools and serves clients via DHCP NTP option. |
| **SSH management access** | Remote configuration and scripting require SSH | LOW | IPFire native: OpenSSH 10.2p1 (CU199). Best practice: use 15-minute expiry button, key-only auth, whitelist management IP. |
| **IDS/IPS (Suricata)** | Without active threat detection the appliance is just a packet filter | MEDIUM | IPFire native: Suricata 8.0.3 (CU200). Multi-threaded, multi-ruleset (ET Community, ET Pro, Abuse.ch ThreatFox). Zone-selectable. Monitor-only mode for tuning. |
| **Automatic rule/signature updates** | Threat signatures go stale in hours; manual updates are operationally unsafe | LOW | IPFire native: per-provider auto-update toggle in IPS configuration. Daily updates for ET Pro. |
| **System log viewer** | Operators need to inspect firewall, IPS, DHCP, DNS, and system events | LOW | IPFire native: WUI → Logs section covers firewall, IPS, system, proxy logs. Remote syslog forwarding via UDP to external collectors. |
| **Reboot-persistent configuration** | Configs that vanish on reboot are not production | LOW | IPFire native: all WUI configuration writes to persistent storage under `/var/ipfire/`. |
| **SSH brute-force protection** | Exposed SSH is the most common initial access vector | LOW | IPFire via Pakfire: Guardian or fail2ban. Fail2ban jail config, key-only auth, IP allowlist in `ignoreip`. |
| **Management anti-lockout** | Misconfigured rules must not cut off management access | LOW | IPFire design: GREEN interface always reaches WUI. SSH 15-minute auto-disable. Rule changes apply immediately — no confirmation window; operator discipline required. |
| **WAN connectivity validation** | Appliance must prove internet reachability before being considered functional | LOW | Validation script responsibility: ping external IP, DNS resolution, NTP sync, reachable from GREEN. |

---

### Differentiators (Competitive Advantage Over Stock IPFire)

These features are not present out of the box in a fresh IPFire install. They are what separates this project from "default IPFire install" and deliver the stated core value: observable, reproducible, rebuild-from-repo appliance.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Git-based reproducibility (config-as-code)** | Box dies → repo rebuilds it identically; enables audit trail, diffing, rollback | MEDIUM | No IPFire native equivalent. Requires exporting all `/var/ipfire/` configs and Pakfire add-on lists to a repo. Rebuild script applies configs to fresh install idempotently. This is the project's primary differentiator vs. stock IPFire. |
| **Persistent NIC-to-zone mapping** | 6-NIC hardware has no guaranteed interface ordering across reboots/kernel updates | MEDIUM | IPFire uses `udev` rules by MAC address. Must be deliberately engineered; not automatic. Prevents zone-swap security failures after hardware changes. |
| **Network telemetry pipeline (firewall logs → processing → visualization)** | Transforms raw syslog into queryable, graphable, searchable event store | HIGH | Not in IPFire stock. IPFire sends UDP syslog (port 514). Collector (Promtail/Alloy/Filebeat) + Loki + Grafana is the lightweight path for N100. OpenSearch is viable but resource-heavy. Pipeline must be dockerized, kept off the core firewall data plane. |
| **Threat-tracing dashboard** | End-to-end: source IP → IPS alert → action taken → geolocation, visible in a single pane | HIGH | Differentiates from IPFire's built-in WUI log viewer (paginated tables, no time-series, no correlation). Grafana dashboards with Loki-backed IPS alert logs and firewall drop logs. Requires log enrichment (DNS hostname, GeoIP). |
| **IPS alert email + PDF reporting** | Scheduled summaries and threshold-based alerts without requiring dashboard access | MEDIUM | IPFire CU199/CU200 native (new in 2026): IPS reporter sends alert emails and PDF reports (daily/weekly/monthly). Requires SMTP configuration. This is now semi-table-stakes but not configured on fresh install. |
| **DNS-over-TLS enforcement** | Prevents ISP/on-path observation of DNS queries from all internal clients | LOW | IPFire native capability but not enabled by default. Must configure DoT upstream resolvers (Cloudflare 1.1.1.1, Quad9, etc.) with TLS hostname and enforce via WUI toggle. |
| **Domain blocklist (IPFire DBL)** | Blocks ads, malware C2, and adult content at DNS layer before browser load | LOW | IPFire CU200 native (beta as of March 2026): IPFire DBL integrated into URL Filter and Suricata. Replaces deprecated Shalla list. Requires explicit activation. |
| **Full validation suite** | Proves every capability works after build or rebuild; not a manual checklist | HIGH | Not in any stock firewall distro. Custom shell scripts: NIC binding, zone routing, NAT, DNS, DHCP, IPS rule load, firewall hit/drop, reboot persistence, SSH lockout test. |
| **Rollback procedures per change category** | Every class of change (firewall rules, IPS rules, DNS, DHCP, zone config) has a documented undo path | MEDIUM | IPFire docs acknowledge rollback procedures are "yet to be written" for some areas. Must be engineered from scratch and stored in repo. |
| **Decision log (ADR format)** | Every architectural choice is documented with rationale and outcome | LOW | Git repo artifact. Prevents revisiting settled decisions. Feeds future operators. |
| **Docker-based supporting services** | Keeps non-core workloads (telemetry, dashboards) isolated from the firewall data plane | MEDIUM | IPFire native: Docker available via Pakfire. Core firewall/routing/NAT must remain native; Docker only for telemetry stack. Resource budget matters on N100 (6W TDP). |
| **OPT zone activation (3 optional segments)** | 6 NICs allow WAN + LAN + MGMT + 3 additional security segments beyond stock GREEN+RED | MEDIUM | IPFire supports ORANGE (DMZ) and BLUE (IoT/WiFi) natively. A dedicated management zone (MGMT) on a physical NIC with strict access rules is an additional hardening step not in stock IPFire. Uses remaining OPT ports. |
| **Source NAT (SNAT) for multi-IP scenarios** | When RED has multiple IPs, specific internal hosts or servers can exit on designated IPs | LOW | IPFire native capability (Firewall Rules → Source NAT), but rarely configured on stock installs. Value for servers behind the firewall needing known egress IPs. |

---

### Anti-Features (Deliberately NOT Building)

Features that sound useful but create scope creep, complexity, or conflict with the project constraints.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **VPN server (IPsec/OpenVPN/WireGuard)** | Remote access to internal network from outside | Separate concern; adds key management, certificate lifecycle, split-tunneling policy complexity. PROJECT.md explicitly out-of-scope. | Separate project after firewall is validated. IPFire supports all three protocols natively when needed. |
| **WiFi AP management** | Convenient to manage APs from the firewall | Dedicated AP hardware runs its own controller (OpenWRT, Ubiquiti, etc.). Mixing AP management into the firewall creates coupling. PROJECT.md explicitly out-of-scope. | Dedicated APs with their own management plane; BLUE zone provides segmentation. |
| **Full ELK/OpenSearch stack on-box** | Most tutorials use ELK; familiar to operators | OpenSearch is resource-heavy — JVM heap alone consumes 1-4GB RAM on an N100 with 16GB. Competes with Suricata and Docker daemon for CPU. | Grafana + Loki stack (columnar, label-indexed) is 5-10x more efficient on constrained hardware. Off-box OpenSearch is viable if a second host exists. |
| **AI/ML threat detection (Zenarmor, etc.)** | Emerging standard in commercial NGFWs | Requires subscription, additional agent, and significant CPU for inference. N100 is not dimensioned for real-time ML inference on wire-speed traffic. | Curated Suricata rulesets (ET Pro, Abuse.ch) provide signature-based detection appropriate for this hardware class. |
| **Web filtering / Squid proxy** | URL-level content blocking, bandwidth caching | Adds TLS inspection complexity (MITM CA), breaks certificate pinning, increases RAM use significantly. DNS-layer blocking via IPFire DBL covers the primary use case without man-in-the-middle. | IPFire DBL (CU200) for DNS-layer blocking; Suricata for encrypted-traffic behavioral analysis. |
| **GUI-based configuration tools beyond IPFire WUI** | Web GUI wrappers, Ansible Galaxy roles, etc. are tempting for automation | IPFire's architecture assumes WUI writes configs to `/var/ipfire/`. External tools that bypass WUI can corrupt config state. PROJECT.md explicitly: native tools only. | Git-backed shell scripts that write canonical IPFire config files directly and reload services via `ipfire` init scripts. |
| **High-availability / cluster failover** | Two-node HA prevents single point of failure | Complexity doubles: CARP/VRRP, config sync, shared state tables. N100 mini-PC is a single appliance. Git-based rebuild from repo is the HA strategy: rebuild in minutes, not seconds. | Fast rebuild from repo + documented manual failover procedure. Accept RTO of ~15 minutes rather than sub-second. |
| **Certificate authority (internal PKI)** | mTLS between internal services, internal HTTPS | CA lifecycle (rotation, revocation) is a separate discipline. Scope creep from firewall into PKI management. | Use Let's Encrypt for externally-facing services; self-signed for internal management endpoints. Defer internal PKI to a separate project. |
| **Intrusion deception / honeypots** | Detect lateral movement via fake credentials | Honeypot management is operationally complex; false positive risk on home/SOHO networks is high. Out of scope for v1 firewall. | IPS alert thresholds + network flow logging provide adequate lateral movement visibility for this network scale. |

---

## Feature Dependencies

```
[Zone NIC Mapping]
    └──required-by──> [Zone Segmentation Policy]
                           └──required-by──> [DHCP per Zone]
                           └──required-by──> [IDS/IPS Zone Selection]
                           └──required-by──> [OPT Zone Activation]

[Stateful Firewall + NAT]
    └──required-by──> [Port Forwarding (DNAT)]
    └──required-by──> [Source NAT (SNAT)]
    └──required-by──> [Anti-Lockout Policy]

[DNS Resolver (Unbound)]
    └──required-by──> [DNS-over-TLS Enforcement]
    └──required-by──> [DNSSEC Validation]
    └──required-by──> [Domain Blocklist (IPFire DBL)]
    └──required-by──> [DHCP-DNS Integration] (hostname from DHCP remark field)

[Remote Syslog (UDP 514)]
    └──required-by──> [Telemetry Pipeline]
                           └──required-by──> [Threat-Tracing Dashboard]

[IDS/IPS (Suricata)]
    └──required-by──> [IPS Alert Email / PDF Reports]
    └──required-by──> [IPS Alert Forwarding to Remote Syslog]
    └──enhances──> [Threat-Tracing Dashboard] (alert events in log stream)
    └──enhances──> [Domain Blocklist] (DBL feeds Suricata rule engine in CU200)

[Docker (Pakfire)]
    └──required-by──> [Telemetry Pipeline Containers]
    └──required-by──> [Threat-Tracing Dashboard Containers]

[Git Repo + Rebuild Scripts]
    └──required-by──> [Validation Suite] (scripts live in repo)
    └──required-by──> [Rollback Procedures] (documented in repo)
    └──enhances──> [Decision Log] (ADRs committed to repo)

[SSH Hardening]
    └──enhances──> [Anti-Lockout Policy] (key-only auth + IP whitelist)
    └──requires──> [SSH Brute-Force Protection] (fail2ban/Guardian)
```

### Dependency Notes

- **Zone NIC mapping must precede all zone-dependent features:** If interfaces are not persistently mapped to zones via MAC-based udev rules, zone policy, DHCP scopes, and IPS zone selection are all unreliable after reboots or kernel updates.
- **Remote syslog is prerequisite for telemetry pipeline:** IPFire sends logs via UDP syslog only (TCP not natively supported). The collector must listen on UDP 514 on the same network segment IPFire can reach.
- **Docker requires core firewall stability first:** Containers on the same host as the firewall share the kernel network stack. Deploying containers before the firewall ruleset is validated introduces noise into troubleshooting.
- **IPS rules conflict with management access:** The `emerging-policy.rules` Suricata category is known to block Linux package manager traffic, potentially blocking Pakfire updates. Enable IPS rule categories incrementally, one per day, while monitoring IPS logs.
- **DBL (CU200) requires Suricata and/or URL Filter enabled:** The domain blocklist feature feeds into two enforcement points — proxy-based URL Filter (requires Squid) and Suricata IPS. Since Squid is an anti-feature here, DBL value comes through the Suricata path only.

---

## MVP Definition

For this project, "MVP" means: the appliance is production-ready and the core value ("can be rebuilt from repo in minutes") is validated. It does not mean feature-complete.

### Launch With (v1 — Production-Ready Baseline)

- [ ] **All 6 NICs persistently mapped** — Zone assignments survive reboots; udev rules in repo. Foundation for everything else.
- [ ] **Stateful firewall, default-deny inbound, NAT/masquerade** — Base security posture. Validated by automated test.
- [ ] **Zone segmentation: GREEN/RED/ORANGE/BLUE + MGMT** — All physical ports assigned; inter-zone policies locked down.
- [ ] **DHCP server on GREEN (and optionally BLUE)** — Clients receive addresses, gateway, DNS, NTP.
- [ ] **DNS resolver: Unbound + DNSSEC + DNS-over-TLS** — Mandatory DNSSEC, DoT upstream configured and enforced.
- [ ] **NTP service** — Synchronized clocks; accurate log timestamps.
- [ ] **SSH hardened + brute-force protection** — Key-only auth, IP whitelist, fail2ban jail, 15-minute auto-disable.
- [ ] **IDS/IPS (Suricata) with auto-updating rules** — ET Community minimum; zone selection configured; monitor-only tuning period completed.
- [ ] **System hardening** — Unused services disabled, permissions locked, audit logging active.
- [ ] **Remote syslog forwarding to telemetry collector** — Firewall and IPS logs reaching collector container.
- [ ] **Telemetry pipeline (Loki + Grafana in Docker)** — Firewall drops and IPS alerts searchable and graphable.
- [ ] **Threat-tracing dashboard** — Source IP → alert → action visible end-to-end.
- [ ] **Full validation suite** — All capabilities tested by scripts; outputs pass/fail.
- [ ] **Git repo with rebuild scripts + rollback procedures** — Fresh install can be reproduced from repo. Rebuild tested.
- [ ] **Decision log** — All architectural choices recorded.

### Add After Validation (v1.x)

- [ ] **IPS alert emails + PDF reports** — Requires SMTP config; value is clear but not needed to validate core appliance. Trigger: IPS tuning period complete (false positive rate acceptable).
- [ ] **Domain blocklist (IPFire DBL)** — Currently beta in CU200. Trigger: DBL exits beta and stabilizes.
- [ ] **SNAT for additional WAN IPs** — Only relevant if ISP provides multiple IPs or a /29 block. Trigger: when needed.
- [ ] **Additional OPT zone policies** — Refined DMZ pinholes for specific services (e.g., a home NAS in ORANGE). Trigger: when services are deployed behind the firewall.
- [ ] **GeoIP dashboards** — IPS alert and firewall drop heatmaps by country. Trigger: telemetry pipeline stable.

### Future Consideration (v2+)

- [ ] **VPN server** — Separate project. Trigger: appliance validated, VPN use case emerges.
- [ ] **Internal PKI** — Deferred. Trigger: internal services requiring mTLS.
- [ ] **Off-box telemetry** — Moving the Loki/Grafana stack to a secondary host frees N100 resources. Trigger: N100 shows sustained high CPU under telemetry load.

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Stateful firewall + NAT | HIGH | LOW | P1 |
| Zone NIC mapping (persistent) | HIGH | MEDIUM | P1 |
| Zone segmentation policy | HIGH | LOW | P1 |
| DHCP server per zone | HIGH | LOW | P1 |
| DNS resolver (Unbound + DNSSEC + DoT) | HIGH | LOW | P1 |
| SSH hardening + brute-force protection | HIGH | LOW | P1 |
| IDS/IPS (Suricata) + auto-updates | HIGH | MEDIUM | P1 |
| Remote syslog forwarding | HIGH | LOW | P1 |
| Telemetry pipeline (Loki + Grafana) | HIGH | HIGH | P1 |
| Threat-tracing dashboard | HIGH | HIGH | P1 |
| Git repo + rebuild scripts | HIGH | MEDIUM | P1 |
| Validation suite | HIGH | HIGH | P1 |
| Rollback procedures | MEDIUM | MEDIUM | P1 |
| System hardening | HIGH | MEDIUM | P1 |
| IPS alert email + PDF reports | MEDIUM | LOW | P2 |
| Domain blocklist (IPFire DBL) | MEDIUM | LOW | P2 |
| Anti-lockout policy (explicit rule) | HIGH | LOW | P1 |
| Port forwarding (DNAT) | MEDIUM | LOW | P2 |
| Source NAT (SNAT) | LOW | LOW | P3 |
| OPT zone additional policies | MEDIUM | MEDIUM | P2 |
| Decision log | MEDIUM | LOW | P1 |
| GeoIP dashboards | LOW | MEDIUM | P3 |
| VPN server | LOW (v1) | HIGH | P3 |

---

## Competitor Feature Analysis

| Feature | Stock IPFire (fresh install) | pfSense/OPNsense | This Project |
|---------|------------------------------|------------------|--------------|
| Stateful firewall | Native, configured | Native, configured | Native, validated by script |
| NAT / masquerade | Native, default on | Native, default on | Native, documented |
| IDS/IPS | Suricata installed, NOT configured | Add-on or built-in, not auto-updating | Configured, zone-selected, auto-updating rulesets |
| DNS (Unbound + DNSSEC) | Enabled by default | Via add-on (Unbound) | Enabled + DoT enforced + DBL activated |
| DHCP | Configured via WUI | Configured via WUI | Configured, static leases in repo |
| Remote syslog | UDP 514 configurable | Configurable | Configured, feeding pipeline |
| Network telemetry pipeline | Not present | Via pfSense/OPNsense plugins (Netflow) | Loki + Grafana in Docker |
| Threat-tracing dashboard | Not present | Limited (Netflow graphs) | Custom Grafana dashboards |
| Git-based reproducibility | Not present | Not present | Core project deliverable |
| Automated validation suite | Not present | Not present | Full scripted test suite |
| Rollback procedures | Docs say "FIXME" | Partial documentation | Documented per change category |
| NIC-to-zone persistent mapping | Not documented | Partially via MAC rules | Explicit udev rules in repo |
| System hardening guide | Exists in wiki | Exists in docs | Applied + validated |

---

## Sources

- [IPFire Official Documentation](https://www.ipfire.org/docs/) — HIGH confidence
- [IPFire IPS Configuration](https://www.ipfire.org/docs/configuration/firewall/ips) — HIGH confidence
- [IPFire Suricata Rulesets](https://www.ipfire.org/docs/configuration/firewall/ips/rulesets) — HIGH confidence
- [IPFire DNS Server](https://www.ipfire.org/docs/configuration/network/dns-server) — HIGH confidence
- [IPFire DHCP Server](https://www.ipfire.org/docs/configuration/network/dhcp) — HIGH confidence
- [IPFire Zone Configuration](https://www.ipfire.org/docs/configuration/network/zoneconf) — HIGH confidence
- [IPFire Firewall Rules Reference](https://wiki.ipfire.org/configuration/firewall/rules) — HIGH confidence
- [IPFire NAT Reference](https://wiki.ipfire.org/configuration/firewall/nat) — HIGH confidence
- [IPFire Port Forwarding](https://www.ipfire.org/docs/configuration/firewall/rules/port-forwarding) — HIGH confidence
- [IPFire Security Hardening Guide](https://wiki.ipfire.org/optimization/start/security_hardening) — HIGH confidence
- [IPFire Core Update 199 Release Notes](https://www.ipfire.org/blog/ipfire-2-29-core-update-199-released) — HIGH confidence
- [IPFire Core Update 200 Release Notes](https://www.ipfire.org/blog/ipfire-2-29-core-update-200-released) — HIGH confidence
- [IPFire Log Settings](https://wiki.ipfire.org/configuration/logs/logsettings) — HIGH confidence
- [IPFire IPS Configuration Recommendations](https://www.ipfire.org/blog/ips-configuration-recommendations-for-ipfire-users) — HIGH confidence
- [IPFire DNS Configuration Recommendations](https://www.ipfire.org/blog/dns-configuration-recommendations-for-ipfire-users) — HIGH confidence
- [IPFire vs pfSense Comparison — Tolu Michael](https://tolumichael.com/ipfire-vs-pfsense/) — MEDIUM confidence
- [Best Hardware Firewalls for Home/SMB — Zenarmor](https://www.zenarmor.com/docs/network-security-tutorials/best-hardware-firewalls-for-home-and-small-business-networks) — MEDIUM confidence
- [Firewall Observability Best Practices — Homelab Guide](https://excalibursheath.com/guide/2025/09/07/homelab-security-automation-monitoring.html) — MEDIUM confidence
- [IPFire + Graylog community integration](https://forum.ipfire.org/viewtopic.php?t=18193) — MEDIUM confidence (community thread)

---

*Feature research for: IPFire-based hardened firewall appliance, Intel N100 6-NIC*
*Researched: 2026-03-21*
