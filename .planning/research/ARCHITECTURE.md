# Architecture Research

**Domain:** IPFire-based hardened firewall appliance with IDS and telemetry
**Researched:** 2026-03-21
**Confidence:** HIGH (zone model, NIC mapping, Suricata integration); MEDIUM (telemetry placement, Docker boundary)

---

## Standard Architecture

### System Overview

```
                        ┌─────────────────────────────────────────────────┐
                        │              INTERNET / ISP (RED)                │
                        │                  NIC 1 (red0)                   │
                        └────────────────────┬────────────────────────────┘
                                             │
                        ┌────────────────────▼────────────────────────────┐
                        │                 IPFire HOST                      │
                        │          Intel N100 — 6 NICs                    │
                        │                                                  │
                        │  ┌──────────────────────────────────────────┐   │
                        │  │           PACKET PROCESSING PIPELINE      │   │
                        │  │                                           │   │
                        │  │  [NIC] → [nfqueue] → [Suricata IPS]      │   │
                        │  │             ↓ (inline)                    │   │
                        │  │        [iptables / netfilter]             │   │
                        │  │             ↓                             │   │
                        │  │         [Routing]                         │   │
                        │  └──────────────────────────────────────────┘   │
                        │                                                  │
                        │  Native Services (Pakfire managed):              │
                        │  ┌───────────┐ ┌─────────┐ ┌───────────────┐   │
                        │  │  DHCP     │ │   DNS   │ │  NTP          │   │
                        │  │  (dnsmasq)│ │(unbound)│ │  (ntpd)       │   │
                        │  └───────────┘ └─────────┘ └───────────────┘   │
                        │  ┌───────────┐ ┌─────────┐ ┌───────────────┐   │
                        │  │  SSH      │ │  WUI    │ │  Suricata     │   │
                        │  │(sshd+f2b) │ │ (:444)  │ │  (IDS/IPS)    │   │
                        │  └───────────┘ └─────────┘ └───────────────┘   │
                        │                                                  │
                        │  Log files (native, on-box):                    │
                        │  /var/log/messages  (iptables, syslog)          │
                        │  /var/log/suricata/eve.json  (Suricata EVE)     │
                        └──┬──────────┬───────────┬──────────┬───────────┘
                           │          │           │          │
            ┌──────────────▼──┐  ┌───▼───────┐ ┌▼────────┐ ┌▼──────────┐
            │  GREEN (LAN)    │  │  BLUE     │ │ ORANGE  │ │  MGMT     │
            │  NIC 2 (green0) │  │  (Guest)  │ │  (DMZ)  │ │  (green0  │
            │  192.168.1.0/24 │  │  NIC 3    │ │  NIC 4  │ │  bridge / │
            │                 │  │  blue0    │ │ orange0 │ │  NIC 5)   │
            │  Trusted LAN    │  │  10.x/24  │ │ 172.x/24│ │  isolated │
            │  clients + srvr │  │  Wireless │ │ Pub-fcg │ │  access   │
            └─────────────────┘  └───────────┘ └─────────┘ └───────────┘
                           │
            ┌──────────────▼─────────────────────────────────────────────┐
            │         TELEMETRY HOST (Docker, separate machine or VM)     │
            │         On GREEN zone — firewall-controlled access          │
            │                                                             │
            │  ┌──────────┐  ┌────────┐  ┌────────┐  ┌──────────────┐  │
            │  │ Promtail │→ │  Loki  │  │Grafana │  │  Prometheus  │  │
            │  │(log ship)│  │ :3100  │  │ :3000  │  │  + node_exp  │  │
            │  └──────────┘  └────────┘  └────────┘  └──────────────┘  │
            └────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Implementation |
|-----------|----------------|----------------|
| IPFire kernel / netfilter | Packet filtering, NAT/masquerade, stateful tracking, zone enforcement | iptables (native, managed by IPFire WUI) |
| Suricata IPS | Inline deep-packet inspection; drop/alert before firewall pass | Native Pakfire package; nfqueue inline mode |
| dnsmasq / unbound | DHCP for GREEN/BLUE zones; recursive DNS resolver | Native IPFire service |
| ntpd | Network time — required for log correlation | Native IPFire service |
| sshd + fail2ban | Hardened SSH management; brute-force blocking | Native + Pakfire addon |
| IPFire WUI | Web management at :444 on GREEN; zone config, IPS rules, logs | Native lighttpd-based interface |
| udev rules | Persistent NIC-to-zone name binding by MAC address | /etc/udev/rules.d/30-persistent-network.rules |
| /var/log/messages | iptables kernel firewall logs (syslog format, FORWARDFW prefix) | Linux syslog, on-box |
| /var/log/suricata/eve.json | Suricata EVE JSON — all alert, flow, DNS, HTTP events | Suricata output module, on-box |
| Promtail (telemetry host) | Ship log files to Loki; parse EVE JSON labels | Docker container, off-box |
| Loki (telemetry host) | Label-indexed log storage; LogQL query engine | Docker container, off-box |
| Grafana (telemetry host) | Dashboard visualization, alerting, threat tracing | Docker container, off-box |
| Prometheus + node_exporter | System metrics: CPU, RAM, NIC throughput, connection counts | Docker container, off-box |

---

## Zone Model and NIC Mapping

### IPFire Zone Constraints (Authoritative)

IPFire supports exactly **four named zones**: RED, GREEN, BLUE, ORANGE. This is a hard limit in IPFire 2.x. There is no fifth zone, no "PURPLE", no custom zone names. Each zone has its own trust level and default inter-zone policy.

| Zone | Color | Trust Level | Default Inter-Zone Policy |
|------|-------|-------------|---------------------------|
| RED | External / WAN | Untrusted | Blocked inbound by default; NAT outbound from GREEN/BLUE |
| GREEN | Internal LAN | Fully trusted | Access to RED allowed; can reach ORANGE with rules |
| BLUE | Wireless / Guest | Semi-trusted | Isolated from GREEN by default; access to RED allowed |
| ORANGE | DMZ | Untrusted / public-facing | Blocked from GREEN by default; reachable from RED via rules |

### 6-NIC Mapping Strategy

With 6 physical NICs and only 4 named zones, two NICs must either be assigned to a zone via **bridge mode** (same zone, IPFire acts as switch) or left unassigned. The recommended mapping:

```
NIC 1  →  RED    (red0)      — WAN / ISP uplink
NIC 2  →  GREEN  (green0)    — Primary trusted LAN (clients, servers, telemetry host)
NIC 3  →  BLUE   (blue0)     — Wireless / guest network (connect to AP uplink)
NIC 4  →  ORANGE (orange0)   — DMZ (public-facing services if needed; default unused)
NIC 5  →  GREEN  (bridge)    — Second trusted LAN port (bridge to green0 in Bridge mode)
NIC 6  →  GREEN  (bridge)    — Third trusted LAN port (bridge to green0 in Bridge mode)
       OR
