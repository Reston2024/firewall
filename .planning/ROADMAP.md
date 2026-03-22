# Roadmap: Firewall Appliance

## Overview

Seven phases build a hardened, reproducible IPFire firewall appliance from the hardware up. Phase order is dictated by hard technical dependencies: NIC persistence before any zone config, core services before IPS, IPS before telemetry (EVE JSON is the pipeline's primary input), and hardening/reproducibility after all services are stable. Each phase delivers a coherent, independently verifiable capability. The project culminates in a git repo that can rebuild the appliance from scratch in under 15 minutes.

## Phases

- [ ] **Phase 1: Platform Foundation and Firewall** - All 6 NICs persistently mapped, anti-lockout in place, stateful firewall with NAT and zone policies operational
- [ ] **Phase 2: Core Network Services** - DHCP, DNS with DNSSEC and DoT, and NTP serving all zones
- [ ] **Phase 3: SSH Hardening and Management Security** - Key-only SSH, IP allowlist, Guardian brute-force protection, WUI access locked down
- [ ] **Phase 4: Suricata IDS/IPS** - IPS running in monitor-then-active mode, EVE JSON confirming alert output, N100-tuned memcap
- [ ] **Phase 5: Telemetry Pipeline and Dashboards** - Off-box Docker stack receiving logs, Loki storing data, Grafana dashboards showing firewall drops and IDS alerts
- [ ] **Phase 6: System Hardening and Validation Suite** - Unused services disabled, hardening applied, full scripted validation suite passing on clean reboot
- [ ] **Phase 7: Reproducibility and Disaster Recovery** - All configs in git, rebuild script verified on fresh IPFire install, rollback procedures and decision log complete

## Phase Details

### Phase 1: Platform Foundation and Firewall
**Goal**: All 6 NICs are permanently anchored to their correct IPFire zones and survive any reboot or kernel update, with a stateful firewall enforcing default-deny and NAT from day one
**Depends on**: Nothing (first phase)
**Requirements**: PLAT-01, PLAT-02, PLAT-03, PLAT-04, PLAT-05, FW-01, FW-02, FW-03, FW-04, FW-05, FW-06, FW-07
**Success Criteria** (what must be TRUE):
  1. Running `ip link show` lists all 6 NICs with their correct zone names (green0, red0, blue0, orange0, and bridge members) and assignments survive a clean reboot
  2. The WUI and SSH remain accessible from the management host after any firewall rule change, because `firewall.local` management allow rules load before any deny rules
  3. A host on GREEN can reach the internet (NAT/masquerade on RED is active) and cannot reach a host on ORANGE without an explicit allow rule (zone isolation enforced)
  4. Dropped packets from blocked inbound traffic appear in `/var/log/messages` firewall log entries (drop logging active)
  5. The git repo exists at the documented path with the full directory structure (/configs, /scripts, /services, /docs, /validation, /rollback, /manifests, /decision-log) and a backup include list is committed
**Plans**: 4 plans

Plans:
- [x] 01-01-PLAN.md — Repository structure, NIC map template, and validation scripts
- [ ] 01-02-PLAN.md — udev NIC persistence rules, ethernet/settings template, firewall.local, backup include list
- [ ] 01-03-PLAN.md — Zone policy runbook and firewall validation script
- [ ] 01-04-PLAN.md — Human deployment checkpoint: NIC identification, hardware deploy, reboot persistence test, acceptance verification

### Phase 2: Core Network Services
**Goal**: DHCP, DNS, and NTP are fully configured and serving all internal zones, with DNSSEC validation and DNS-over-TLS to upstream resolvers enforced from the start
**Depends on**: Phase 1
**Requirements**: SVC-01, SVC-02, SVC-03, SVC-04, SVC-05, SVC-06
**Success Criteria** (what must be TRUE):
  1. A new client on GREEN receives a correct IP address, default gateway, DNS server, and NTP server via DHCP, and known hosts receive their static lease addresses
  2. DNS resolution works from an internal client, DNSSEC validation is active (`dig +dnssec example.com` shows AD flag), and DNS-over-TLS is the upstream transport (confirmed by `tcpdump` on port 853)
  3. NTP is synchronized to upstream pools and clients receive time service (`ntpq -p` shows sync, client clocks converge within acceptable tolerance)
  4. All three services (dhcpd, unbound, ntpd) auto-start and are running after a clean reboot
**Plans**: TBD

### Phase 3: SSH Hardening and Management Security
**Goal**: Remote management is locked down to key authentication from a whitelisted subnet, with Guardian blocking brute-force attempts before any Suricata IPS rules could interfere with management traffic
**Depends on**: Phase 2
**Requirements**: SSH-01, SSH-02, SSH-03, SSH-04, SSH-05
**Success Criteria** (what must be TRUE):
  1. An SSH connection attempt using a password from any host is rejected; key-based auth from a whitelisted management host succeeds
  2. An SSH connection attempt from an IP outside the management subnet is refused at the firewall level (packet dropped, not just auth failure)
  3. Guardian is installed and active; repeated failed SSH attempts from a non-whitelisted IP result in a temporary block visible in Guardian's WUI panel
  4. The IPFire WUI at port 444 is unreachable from a host on ORANGE or BLUE, but reachable from the management host on GREEN
**Plans**: TBD

### Phase 4: Suricata IDS/IPS
**Goal**: Suricata is running inline on RED and GREEN in monitor-then-active mode with ET Community rulesets, N100-appropriate memcap limits, and EVE JSON output confirmed at `/var/log/suricata/eve.json`
**Depends on**: Phase 3
**Requirements**: IDS-01, IDS-02, IDS-03, IDS-04, IDS-05, IDS-06, IDS-07, IDS-08
**Success Criteria** (what must be TRUE):
  1. Suricata is running and `/var/log/suricata/eve.json` is actively receiving entries — `tail -f` shows new events within 60 seconds of network activity
  2. Triggering a known test signature (e.g., curl to a test-IDS URL) produces a matching alert entry in `eve.json` with correct source IP, destination, and rule metadata
  3. Rule updates run daily and complete without error; `suricata-update` log shows successful ruleset fetch and load
  4. Suricata memory usage stays within defined memcap limits after 30 minutes of normal traffic (no OOM events, CPU headroom confirmed on N100)
  5. The post-Core-Update validation script detects if `suricata.yaml` has been overwritten and reports the finding
**Plans**: TBD

### Phase 5: Telemetry Pipeline and Dashboards
**Goal**: An off-box Docker Compose stack on a GREEN-zone monitoring host is ingesting IPFire firewall logs via UDP syslog and Suricata EVE JSON via file-read, storing data in Loki, and displaying threat-tracing dashboards in Grafana
**Depends on**: Phase 4
**Requirements**: TEL-01, TEL-02, TEL-03, TEL-04, TEL-05, TEL-06, TEL-07, TEL-08, DASH-01, DASH-02, DASH-03, DASH-04
**Success Criteria** (what must be TRUE):
  1. A firewall drop event on IPFire appears as a labeled log entry in Grafana/Loki within 60 seconds of the packet being dropped
  2. A Suricata IDS alert appears in Grafana within 60 seconds of the triggering event, with source IP, destination, rule name, and severity visible
  3. The threat-tracing dashboard shows a single-pane view connecting a source IP to its IDS alert and to the resulting firewall action for the same flow
  4. The top blocked IPs and top triggered rule names are visible in dedicated dashboard panels
  5. Log retention policy is configured (defined maximum age or volume) and confirmed in Loki config
**Plans**: TBD

### Phase 6: System Hardening and Validation Suite
**Goal**: All unnecessary services are disabled, IPFire hardening recommendations are applied, and a scripted validation suite produces a pass/fail report covering every capability from NIC binding through telemetry ingestion
**Depends on**: Phase 5
**Requirements**: HARD-01, HARD-02, HARD-03, HARD-04, HARD-05, VAL-01, VAL-02, VAL-03, VAL-04, VAL-05, VAL-06, VAL-07, VAL-08, VAL-09, VAL-10, VAL-11
**Success Criteria** (what must be TRUE):
  1. Running the validation suite script produces a pass/fail report and all tests pass on a system that has just completed a clean reboot
  2. No unnecessary services are running (`ss -tlnp` and Pakfire shows only expected services); audit logging captures configuration changes
  3. Kernel hardening parameters are active (`sysctl -a` shows IP source routing disabled, ICMP redirects disabled, and other hardened values)
  4. The IPFire WUI HTTPS certificate is documented and the backup include list covers all custom configs including udev rules, `firewall.local`, and Suricata customizations
**Plans**: TBD

### Phase 7: Reproducibility and Disaster Recovery
**Goal**: Every configuration artifact lives in the git repo, a rebuild script applies the full configuration idempotently to a fresh IPFire install, and rollback procedures exist for every change category
**Depends on**: Phase 6
**Requirements**: REPO-01, REPO-02, REPO-03, REPO-04, REPO-05, REPO-06
**Success Criteria** (what must be TRUE):
  1. Running the rebuild script against a fresh IPFire install produces a fully configured appliance that passes the full validation suite without manual intervention
  2. The repo contains a complete Pakfire add-on manifest and a full file manifest with checksums; a diff between the manifest and a live system detects any drift
  3. Rollback procedures exist for every change category (firewall rules, IPS rules, DNS config, DHCP leases, zone config) and each procedure has been tested
  4. The decision log (ADR format) is committed to the repo with entries covering all architectural choices documented in PROJECT.md Key Decisions
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Platform Foundation and Firewall | 1/4 | In Progress|  |
| 2. Core Network Services | 0/TBD | Not started | - |
| 3. SSH Hardening and Management Security | 0/TBD | Not started | - |
| 4. Suricata IDS/IPS | 0/TBD | Not started | - |
| 5. Telemetry Pipeline and Dashboards | 0/TBD | Not started | - |
| 6. System Hardening and Validation Suite | 0/TBD | Not started | - |
| 7. Reproducibility and Disaster Recovery | 0/TBD | Not started | - |
