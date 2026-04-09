# Network Wiring Diagram — Firewall AI SOC

**Date:** 2026-04-09 (verified against live hardware)
**Hardware:** Intel N100 6-NIC mini-PC (IPFire) + GMKtec NucBox G3 Plus (Data Layer) + Desktop SOC (Analysis Layer)

```
                    ISP MODEM (192.168.1.254)
                          │
                          │ Ethernet
                          │
              ┌───────────┴──────────────────────────────────────┐
              │         INTEL N100 6-NIC MINI-PC (IPFire)        │
              │                                                  │
              │  ETH0 🔴 RED    ← modem cable (WAN)             │
              │  ETH1 🟠 ORANGE   (future sniffer/honeypot)     │
              │  ETH2 🟠 ORANGE   (future sniffer/honeypot)     │
              │  ETH3 🔵 BLUE     (future WiFi/IoT)             │
              │  ETH4 🟢 GREEN  → switch cable (LAN)            │
              │  ETH5 🟢 GREEN    (bridge, unused)              │
              │                                                  │
              │  Zones: CONFIG_TYPE=3 (GREEN+RED+BLUE+ORANGE)   │
              │  Only ETH0 and ETH4 have cables connected       │
              └──────────────────┬───────────────────────────────┘
                                 │
                                 │ ETH4 GREEN (192.168.1.1/24)
                                 │
              ┌──────────────────┴───────────────────────────────┐
              │         NETGEAR GS308EP MANAGED SWITCH           │
              │         (SPAN mirror: Port 1 → Port 5)          │
              │                                                  │
              │  Port 1 ← IPFire GREEN (SPAN source — ALL)     │
              │  Port 2 → Laptop                                │
              │  Port 3 → Desktop SOC (RTX 5080)                │
              │  Port 4 → GMKtec enp3s0 (network)              │
              │  Port 5 → GMKtec USB adapter (SPAN capture)     │
              │  Port 6-8   (empty)                             │
              └──┬──────┬──────┬──────┬─────────────────────────┘
                 │      │      │      │
                 │      │      │      │
        ┌────────┘      │      │      └────────────────┐
        │               │      │                       │
   ┌────┴────┐   ┌──────┴──┐  ┌┴──────────────┐  ┌────┴────────────────────┐
   │ Laptop  │   │ Desktop │  │    GMKtec     │  │  GMKtec USB Ethernet   │
   │         │   │   SOC   │  │   enp3s0      │  │  enx6c6e072d459d       │
   │         │   │         │  │   (network)   │  │  (SPAN capture)        │
   │         │   │ RTX 5080│  │               │  │  PROMISC, no IP        │
   │         │   │ local-  │  │  192.168.1.22 │  │  Zeek + Suricata read  │
   │         │   │ ai-soc  │  │               │  │  raw packets here      │
   └─────────┘   └─────────┘  └───────────────┘  └─────────────────────────┘
```

## Cable Connections

| Cable # | FROM | TO | Purpose |
|---------|------|----|---------|
| 1 | ISP Modem | IPFire **ETH0** (RED) | WAN internet uplink |
| 2 | IPFire **ETH4** (GREEN) | GS308EP Switch Port 1 | LAN gateway |
| 3 | GS308EP Port 2 | Laptop | Management |
| 4 | GS308EP Port 3 | Desktop SOC (RTX 5080) | Analysis layer |
| 5 | GS308EP Port 4 | GMKtec enp3s0 (built-in Ethernet) | Data layer network |
| 6 | GS308EP Port 5 | GMKtec USB Ethernet adapter | SPAN capture (promiscuous) |

## Data Flow Paths

```
IPFire syslog (UDP :514) ─────────────────────────────► rsyslog :514
                                                          │ on supportTAK-server
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


IPFire Suricata EVE ──── SCP cron (60s) ──────────────► /opt/malcolm/
  /var/log/suricata/                                suricata-logs/
  eve.json                                          suricata-ipfire/
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


SPAN mirror (all GREEN traffic) ──────────────────────► USB adapter
  GS308EP Port 1 → Port 5                          enx6c6e072d459d
                                                    (promiscuous mode)
                                                          │
                                                    ┌─────┴─────┐
                                                    ▼           ▼
                                                  Zeek      Suricata
                                                (2 workers) (2 threads)
                                                    │           │
                                                    ▼           ▼
                                                Logstash    Logstash
                                              (zeek pipe) (suricata pipe)
                                                    │           │
                                                    ▼           ▼
                                                OpenSearch  OpenSearch
                                              (network-*) (arkime_sessions3-*)


All raw logs ──── hourly cron ────────────────────────► Seagate 1.8TB
  EVE JSON, syslog, Zeek logs                       /firewall-archive/
                                                    raw-logs/ + checksums/
                                                    SHA256 chain of custody
```

