# Firewall Appliance + Local AI SOC

A two-tier local-first AI SOC: a hardened IPFire perimeter appliance with Malcolm NSM as the data collection layer, feeding a desktop SOC Brain (RTX 5080) for GPU-accelerated AI analysis. Raw telemetry flows from firewall → indexer → analyst with no AI on the data path.

## Core Value

**Raw telemetry collected, preserved with chain of custody, and served to a GPU-powered local SOC for AI-assisted analysis — no cloud, no data distortion between collection and analysis.**

### v1.0 (Shipped 2026-03-26)
Hardened IPFire perimeter with Suricata IDS/IPS, off-box telemetry (Grafana + Loki + Alloy), git-based disaster recovery (15-min rebuild), full validation suite, and 12 ADRs. 8 phases, 27 plans, 124 commits, 192 files.

### v2.0 (In Progress)
Malcolm NSM data layer (10 active containers), desktop SOC integration via OpenSearch API, raw log archival with chain of custody. AI removed from data layer per ADR-E04 — desktop SOC (local-ai-soc, RTX 5080) handles all inference. 17 Malcolm containers disabled pending SPAN hardware (~$48).

## Architecture

```
  ISP Modem
      |
  IPFire N100 (192.168.1.1) ── firewall, routing, Suricata IDS
      |  Port 1 (GREEN) ── only 2 of 6 ports in use
      |  Port 3 (RED) ── WAN
      |
  GS305 Switch (unmanaged — no SPAN capability)
      |
      +── Laptop
      +── Desktop SOC (RTX 5080, local-ai-soc)
      +── supportTAK-server (192.168.1.22)

  supportTAK-server — DATA LAYER (NO AI)
  ┌─────────────────────────────────────────────┐
  │  Malcolm NSM (10 active / 17 disabled)      │
  │    OpenSearch   :9200  (alert/log store)    │
  │    Logstash     :5044  (EVE JSON ingest)    │
  │    Filebeat     :5514  (syslog relay)       │
  │    Dashboards   :443   (web UI, basic auth) │
  │  ChromaDB API   :8200  (RAG corpus, 387ch)  │
  │  17 containers DISABLED (no SPAN hardware)  │
  │  NO AI — raw data only (ADR-E04)            │
  └─────────────────────────────────────────────┘

  Desktop SOC — ANALYSIS LAYER (ALL AI HERE)
  ┌─────────────────────────────────────────────┐
  │  local-ai-soc (FastAPI + Svelte 5)          │
  │    Ollama qwen3:14b (RTX 5080 GPU)          │
  │    DuckDB (event store)                     │
  │    ChromaDB (local embeddings)              │
  │    Sigma detection engine                   │
  │    SOAR playbooks + HITL gates              │
  │    Pulls from Malcolm OpenSearch API        │
  └─────────────────────────────────────────────┘
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
| SOC Host | GMKtec NucBox G3 Plus, Intel N150, 16GB RAM, 912GB NVMe, Ubuntu 22.04 |

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
|   +-- validate-phase6.sh      # Phase 6 system hardening tests
|   +-- validate-phase9.sh      # Phase 9 Malcolm NSM tests
|   +-- validate-all.sh         # Full validation suite (all phases)
|   +-- validate-firewall.sh    # Standalone firewall rule checks
|   +-- check-integrity.sh      # SHA256 integrity monitor (8 files)
|   +-- check-drift.sh          # Config drift detection (12 files)
|   +-- validate-reboot.sh      # Reboot persistence validator
|   +-- check-suricata-integrity.sh  # Post-Core-Update config checker
+-- telemetry/                      # v1.0 stack (Loki/Alloy/Grafana — being replaced by Malcolm)
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
+-- validation/             # Hardening configs (sysctl, integrity baselines)
+-- rollback/               # Rollback procedures (7 categories)
+-- manifests/              # Pakfire addon manifest, drift manifest
+-- decisions/              # Architecture Decision Records (12 ADRs)
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

### Deploy v1.0 Telemetry Stack (run on SOC host at 192.168.1.22)

```bash
cd /opt
sudo git clone https://github.com/Reston2024/firewall.git telemetry
cd /opt/telemetry/telemetry
sudo docker compose up -d

# Access Grafana
# http://192.168.1.22:3000 (login with GF_SECURITY_ADMIN_PASSWORD from .env)
```

### Deploy v2.0 Malcolm NSM (run on SOC host at 192.168.1.22)

```bash
# Malcolm is deployed to /opt/malcolm via install.py
# See docs/telemetry-deployment-runbook.md for full procedure
# Access OpenSearch Dashboards: https://192.168.1.22:5601
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
| IDS/IPS (Suricata) | Active | ET Community rules, monitor mode |
| NIC persistence | Active | udev MAC-based zone binding |
| Backup protection | Active | include.user for Core Update survival |
| Sysctl hardening | Active | ICMP redirects, SYN cookies, source routing disabled |
| File integrity monitoring | Active | SHA256 baseline for 8 critical files |
| Config drift detection | Active | 12 managed files tracked |
| Reboot persistence | Validated | iptables rules survive reboot |
| Rebuild from repo | Validated | 15-minute RTO via rebuild.sh |
| Rollback procedures | Active | 7 change categories covered |

## Build Phases

### v1.0 — Firewall Appliance (Shipped 2026-03-26)

| # | Phase | Status |
|---|-------|--------|
| 1 | Platform Foundation & Firewall | Complete |
| 2 | Core Network Services (DHCP/DNS/NTP) | Complete |
| 3 | SSH Hardening & Management Security | Complete |
| 4 | Suricata IDS/IPS | Complete |
| 5 | Telemetry Pipeline & Dashboards | Complete |
| 6 | System Hardening & Validation Suite | Complete |
| 7 | Reproducibility & Disaster Recovery | Complete |
| 8 | Milestone Gap Closure | Complete |

### v2.0 — Local AI SOC (In Progress)

| # | Phase | Status |
|---|-------|--------|
| 9 | Malcolm NSM Deployment | In Progress |
| 10 | Data Ingestion & Loki Migration | Planned |
| 11 | Foundation-Sec-8B AI Analyst Setup | Planned |
| 12 | RAG Pipeline | Planned |
| 13 | Alert Triage Integration | Planned |
| 14 | SBOM & Signed Releases | Planned |

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
