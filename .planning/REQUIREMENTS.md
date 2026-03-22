# Requirements: Firewall Appliance

**Defined:** 2026-03-21
**Core Value:** A secure, observable network perimeter that can be rebuilt from scratch in minutes

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Platform Foundation

- [ ] **PLAT-01**: All 6 NICs persistently mapped to IPFire zones via MAC-based udev rules, surviving reboots and kernel updates
- [ ] **PLAT-02**: Anti-lockout rules in firewall.local ensuring management access (SSH + WUI) is preserved during all firewall changes
- [ ] **PLAT-03**: Git repository initialized with project structure (/configs, /scripts, /services, /docs, /validation, /rollback, /manifests, /decision-log)
- [ ] **PLAT-04**: IPFire hostname, timezone, and base system updates applied and documented
- [ ] **PLAT-05**: Backup strategy defined — config export + backup include list for Core Update survival

### Firewall & NAT

- [ ] **FW-01**: Stateful firewall with default-deny inbound on all zones
- [ ] **FW-02**: NAT/IP masquerade on RED (WAN) for all internal zones
- [ ] **FW-03**: Zone segmentation policies: GREEN/RED/ORANGE/BLUE with explicit inter-zone rules
- [ ] **FW-04**: Port forwarding (DNAT) capability configured and validated
- [ ] **FW-05**: Firewall logging enabled for all drop/reject actions
- [ ] **FW-06**: Firewall rules persist across reboot
- [ ] **FW-07**: Anti-lockout: MGMT allow rules applied FIRST before any deny rules during changes

### Core Services

- [ ] **SVC-01**: DHCP server on GREEN zone with correct gateway, DNS, and NTP options
- [ ] **SVC-02**: DHCP static leases capability for known hosts
- [ ] **SVC-03**: DNS resolver via Unbound with mandatory DNSSEC validation
- [ ] **SVC-04**: DNS-over-TLS enforcement with configured upstream resolvers (Cloudflare/Quad9)
- [ ] **SVC-05**: NTP service synchronized to upstream pools and serving clients
- [ ] **SVC-06**: All core services persist and auto-start after reboot

### SSH & Management Security

- [ ] **SSH-01**: SSH configured with key-only authentication (password auth disabled)
- [ ] **SSH-02**: SSH access restricted to management IP/subnet whitelist
- [ ] **SSH-03**: Guardian installed via Pakfire for SSH brute-force protection
- [ ] **SSH-04**: IPFire WUI access restricted to GREEN/management subnet only
- [ ] **SSH-05**: SSH 15-minute expiry feature documented and operational

### IDS/IPS (Suricata)

- [ ] **IDS-01**: Suricata enabled with ET Community ruleset at minimum
- [ ] **IDS-02**: IPS zone selection configured (monitor RED + GREEN traffic)
- [ ] **IDS-03**: Automatic rule updates enabled (daily)
- [ ] **IDS-04**: Monitor-only mode validated before enabling blocking
- [ ] **IDS-05**: Memory cap tuned for N100 single-channel RAM constraints
- [ ] **IDS-06**: EVE JSON logging active at /var/log/suricata/eve.json
- [ ] **IDS-07**: Rule categories enabled incrementally (not all at once) to prevent self-lockout
- [ ] **IDS-08**: Post-Core-Update validation script checks suricata.yaml integrity

### System Hardening

- [ ] **HARD-01**: Unused services identified and disabled
- [ ] **HARD-02**: File permissions locked down per IPFire hardening guide
- [ ] **HARD-03**: Audit logging enabled for configuration changes
- [ ] **HARD-04**: Kernel parameters hardened (sysctl: disable IP source routing, ICMP redirects, etc.)
- [ ] **HARD-05**: IPFire WUI HTTPS certificate verified and documented

### Telemetry Pipeline (Off-Box)

- [ ] **TEL-01**: Remote syslog forwarding configured (UDP 514) for firewall logs
- [ ] **TEL-02**: IPS alert syslog forwarding configured (CU198+ feature)
- [ ] **TEL-03**: Off-box telemetry host provisioned with Docker Compose
- [ ] **TEL-04**: Grafana Alloy collector receiving syslog + reading EVE JSON
- [ ] **TEL-05**: Loki ingesting parsed firewall and IDS logs
- [ ] **TEL-06**: Grafana dashboards displaying firewall drops and IDS alerts
- [ ] **TEL-07**: Phased ingest: firewall logs first, then IDS, then auth/DHCP/DNS
- [ ] **TEL-08**: Log retention policy defined and configured

### Threat-Tracing Dashboard

- [ ] **DASH-01**: End-to-end threat trace: source IP → IDS alert → firewall action visible in single pane
- [ ] **DASH-02**: Time-series visualization of firewall drop events
- [ ] **DASH-03**: IPS alert severity breakdown dashboard
- [ ] **DASH-04**: Top blocked IPs / top triggered rules views

### Reproducibility

- [ ] **REPO-01**: All IPFire configs exported to /configs in git repo
- [ ] **REPO-02**: Rebuild script that restores a fresh IPFire install from repo
- [ ] **REPO-03**: Pakfire add-on manifest (list of installed packages)
- [ ] **REPO-04**: Full file manifest with sizes for drift detection
- [ ] **REPO-05**: Rollback procedures documented per change category (firewall, IDS, DNS, DHCP, zone)
- [ ] **REPO-06**: Decision log initialized with all architectural choices from project setup