NIC 5  →  Unassigned         — Reserve for dedicated management VLAN (future)
NIC 6  →  Unassigned         — Reserve for second WAN / failover (future)
```

Decision rationale: GREEN bridge mode is the simplest valid use of extra NICs within IPFire's constraints. Assigning NICs 5-6 to GREEN via Bridge mode gives additional physical LAN ports without VLAN complexity. ORANGE is provisioned but can remain empty until needed.

**Anti-lockout rule:** GREEN NIC (NIC 2) must always be the dedicated management NIC. Never reconfigure NIC 2 without a local console fallback plan.

### Persistent NIC Naming

IPFire stores NIC assignments in `/var/ipfire/ethernet/settings`. The underlying device names are stabilized by udev rules at `/etc/udev/rules.d/30-persistent-network.rules`, which bind zone interface names (green0, red0, blue0, orange0) to NIC MAC addresses.

Without persistent naming, kernel init order can scramble NIC-to-zone assignments across reboots on multi-NIC hosts. This is a critical initialization step and must be done before any zone configuration.

```
# Example udev rule (modern ATTR syntax)
ACTION=="add", SUBSYSTEM=="net", ATTR{type}=="1", ATTR{address}=="aa:bb:cc:dd:ee:01", NAME="red0"
ACTION=="add", SUBSYSTEM=="net", ATTR{type}=="1", ATTR{address}=="aa:bb:cc:dd:ee:02", NAME="green0"
ACTION=="add", SUBSYSTEM=="net", ATTR{type}=="1", ATTR{address}=="aa:bb:cc:dd:ee:03", NAME="blue0"
ACTION=="add", SUBSYSTEM=="net", ATTR{type}=="1", ATTR{address}=="aa:bb:cc:dd:ee:04", NAME="orange0"
```

---

## Native vs Docker Service Boundaries

### The IPFire Team's Official Position on Docker

**Docker is explicitly rejected by IPFire developers** (HIGH confidence — confirmed by lead developer statement in IPFire community forums). Reasons:

1. Container kernel sharing with the host is a security risk on a hardened firewall OS
2. Docker's NAT model conflicts with IPFire's zone-based network isolation
3. IPFire's sealed kernel hardening is incompatible with Docker's user namespace requirements
4. Container breakouts could compromise the entire firewall host

**The IPFire team's recommendation:** Run Docker services on a dedicated host in the GREEN (or ORANGE) zone, not on the IPFire box itself.

### Service Boundary Decision Table

| Service | Where | Why |
|---------|-------|-----|
| Firewall / NAT / iptables | Native (IPFire host) | Core packet path; must not depend on container runtime |
| Suricata IPS | Native (IPFire host, Pakfire) | Inline in packet path; nfqueue integration requires kernel access |
| DHCP (dnsmasq) | Native (IPFire host) | Core infrastructure; must function before Docker host has IP |
| DNS (unbound) | Native (IPFire host) | Core infrastructure; must function at boot |
| NTP | Native (IPFire host) | Needed for log timestamp correlation |
| SSH | Native (IPFire host) | Management access independent of other services |
| IPFire WUI | Native (IPFire host) | Zone/firewall management |
| Promtail | Docker (telemetry host on GREEN) | Log shipping agent; reads from IPFire via syslog or file share |
| Loki | Docker (telemetry host on GREEN) | Log storage; fine in container, no packet path involvement |
| Grafana | Docker (telemetry host on GREEN) | Dashboard only; no firewall path involvement |
| Prometheus | Docker (telemetry host on GREEN) | Metrics collection; scrapes node_exporter and remote endpoints |
| node_exporter | Docker or native (IPFire host) | System metrics; low-risk native install acceptable on IPFire |
| Reverse proxy (for telemetry) | Docker (telemetry host on GREEN) | TLS termination for dashboard access |

**Practical constraint:** If no separate physical host is available in the short term, the telemetry stack can temporarily run on the IPFire box using a carefully contained installation (non-Docker, native binaries). The architecture goal is off-box, but on-box as a transitional state is acceptable if resource-monitored.

---

## Log Flow Architecture

### Log Sources

| Source | Log Format | Location | What It Contains |
|--------|-----------|----------|-----------------|
| iptables / netfilter | Syslog (FORWARDFW prefix) | /var/log/messages | Dropped/accepted packets: IN/OUT interface, SRC/DST IP, protocol, ports, MAC |
| Suricata IDS/IPS | EVE JSON | /var/log/suricata/eve.json | Alerts, flows, DNS queries, HTTP, anomalies — full structured event stream |
| Suricata | Plain text | /var/log/suricata/suricata.log | Engine start/stop, errors — not alert data |
| IPFire syslog | Syslog | /var/log/messages | System events, daemon messages |
| SSH / fail2ban | Syslog | /var/log/messages | Auth attempts, bans |

### Log Delivery Paths

Two patterns are available; this project uses Pattern A for Suricata (EVE fidelity) and Pattern B for syslog:

**Pattern A: File-read shipping (recommended for EVE JSON)**
```
Suricata → /var/log/suricata/eve.json
                  ↓
           Promtail (on telemetry host, reads via NFS mount or direct if on-box)
                  ↓
           Loki (label-indexed storage)
                  ↓
           Grafana (LogQL queries, dashboards, alerts)
