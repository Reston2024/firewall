# Network Wiring Diagram — Firewall AI SOC

**Date:** 2026-04-06
**Hardware:** Intel N100 6-NIC mini-PC (IPFire) + GMKtec NucBox G3 Plus (SOC Host)

```
                          ┌──────────────────────┐
                          │     ISP MODEM         │
                          │                      │
                          └──────────┬───────────┘
                                     │
                                     │ Ethernet cable
                                     │
                    ┌────────────────────────────────────┐
                    │      INTEL N100 6-NIC MINI-PC      │
                    │           (IPFire 2.29)            │
                    │                                    │
                    │  ┌──────┐ ┌──────┐ ┌──────┐       │
                    │  │Port 1│ │Port 2│ │Port 3│       │
                    │  │GREEN │ │ BLUE │ │ RED  │       │
                    │  │green0│ │blue0 │ │red0  │       │
                    │  │ .39  │ │ .3a  │ │ .3b  │       │
                    │  └──┬───┘ └──┬───┘ └──┬───┘       │
                    │     │        │        │            │
                    │  ┌──────┐ ┌──────┐ ┌──────┐       │
                    │  │Port 4│ │Port 5│ │Port 6│       │
                    │  │ORANGE│ │GREEN │ │GREEN │       │
                    │  │orng0 │ │green1│ │green2│       │
                    │  │ .3c  │ │ .3d  │ │ .3e  │       │
                    │  └──┬───┘ └──┬───┘ └──┬───┘       │
                    │     │        │        │            │
                    │  192.168.    │        │            │
                    │  3.1/24      │Bridged to green0    │
                    │  (future)    │                     │
                    └──────────────┼─────────────────────┘
              ▲                   │                 ▲
              │              192.168.1.1/24         │
              │ Port 3            │                 │ Port 2
              │ to modem          │ GREEN zone      │ (future WiFi AP)
              │                   │                 │
              │                   │                 │
              │          ┌────────┴─────────┐       │
              │          │   LAN SWITCH     │       │
              │          │  (unmanaged)     │       │
              │          └──┬───────┬───────┘       │
              │             │       │               │
              │             │       │               │
    ┌─────────┴──┐   ┌──────┴──┐  ┌┴──────────────────────┐
    │ ISP MODEM  │   │ WINDOWS │  │  GMKtec NucBox G3 Plus │
    │            │   │   PC    │  │   (supportTAK-server)  │
    │ WAN DHCP   │   │         │  │                        │
    │            │   │ .1.93   │  │  IP: 192.168.1.22      │
    └────────────┘   │ or .100 │  │  OS: Ubuntu 22.04      │
                     │         │  │                        │
                     │ Mgmt    │  │  ┌─── Malcolm NSM ───┐ │
                     │ Host    │  │  │ OpenSearch  :9200  │ │
                     │         │  │  │ Logstash   :5044  │ │
                     │ SSH key │  │  │ Filebeat   :5514  │ │
                     │ access  │  │  │ Zeek, Arkime      │ │
                     │ to both │  │  │ Dashboards :443   │ │
                     │ boxes   │  │  │ 27 containers     │ │
                     │         │  │  └───────────────────┘ │
                     │         │  │                        │
                     │         │  │  ┌─── AI Stack ─────┐ │
                     │         │  │  │ Ollama    :11434  │ │
                     │         │  │  │ (127.0.0.1 only)  │ │
                     │         │  │  │ Foundation-Sec-8B │ │
                     │         │  │  │ ChromaDB (embed)  │ │
                     │         │  │  │ RAG pipeline      │ │
                     │         │  │  └───────────────────┘ │
                     │         │  │                        │
                     └─────────┘  └────────────────────────┘
```

## Cable Connections (What Plugs Into What)

| Cable # | FROM | TO | Purpose |
|---------|------|----|---------|
| 1 | ISP Modem Ethernet out | N100 **Port 3** (RED) | WAN internet uplink |
| 2 | N100 **Port 1** (GREEN) | LAN Switch | Primary LAN gateway |
| 3 | LAN Switch | Windows PC (`192.168.1.93` / `.100`) | Management workstation |
| 4 | LAN Switch | GMKtec NucBox G3 Plus (`192.168.1.22`) | SOC host (Malcolm + AI) |
| 5 | *(optional)* N100 **Port 5** (GREEN bridge) | LAN Switch | Extra LAN port |
| 6 | *(optional)* N100 **Port 6** (GREEN bridge) | LAN Switch | Extra LAN port |
| 7 | *(future)* N100 **Port 2** (BLUE) | WiFi AP | Wireless/IoT zone |
| 8 | *(future)* N100 **Port 4** (ORANGE) | DMZ switch/host | DMZ servers |