### Validation

- [ ] **VAL-01**: Interface status validation (all 6 NICs up, correct zone assignment)
- [ ] **VAL-02**: Routing validation (GREEN can reach RED, inter-zone isolation verified)
- [ ] **VAL-03**: Firewall rule validation (default deny confirmed, allowed traffic passes)
- [ ] **VAL-04**: NAT validation (internal hosts reach internet, external sees WAN IP)
- [ ] **VAL-05**: DHCP validation (clients receive correct IP, gateway, DNS, NTP)
- [ ] **VAL-06**: DNS validation (resolution works, DNSSEC validates, DoT active)
- [ ] **VAL-07**: IDS validation (test signature triggers alert)
- [ ] **VAL-08**: Reboot persistence (all configs survive clean reboot)
- [ ] **VAL-09**: Service health checks (all services running post-boot)
- [ ] **VAL-10**: Telemetry validation (logs appearing in Grafana within 60 seconds)
- [ ] **VAL-11**: Full acceptance checklist script (runs all above, outputs pass/fail)

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Enhanced Security

- **SEC2-01**: IPS alert email and PDF reports (CU200 native, requires SMTP config)
- **SEC2-02**: IPFire Domain Blocklist (DBL) activation (currently beta in CU200)
- **SEC2-03**: GeoIP-based dashboard overlays for threat visualization

### Extended Network

- **NET2-01**: Source NAT (SNAT) for multi-IP WAN scenarios
- **NET2-02**: Additional OPT zone policies for specific DMZ services
- **NET2-03**: Port forwarding rules for specific hosted services

### Advanced Observability

- **OBS2-01**: collectd metrics export to Prometheus via collectd_exporter
- **OBS2-02**: System resource dashboards (CPU, RAM, disk, network throughput)
- **OBS2-03**: DHCP/DNS query logging and analytics

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| VPN server (IPsec/OpenVPN/WireGuard) | Separate project — adds key management complexity |
| WiFi AP management | Dedicated APs handle their own management |
| Web filtering / Squid proxy | Adds TLS MITM complexity; DNS-layer blocking sufficient |
| Full ELK/OpenSearch on-box | Too resource-heavy for N100; Loki+Grafana is 5-10x lighter |
| AI/ML threat detection | N100 not dimensioned for real-time ML inference |
| Docker on IPFire host | Officially rejected by IPFire developers — bypasses zone policies |
| High-availability clustering | Git-based rebuild is the HA strategy (15 min RTO) |
| Internal PKI / Certificate Authority | Separate discipline; defer to separate project |
| Honeypots / deception | Operationally complex; IPS provides adequate detection at SOHO scale |
| GUI tools beyond IPFire WUI | External tools can corrupt IPFire config state |
| Mail server/relay | Not a firewall function |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| PLAT-01 | — | Pending |
| PLAT-02 | — | Pending |
| PLAT-03 | — | Pending |
| PLAT-04 | — | Pending |
| PLAT-05 | — | Pending |
| FW-01 | — | Pending |
| FW-02 | — | Pending |
| FW-03 | — | Pending |
| FW-04 | — | Pending |
| FW-05 | — | Pending |
| FW-06 | — | Pending |
| FW-07 | — | Pending |
| SVC-01 | — | Pending |
| SVC-02 | — | Pending |
| SVC-03 | — | Pending |
| SVC-04 | — | Pending |
| SVC-05 | — | Pending |
| SVC-06 | — | Pending |
| SSH-01 | — | Pending |
| SSH-02 | — | Pending |
| SSH-03 | — | Pending |
| SSH-04 | — | Pending |
| SSH-05 | — | Pending |
| IDS-01 | — | Pending |
| IDS-02 | — | Pending |
| IDS-03 | — | Pending |
| IDS-04 | — | Pending |
| IDS-05 | — | Pending |
| IDS-06 | — | Pending |
| IDS-07 | — | Pending |
| IDS-08 | — | Pending |
| HARD-01 | — | Pending |
| HARD-02 | — | Pending |
| HARD-03 | — | Pending |
| HARD-04 | — | Pending |
| HARD-05 | — | Pending |
| TEL-01 | — | Pending |
| TEL-02 | — | Pending |
| TEL-03 | — | Pending |
| TEL-04 | — | Pending |
| TEL-05 | — | Pending |
| TEL-06 | — | Pending |
| TEL-07 | — | Pending |
| TEL-08 | — | Pending |
| DASH-01 | — | Pending |
| DASH-02 | — | Pending |
| DASH-03 | — | Pending |
| DASH-04 | — | Pending |
| REPO-01 | — | Pending |
| REPO-02 | — | Pending |
| REPO-03 | — | Pending |
| REPO-04 | — | Pending |
| REPO-05 | — | Pending |
| REPO-06 | — | Pending |
| VAL-01 | — | Pending |
| VAL-02 | — | Pending |
| VAL-03 | — | Pending |
| VAL-04 | — | Pending |
| VAL-05 | — | Pending |
| VAL-06 | — | Pending |
| VAL-07 | — | Pending |
| VAL-08 | — | Pending |
| VAL-09 | — | Pending |
| VAL-10 | — | Pending |
| VAL-11 | — | Pending |

**Coverage:**
- v1 requirements: 56 total
- Mapped to phases: 0
- Unmapped: 56 ⚠️

---
*Requirements defined: 2026-03-21*
*Last updated: 2026-03-21 after initial definition*
