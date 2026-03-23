# Firewall Appliance

A fully configured, hardened, reproducible firewall/router/security gateway built on an Intel N100 6-NIC mini-PC running IPFire. Includes IDS/IPS (Suricata), off-box telemetry (Grafana + Loki + Alloy), and git-based disaster recovery.

## Core Value

**If the box dies, the repo rebuilds it identically in under 15 minutes.**

Every configuration, script, validation test, and runbook lives in this repository. No manual steps are undocumented.

## Architecture

```
                    +-----------+
  ISP/Modem ------->|   RED     | (WAN - DHCP)
                    |           |
  LAN Switch ------>|  GREEN    | (192.168.1.0/24)
    |               |           |
    +-- Win PC      |  BLUE     | (192.168.2.0/24 - WiFi/IoT)
    +-- Ubuntu Tel  |           |
                    |  ORANGE   | (192.168.3.0/24 - DMZ)
                    +-----------+
                      IPFire N100

  Telemetry Host (192.168.1.101 - Ubuntu 22.04)
    +-- Grafana    :3000  (dashboards)
    +-- Loki       :3100  (log storage)
    +-- Alloy      :514   (syslog collector)
    +-- Prometheus  :9090  (metrics)
```

## Hardware

| Component | Details |
|-----------|---------|
| Platform | Intel N100 6-NIC mini-PC |
| NICs | 6x Intel i226-V (igc driver) |
| OS | IPFire 2.29 Core Update 200 |
| Kernel | 6.18.7 LTS |
| RAM | 16GB DDR5 (single-channel) |
| Storage | NVMe |
| Telemetry Host | GMKtec mini-PC, Ubuntu 22.04, Docker |

## Network Zones

| Zone | Interface | IP | Purpose |
|------|-----------|-----|---------|
| GREEN | green0 | 192.168.1.1/24 | Trusted LAN |
| RED | red0 | DHCP | WAN uplink |
| BLUE | blue0 | 192.168.2.1/24 | WiFi/IoT (future) |
| ORANGE | orange0 | 192.168.3.1/24 | DMZ (future) |
| GREEN Bridge | green1, green2 | bridged | Extra LAN ports |

See [docs/nic-map.md](docs/nic-map.md) for MAC-to-port mapping.

## Directory Structure

```
Firewall/
+-- configs/
|   +-- udev/              # NIC persistence rules (30-persistent-network.rules)
|   +-- ethernet/          # IPFire ethernet/settings export
|   +-- firewall/          # firewall.local, backup-include.user
|   +-- dhcp/              # DHCP server config exports
|   +-- dns/               # Unbound/DoT config templates
|   +-- ntp/               # NTP time-settings templates
|   +-- ssh/               # sshd_config hardened reference
|   +-- guardian/          # Guardian brute-force config
|   +-- suricata/          # Suricata config references + memcap
+-- scripts/
|   +-- validate-nics.sh        # NIC MAC-to-zone validation
|   +-- validate-phase1.sh      # Phase 1 integration tests
|   +-- validate-phase2.sh      # Phase 2 service tests (DHCP/DNS/NTP)
|   +-- validate-phase3.sh      # Phase 3 SSH hardening tests
|   +-- validate-phase4.sh      # Phase 4 Suricata IDS tests
|   +-- validate-phase5.sh      # Phase 5 telemetry pipeline tests
|   +-- validate-firewall.sh    # Standalone firewall rule checks
|   +-- check-suricata-integrity.sh  # Post-Core-Update config checker
+-- telemetry/
|   +-- docker-compose.yml      # Grafana + Loki + Alloy + Prometheus
|   +-- alloy/config.alloy      # Syslog + EVE JSON pipeline
|   +-- loki/loki-config.yml    # Storage, retention, query limits
|   +-- grafana/provisioning/   # Datasources + dashboard providers
|   +-- prometheus/prometheus.yml
|   +-- scripts/rsync-eve.sh    # EVE JSON pull from IPFire
+-- docs/
|   +-- nic-map.md              # Physical port to zone mapping
|   +-- deployment-checklist.md # Initial setup procedure
|   +-- services-runbook.md     # DHCP/DNS/NTP WUI config steps
|   +-- ssh-management-runbook.md  # SSH hardening deployment
|   +-- suricata-ids-runbook.md # IDS/IPS deployment procedure
|   +-- zone-policy-runbook.md  # Firewall zone policy steps
+-- services/               # Service-specific configs (future)
+-- validation/             # Test artifacts (Phase 6)
+-- rollback/               # Rollback procedures (Phase 7)
+-- manifests/              # Pakfire addon manifest (Phase 7)
+-- decision-log/           # Architecture Decision Records
+-- .planning/              # GSD project planning artifacts
```