```

**Pattern B: UDP syslog forwarding (for iptables / system logs)**
```
IPFire syslog daemon (/var/log/messages)
        ↓  (UDP only — TCP not currently supported by IPFire's syslog daemon)
Remote syslog receiver on telemetry host
        ↓
Promtail (scrapes received syslog)
        ↓
Loki
        ↓
Grafana
```

**Critical note on EVE JSON and syslog:** IPFire's Suricata only writes meta-information (start/stop events) to syslog — not EVE alerts. EVE alerts only appear in `/var/log/suricata/eve.json`. Pattern A (file read) is mandatory for full IDS telemetry.

### Log Volume Management

On an N100 with a home/SOHO network:
- EVE JSON can generate 10-100 MB/day depending on traffic and ruleset scope
- iptables logs are lower volume but continuous
- File transfer and TLS session logging in Suricata should be selectively disabled to control volume
- Logrotate on IPFire handles daily rotation with compression; 1 year retention by default

---

## Data Paths

### Packet Ingress Path (inbound, IPS mode)

```
[External host] → [NIC red0 / WAN]
    → [nfqueue] → [Suricata IPS inline inspection]
         ↓ (pass or DROP)
    → [iptables PREROUTING] → [Routing decision]
         ↓
    → [iptables FORWARD] → [zone policy rules]
         ↓ (if allowed)
    → [NIC green0 / destination zone]
    → [Internal host]
```

Suricata sits **before** the firewall engine in IPFire's inline IPS mode. A malicious packet is dropped by Suricata before iptables ever processes it.

### Management Access Path

```
[Admin workstation] → [NIC green0, port 444 HTTPS]
    → [IPFire WUI (lighttpd)]
    → [Zone config, firewall rules, IPS config, log viewer]
```

SSH path:
```
[Admin workstation] → [NIC green0, port 22 (or custom)]
    → [sshd] (fail2ban monitors auth log)
```

### Telemetry Data Path

```
[IPFire /var/log/suricata/eve.json]  ──── (NFS mount or SSH tunnel) ────►
[IPFire /var/log/messages]           ──── (UDP syslog, port 514)     ────►
                                                                          │
                                                         [Telemetry host on GREEN]
                                                         Promtail → Loki → Grafana
```

Prometheus node_exporter path:
```
[IPFire host — node_exporter :9100]  ◄── scrape (HTTP, Prometheus pull model) ──
                                                         [Prometheus on telemetry host]
                                                                ↓
                                                         Grafana (metrics dashboards)
```

### Suricata Zone Coverage Decision

Suricata requires selecting which zones to inspect. Performance consideration: inspecting ALL interfaces doubles processing load. Recommended targeting:

| Zone | Inspect? | Reason |
|------|----------|--------|
| RED (red0) | Yes | All external traffic; primary threat surface |
| GREEN (green0) | Yes | Detect lateral movement and exfiltration from LAN |
| BLUE (blue0) | Optional | Guest network; enable if wireless clients are untrusted |
| ORANGE (orange0) | Yes if populated | DMZ servers; detect inbound exploitation attempts |

---

## Architectural Patterns

### Pattern 1: Zone-First Design

**What:** Define all zone assignments and firewall policies before configuring any services. NIC-to-zone binding happens at the OS level (udev); zone policies are set in IPFire WUI.

**When to use:** Always — this is the foundational step. Changing zones after services are configured risks losing management access (anti-lockout failure).

**Trade-offs:** Requires knowing final NIC-to-zone assignments upfront. Getting this wrong early causes rework.

**Sequence:**
```
1. Identify physical NIC MAC addresses (ip link show / ethtool)
2. Write udev rules mapping MACs to zone interface names
3. Update /var/ipfire/ethernet/settings
4. Reboot and verify zone assignments
5. THEN configure services on top
```

### Pattern 2: Native-First, Docker-After

**What:** All core firewall services (iptables, Suricata, DHCP, DNS) are operational natively before any Docker infrastructure is introduced. Docker services are additive, not dependencies.

**When to use:** Always on an IPFire host. The firewall must function completely without the telemetry stack.

**Trade-offs:** Requires two stages of deployment (native core, then telemetry). Reduces operational risk — losing the telemetry host doesn't affect network operation.

### Pattern 3: Incremental Log Ingest

**What:** Add log sources to the telemetry pipeline one at a time, validating data quality before adding the next source. Start with Suricata EVE JSON (highest value), then iptables syslog, then system logs.

**When to use:** N100 has limited RAM; telemetry stack should be proven lightweight before ingesting all sources simultaneously. Prevents resource exhaustion during initial setup.

**Trade-offs:** Slightly longer time to full observability. Avoids scenario where all logs flood Loki on day one and overwhelm the stack.

---

## Recommended Project Structure (Repo Layout)

```
/
├── docs/                         # Architecture decisions, runbooks
│   ├── decisions/                # ADR (Architecture Decision Records)
│   └── zones.md                  # Zone definitions and NIC map
│
├── firewall/                     # Native IPFire configuration
│   ├── udev/                     # NIC persistence rules
│   │   └── 30-persistent-network.rules
│   ├── zones/                    # Zone settings exports
│   │   └── ethernet_settings
│   ├── firewall-rules/           # Exported IPFire firewall rule configs
│   └── suricata/                 # Suricata configuration overlays
│       ├── suricata.yaml         # EVE JSON output config
│       └── rules/                # Custom local rules
│
├── telemetry/                    # Off-box Docker telemetry stack
│   ├── docker-compose.yml        # Loki + Promtail + Grafana + Prometheus
│   ├── loki/
│   │   └── loki-config.yaml
│   ├── promtail/
│   │   └── promtail-config.yaml  # Scrape eve.json + syslog
│   ├── grafana/
│   │   ├── provisioning/         # Dashboard and datasource provisioning
│   │   └── dashboards/           # Pre-built dashboard JSON exports
│   └── prometheus/
│       └── prometheus.yml        # Scrape configs (node_exporter, etc.)
│
├── scripts/                      # Automation and validation
│   ├── validate-nics.sh          # Verify NIC-to-zone mapping
│   ├── validate-firewall.sh      # Test connectivity matrix
│   ├── deploy-telemetry.sh       # Bootstrap Docker stack
│   └── rebuild.sh                # Full rebuild from scratch
│
└── validation/                   # Test artifacts
    └── test-results/             # Timestamped validation outputs
```

---

## Anti-Patterns

### Anti-Pattern 1: Running Docker Directly on IPFire

**What people do:** Install Docker on the IPFire host to co-locate the telemetry stack.

**Why it's wrong:** IPFire developers explicitly reject Docker due to kernel sharing risks, NAT conflicts with zone isolation, and incompatibility with sealed kernel hardening. Docker's iptables manipulation can corrupt IPFire's firewall rules silently.

**Do this instead:** Run Docker on a dedicated host in the GREEN zone. If hardware is limited, use native binaries (non-Docker Promtail/Loki) or accept on-box native install as a transitional state.

### Anti-Pattern 2: Configuring Services Before Verifying NIC Persistence

**What people do:** Configure DHCP, DNS, and firewall rules immediately after install without first verifying that NIC-to-zone assignments survive reboot.

**Why it's wrong:** On a 6-NIC host, boot order can scramble interface names. After a reboot, green0 might become the WAN interface, exposing the trusted LAN to the internet.

**Do this instead:** Complete a full reboot cycle and verify all zone assignments before any service configuration. Test with: `ip link show && cat /var/ipfire/ethernet/settings`.

### Anti-Pattern 3: Enabling IPS on All Zones Without Ruleset Tuning

**What people do:** Enable Suricata on all 6 interfaces with the largest available ruleset immediately.

**Why it's wrong:** IPS is CPU-and-memory-intensive. On an N100, inspecting all zones with an untuned ruleset can saturate the processor and degrade throughput. On a home network, many enterprise rules generate false positives that mask real alerts.

**Do this instead:** Enable Suricata on RED only initially. Validate rule performance and alert quality before expanding to GREEN. Tune (suppress/disable) high-volume false-positive rule categories before full deployment.

### Anti-Pattern 4: Relying on UDP Syslog for Suricata EVE Alerts

**What people do:** Configure Suricata to forward EVE JSON to syslog, then ship syslog to Loki.

**Why it's wrong:** IPFire's Suricata only sends meta-information (engine start/stop) to syslog — not EVE alert data. EVE JSON stays in `/var/log/suricata/eve.json` regardless of syslog config. All alert data is silently lost.

**Do this instead:** Use Promtail to read `/var/log/suricata/eve.json` directly via file mount. Never rely on syslog for EVE data on IPFire.

### Anti-Pattern 5: Using eth0-Style Interface Names

**What people do:** Reference network interfaces by kernel-assigned names (eth0, eth1, ...) in scripts and configs.

**Why it's wrong:** Kernel interface naming is non-deterministic on multi-NIC hosts. After any hardware change or kernel update, eth0 may point to a different physical port.

**Do this instead:** Always reference interfaces by udev-assigned zone names (green0, red0, blue0, orange0) or by MAC address in udev rules.

---

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| ISP / WAN | DHCP client on red0 | Typical home/SOHO; static IP assignment also supported |
| Suricata rule feeds | Pakfire-managed auto-update (daily/weekly) | Abuse.ch, ET rules, etc.; managed via IPFire WUI |
| NTP upstream | ntpd polls pool.ntp.org | Required for log timestamp accuracy across all components |
| Remote syslog receiver | UDP port 514 from IPFire syslog daemon | TCP not supported in current IPFire syslog daemon |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| IPFire host ↔ Telemetry host | UDP syslog (:514) + HTTP (node_exporter :9100) | Firewall rule must allow telemetry host IP to reach IPFire :9100 |
| Telemetry host → eve.json | NFS mount or rsync (pull) | If off-box: mount /var/log/suricata from IPFire via NFS over GREEN; restrict to telemetry host IP |
| Promtail → Loki | HTTP POST :3100 (on telemetry host, localhost) | If same Docker Compose network: service discovery by container name |
| Grafana → Loki | HTTP :3100 | Data source configured in Grafana provisioning |
| Grafana → Prometheus | HTTP :9090 | Data source configured in Grafana provisioning |
| Admin workstation → IPFire WUI | HTTPS :444 via GREEN | Must remain accessible; this is the anti-lockout path |
| Admin workstation → Grafana | HTTPS :3000 (or via reverse proxy) | Port should be restricted to management VLAN / specific IP |

---

## Build Order (Dependencies)

The architecture has hard dependencies that dictate phase sequencing:

```
Phase 1: Platform + NIC Persistence
    ↳ Required before: everything else
    ↳ Deliverable: All 6 NICs mapped, assignments survive reboot

Phase 2: Zone Policies + Core Services
    ↳ Requires: Phase 1 (stable NIC names)
    ↳ Required before: IDS (needs correct interfaces), Telemetry (needs routing)
    ↳ Deliverable: DHCP/DNS/NTP working, default-deny inbound, NAT masquerade

Phase 3: SSH Hardening + Anti-lockout
    ↳ Requires: Phase 2 (GREEN zone functional)
    ↳ Can run in parallel with Phase 4 prep
    ↳ Deliverable: Hardened management access, fail2ban active

Phase 4: Suricata IDS/IPS
    ↳ Requires: Phase 2 (zone interfaces exist and are stable)
    ↳ Required before: Telemetry (IDS alerts are primary telemetry source)
    ↳ Deliverable: Inline IPS on RED, EVE JSON emitting alerts

Phase 5: Telemetry Pipeline
    ↳ Requires: Phase 4 (eve.json populated), Phase 2 (routing to telemetry host)
    ↳ Deliverable: Promtail → Loki → Grafana, threat dashboard visible

Phase 6: System Hardening + Validation
    ↳ Requires: All prior phases stable
    ↳ Deliverable: Audit log, unused services off, full test suite passing

Phase 7: Reproducibility
    ↳ Requires: All configs known and stable
    ↳ Deliverable: Rebuild-from-repo scripts, rollback procedures
```

---

## Scaling Considerations

This is a home/SOHO appliance — scaling concerns are about resource saturation, not horizontal scale.

| Concern | N100 baseline | If saturated |
|---------|---------------|--------------|
| IPS throughput | ~130 Mbps (mini appliance benchmark) with full ruleset; likely higher with tuned rules | Reduce monitored zones; disable expensive rule categories (TLS, file detection) |
| Telemetry storage | eve.json + syslog: 30-100 MB/day at SOHO scale | Loki retention policy (7-30 days); disable file/TLS logging in Suricata |
| RAM (Suricata) | Rules compiled at startup; larger rulesets use more RAM; 16 GB gives headroom | Reduce enabled rule categories; prioritize IP reputation rules over deep-inspect |
| RAM (telemetry on-box) | Loki + Grafana + Promtail: ~300-500 MB at minimal config | Move telemetry off-box; use remote Loki instance |
| CPU under load | N100 handles 1-2.5 Gbps routing without IPS; IPS adds meaningful load | Enable only RED-facing IPS; defer GREEN inspection |

---

## Sources

- [IPFire Zone Configuration](https://www.ipfire.org/docs/configuration/network/zoneconf) — zone modes, NIC assignment, VLAN limits
- [IPFire Step 5: Network Setup](https://www.ipfire.org/docs/installation/step5) — zone assignment during installation
- [IPFire IPS Documentation](https://www.ipfire.org/docs/configuration/firewall/ips) — Suricata inline mode, zone selection
- [IPFire IPS Performance Considerations](https://www.ipfire.org/docs/configuration/firewall/ips/performance-considerations) — CPU/memory tradeoffs
- [IPFire Suricata 7 Roadmap](https://www.ipfire.org/docs/roadmap/suricata7) — HTTP/2 support, performance improvements
- [IPFire Log Settings](https://www.ipfire.org/docs/configuration/logs/logsettings) — remote syslog (UDP only), retention
- [IPFire Firewall Logs](https://www.ipfire.org/docs/configuration/logs/firewall) — log fields and format
- [IPFire Docker Feature Request — developer rejection](https://community.ipfire.org/t/feature-request-docker-support/3527) — official position on Docker
- [IPFire IPS Syslog limitation](https://community.ipfire.org/t/ips-suricata-does-not-log-into-syslog/9302) — EVE JSON not in syslog
- [Suricata EVE JSON Output](https://docs.suricata.io/en/latest/output/eve/eve-json-output.html) — eve.json format, output types
- [Suricata-Loki-Grafana homelab reference](https://github.com/justynlarry/suricata-loki-grafana) — deployment pattern
- [Grafana Suricata EVE JSON dashboard](https://grafana.com/grafana/dashboards/22247-suricata-logs-json/) — dashboard reference
- [N100 IPFire hardware community thread](https://community.ipfire.org/t/cwwk-n100-n150-is-a-good-option/13811) — N100 zone/NIC configuration in practice

---

*Architecture research for: IPFire hardened firewall appliance with 6 NICs, Suricata IDS, telemetry stack*
*Researched: 2026-03-21*