## IP Address Table

| Device | Interface | IP Address | Subnet | Zone | Notes |
|--------|-----------|------------|--------|------|-------|
| IPFire | red0 (ETH0) | DHCP (192.168.1.106) | /24 | RED | WAN — same subnet as GREEN (modem NAT) |
| IPFire | green0 (ETH4) | 192.168.1.1 | /24 | GREEN | LAN gateway |
| IPFire | orange0 (ETH1) | 192.168.3.1 | /24 | ORANGE | Future sniffer/honeypot |
| IPFire | blue0 (ETH3) | 192.168.2.1 | /24 | BLUE | Future WiFi/IoT |
| Laptop | — | DHCP | /24 | GREEN | Management |
| Desktop SOC | — | DHCP | /24 | GREEN | Analysis layer (local-ai-soc, RTX 5080) |
| GMKtec | enp3s0 | 192.168.1.22 | /24 | GREEN | Data layer (Malcolm) |
| GMKtec | enx6c6e072d459d | none | — | — | SPAN capture (promiscuous, no IP) |

## SSH Access

| From | To | Command | Key |
|------|----|---------|-----|
| Laptop/Desktop | IPFire | `ssh root@192.168.1.1` | `~/.ssh/id_ed25519` |
| Laptop/Desktop | GMKtec | `ssh opsadmin@192.168.1.22` | `~/.ssh/id_ed25519` |
| GMKtec | IPFire | `scp -i ~/.ssh/eve_rsync_ed25519 root@192.168.1.1:...` | `~/.ssh/eve_rsync_ed25519` |

## Port Summary (supportTAK-server)

| Port | Protocol | Service | Binding | Auth |
|------|----------|---------|---------|------|
| 22 | TCP | SSH (opsadmin) | 0.0.0.0 | Key-only |
| 443 | TCP | Malcolm Dashboards (nginx) | 0.0.0.0 | Basic auth |
| 514 | UDP | rsyslog (receives IPFire syslog) | 0.0.0.0 | None (UDP) |
| 5044 | TCP | Malcolm Logstash (Beats) | 0.0.0.0 | TLS certs |
| 5514 | UDP | Malcolm Filebeat (syslog relay) | 0.0.0.0 | None (internal relay) |
| 8200 | TCP | ChromaDB RAG API | 0.0.0.0 | Bearer token |
| 9200 | TCP | OpenSearch API | 0.0.0.0 | TLS + malcolm_internal creds |

## GS308EP Switch Configuration

| Setting | Value |
|---------|-------|
| Management IP | 192.168.1.104 |
| Management URL | http://192.168.1.104 |
| Default password | `password` (change this) |
| SPAN source | Port 1 (all traffic, both directions) |
| SPAN destination | Port 5 |

## Power Cycle Checklist

### IPFire (N100)
1. Verify boot completed — SSH: `ssh root@192.168.1.1 "uptime"`
2. Check authorized_keys: `cat /root/.ssh/authorized_keys` — should have 2 keys
3. If keys missing: restore from `configs/ssh/authorized_keys` in repo
4. Check syslog target: `grep 192.168 /etc/syslog.conf` — should be `192.168.1.22`
5. May need to bounce RED interface: `ip link set red0 down; sleep 3; ip link set red0 up`

### SOC Host (GMKtec) — LUKS ENCRYPTED
1. **REQUIRES PASSPHRASE ON CONSOLE BEFORE SSH WORKS.** Connect monitor + keyboard, enter LUKS passphrase at boot prompt. This is NOT a hardware failure.
2. After LUKS unlock, verify IP: `ip a | grep inet` — must show `192.168.1.22`
3. If wrong IP: check `cat /etc/netplan/01-network-manager-all.yaml`
4. Check Malcolm: `docker compose -f /opt/malcolm/docker-compose.yml ps | grep -c healthy` — expect 27
5. If Malcolm not running: `cd /opt/malcolm && ./scripts/start`
6. Check USB adapter: `ip link show enx6c6e072d459d` — should show PROMISC,UP
7. If USB adapter down: `sudo ip addr flush dev enx6c6e072d459d && sudo ip link set enx6c6e072d459d promisc on`
8. Check rsyslog: `pgrep rsyslogd` — must return PID
9. Check SCP cron: `crontab -l | grep sync-eve`
10. Check archive cron: `crontab -l | grep archive-logs`

### GS308EP Switch
1. SPAN mirror config survives power cycles (stored in switch firmware)
2. Verify at http://192.168.1.104 → Diagnostics → Port Mirroring
3. Source: Port 1, Destination: Port 5