## Quick Start

### Validate IPFire (run on the appliance)

```bash
# Clone repo to IPFire
scp -r . root@192.168.1.1:/root/firewall-repo

# Fix Windows line endings
find /root/firewall-repo/scripts -name "*.sh" -exec sed -i 's/\r$//' {} \; -exec chmod +x {} \;

# Run NIC validation
bash /root/firewall-repo/scripts/validate-nics.sh

# Run full phase validation
bash /root/firewall-repo/scripts/validate-phase1.sh
bash /root/firewall-repo/scripts/validate-phase2.sh
bash /root/firewall-repo/scripts/validate-phase3.sh
bash /root/firewall-repo/scripts/validate-phase4.sh
```

### Deploy Telemetry Stack (run on Ubuntu host)

```bash
cd /opt
sudo git clone https://github.com/Reston2024/Firewall.git telemetry
cd /opt/telemetry/telemetry
sudo docker compose up -d

# Access Grafana
# http://192.168.1.101:3000 (admin/admin)
```

## Security Features

| Feature | Status | Details |
|---------|--------|---------|
| Stateful firewall | Active | Default-deny inbound, NAT/masquerade |
| Zone isolation | Active | GREEN/RED/BLUE/ORANGE with explicit policies |
| SSH key-only auth | Active | Password auth disabled, key required |
| SSH brute-force protection | Active | Guardian with management host whitelist |
| Management lockout prevention | Active | firewall.local CUSTOMINPUT rules |
| DNSSEC | Active | Mandatory validation via Unbound |
| DNS-over-TLS | Active | Cloudflare + Quad9 upstream |
| IDS/IPS (Suricata) | Active | ET Community rules, surveillance mode |
| NIC persistence | Active | udev MAC-based zone binding |
| Backup protection | Active | include.user for Core Update survival |

## Build Phases

| # | Phase | Status |
|---|-------|--------|
| 1 | Platform Foundation & Firewall | Complete |
| 2 | Core Network Services (DHCP/DNS/NTP) | Complete |
| 3 | SSH Hardening & Management Security | Complete |
| 4 | Suricata IDS/IPS | Complete |
| 5 | Telemetry Pipeline & Dashboards | In Progress |
| 6 | System Hardening & Validation Suite | Planned |
| 7 | Reproducibility & Disaster Recovery | Planned |

## Key Files for Rebuild

If starting from a fresh IPFire install, deploy these in order:

1. `configs/udev/30-persistent-network.rules` -> `/etc/udev/rules.d/`
2. `configs/firewall/firewall.local` -> `/etc/sysconfig/`
3. `configs/firewall/backup-include.user` -> `/var/ipfire/backup/include.user`
4. Follow `docs/deployment-checklist.md` for hostname/timezone
5. Follow `docs/services-runbook.md` for DHCP/DNS/NTP
6. Follow `docs/ssh-management-runbook.md` for SSH hardening
7. Follow `docs/suricata-ids-runbook.md` for IDS/IPS

## License

[MIT](LICENSE)