## Data Flow Paths

```
IPFire syslog (UDP :514) ──────────────────────────────────► rsyslog :514
                                                              │
                                                              ▼
                                                         omfwd relay
                                                              │
                                                              ▼
                                                       Malcolm Filebeat
                                                         :5514/udp
                                                              │
                                                              ▼
                                                         Logstash
                                                       (beats pipeline)
                                                              │
                                                              ▼
                                                         OpenSearch
                                                    (malcolm_beats_syslog_*)


IPFire Suricata EVE ──── SCP cron (60s) ──────────────────► /opt/malcolm/
  /var/log/suricata/                                    suricata-logs/
  eve.json                                              suricata-ipfire/
                                                        eve.json
                                                              │
                                                              ▼
                                                       Malcolm internal
                                                         Filebeat
                                                    (_filebeat_suricata_
                                                     malcolm_upload)
                                                              │
                                                              ▼
                                                         Logstash
                                                    (suricata pipeline)
                                                              │
                                                              ▼
                                                         OpenSearch
                                                    (arkime_sessions3-*)
```

## IP Address Table

| Device | Interface | IP Address | Subnet | Zone | Notes |
|--------|-----------|------------|--------|------|-------|
| IPFire | green0 | 192.168.1.1 | /24 | GREEN | LAN gateway, WUI at :444 |
| IPFire | red0 | DHCP | varies | RED | WAN uplink |
| IPFire | blue0 | 192.168.2.1 | /24 | BLUE | Future WiFi/IoT |
| IPFire | orange0 | 192.168.3.1 | /24 | ORANGE | Future DMZ |
| Windows PC | enp* | 192.168.1.93 | /24 | GREEN | Management host |
| SOC Host | enp3s0 | 192.168.1.22 | /24 | GREEN | Malcolm + AI stack |

## SSH Access

| From | To | Command | Key |
|------|----|---------|-----|
| Windows PC | IPFire | `ssh root@192.168.1.1` | `~/.ssh/id_ed25519` |
| Windows PC | SOC Host | `ssh opsadmin@192.168.1.22` | `~/.ssh/id_ed25519` |
| SOC Host | IPFire | `scp -i ~/.ssh/eve_rsync_ed25519 root@192.168.1.1:...` | `~/.ssh/eve_rsync_ed25519` |

## Port Summary (SOC Host)

| Port | Protocol | Service | Binding | Auth |
|------|----------|---------|---------|------|
| 22 | TCP | SSH (opsadmin) | 0.0.0.0 | Key-only |
| 443 | TCP | Malcolm Dashboards (nginx) | 0.0.0.0 | Basic auth |
| 514 | UDP | rsyslog (receives IPFire syslog) | 0.0.0.0 | None (UDP) |
| 5044 | TCP | Malcolm Logstash (Beats) | 0.0.0.0 | TLS certs |
| 5514 | UDP | Malcolm Filebeat (syslog relay) | 0.0.0.0 | None (internal relay) |
| 9200 | TCP | OpenSearch (internal only) | Docker network | Malcolm internal |
| 11434 | TCP | Ollama (AI model API) | **127.0.0.1 only** | None (ADR-E02) |

## Power Cycle Checklist

After a power outage or reboot of either box:

### IPFire (N100)
1. Verify boot completed — SSH: `ssh root@192.168.1.1 "uptime"`
2. Check authorized_keys: `cat /root/.ssh/authorized_keys` — should have 2 keys
3. If keys missing: restore from `configs/ssh/authorized_keys` in repo
4. Check syslog target: `grep 192.168 /etc/syslog.conf` — should be `192.168.1.22`

### SOC Host (GMKtec)
1. Check IP: `ip a | grep inet` — must show `192.168.1.22/24` on enp3s0
2. If wrong IP: `sudo ip addr add 192.168.1.22/24 dev enp3s0`
3. Check netplan: `cat /etc/netplan/01-network-manager-all.yaml` — must show `192.168.1.22/24`
4. Check Malcolm: `docker compose -f /opt/malcolm/docker-compose.yml ps | grep -c healthy` — expect 27
5. If Malcolm not running: `cd /opt/malcolm && ./scripts/start`
6. Check rsyslog: `pgrep rsyslogd` — must return PID
7. Check SCP cron: `crontab -l | grep sync-eve`
8. Check ChromaDB: `/opt/rag/bin/python3 -c "import chromadb; print(chromadb.PersistentClient(path='/var/lib/chromadb').get_collection('firewall-corpus').count())"`
