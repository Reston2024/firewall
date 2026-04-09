# Telemetry Deployment Runbook — v2.0 Malcolm NSM

**Date:** 2026-04-08 (updated for ADR-E04 architecture pivot)
**Stack:** Malcolm v26.02.0 — 10 active containers (17 disabled, no SPAN hardware)
**Role:** DATA LAYER ONLY — no AI inference (see ADR-E04)
**SOC host:** supportTAK-server (192.168.1.22, Intel N150, 16GB RAM, Ubuntu 22.04, LUKS encrypted)
**IPFire:** 192.168.1.1 (IPFire 2.29 CU200, Suricata 8.0.3)
**Repo root (dev machine):** C:\Users\ablan\Firewall

Complete sections in ORDER — the sequence below is mandatory for safe deployment.

---

## Architecture Overview

```
IPFire (192.168.1.1)
  |
  +-- Suricata EVE JSON (/var/log/suricata/eve.json)
  |     |
  |     +-- SCP cron (60s) via sync-eve.sh
  |           |
  |           v
  |     /opt/malcolm/suricata-logs/suricata-ipfire/eve.json
  |           |
  |           v
  |     Malcolm internal Filebeat (_filebeat_suricata_malcolm_upload)
  |           |
  |           v
  |     Malcolm Logstash (suricata pipeline)
  |           |
  |           v
  |     OpenSearch (arkime_sessions3-* indices)
  |
  +-- Syslog (UDP :514 via syslog.conf)
        |
        v
  rsyslog on SOC host (:514)
        |
        +-- omfwd relay to 127.0.0.1:5514
              |
              v
        Malcolm Filebeat syslog listener (:5514/udp)
              |
              v
        Malcolm Logstash (beats pipeline)
              |
              v
        OpenSearch (malcolm_beats_syslog_* indices)
```

**Access:** Malcolm dashboards at https://192.168.1.22 (basic auth)

---

## CRITICAL WARNINGS

- **Malcolm must be running BEFORE configuring IPFire syslog forwarding** — Filebeat syslog listener must be bound to :5514 before IPFire starts sending logs.
- **rsyslog must remain running** — it receives IPFire syslog on UDP :514 and relays to Malcolm on :5514. Do NOT disable rsyslog.
- **EVE JSON delivery uses Malcolm's internal Filebeat** — files must be placed in `/opt/malcolm/suricata-logs/suricata-*/` directory pattern. External Filebeat cannot replicate Malcolm's internal routing tags.
- **OpenSearch heap is 6GB, Logstash heap is 2GB** — do not increase without verifying RAM headroom (`free -m` must show used < 14GB).
- **Arkime live capture is disabled** — no SPAN/mirror port available. Do not enable without a managed switch.

---

## Section 1: Pre-Flight Checks

```bash
# Verify SOC host reachable
ssh opsadmin@192.168.1.22 "hostname && free -m | grep Mem"

# Verify Malcolm running
ssh opsadmin@192.168.1.22 "docker compose -f /opt/malcolm/docker-compose.yml ps --format '{{.Name}} {{.Status}}' | grep -c healthy"
# Expected: 27

# Verify ports
ssh opsadmin@192.168.1.22 "ss -tlnp | grep 5044"   # Logstash beats
ssh opsadmin@192.168.1.22 "ss -ulnp | grep 5514"   # Malcolm syslog
ssh opsadmin@192.168.1.22 "ss -ulnp | grep ':514'"  # rsyslog

# Verify IPFire syslog target
ssh root@192.168.1.1 "grep '192.168' /etc/syslog.conf"
# Expected: *.*  @192.168.1.22
```

---

## Section 2: EVE JSON Path (Suricata Alerts)

The EVE JSON path uses SCP to pull from IPFire, then Malcolm's internal Filebeat picks it up.

### 2.1 SCP Sync Script

Location on SOC host: `/opt/malcolm/scripts/sync-eve.sh`
Repo copy: `telemetry-malcolm/filebeat/scp-eve.sh`

```bash
# Verify SCP cron is running
ssh opsadmin@192.168.1.22 "crontab -l | grep sync-eve"
# Expected: * * * * * /opt/malcolm/scripts/sync-eve.sh

# Verify eve.json is fresh (less than 2 minutes old)
ssh opsadmin@192.168.1.22 "stat -c '%Y' /opt/malcolm/suricata-logs/suricata-ipfire/eve.json"

# Test SCP manually
ssh opsadmin@192.168.1.22 "/opt/malcolm/scripts/sync-eve.sh && echo OK"
```

### 2.2 SSH Key for SCP

The SCP uses a dedicated ed25519 key at `/home/opsadmin/.ssh/eve_rsync_ed25519`.
This key must be in IPFire's `/root/.ssh/authorized_keys`.
Both keys (management + eve_rsync) are stored in `configs/ssh/authorized_keys` in the repo.

**Recovery after IPFire crash/reboot:**
```bash
# From management PC (key-based SSH to IPFire already works):
ssh root@192.168.1.1 "cat /root/.ssh/authorized_keys"
# If eve_rsync key is missing, re-add it:
# The public key is: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF0N64y7aJ0Nh+MfqAEhOfax8RbyKhNCoD+o0mP8THLZ eve-rsync@supportTAK-server
```

### 2.3 Malcolm Suricata Data Path

Malcolm's internal Filebeat monitors `/suricata/suricata-*/eve*.json` inside the container.
The host directory `/opt/malcolm/suricata-logs/` is bind-mounted as `/suricata/` in the container.
Files MUST be in a subdirectory matching `suricata-*` (e.g., `suricata-ipfire/`).

```bash
# Verify data is being indexed
CREDS=$(ssh opsadmin@192.168.1.22 "docker exec malcolm-dashboards-helper-1 \
  cat /var/local/curlrc/.opensearch.primary.curlrc \
  | grep '^user:' | sed 's/^user: \"//;s/\"$//'" 2>/dev/null)
ssh opsadmin@192.168.1.22 "docker exec malcolm-opensearch-1 \
  curl -sk -u '${CREDS}' 'https://localhost:9200/arkime_sessions3-*/_count'"
# Expected: count > 0
```

---

## Section 3: Syslog Path (Firewall Logs)

### 3.1 IPFire Syslog Configuration

IPFire forwards all syslog to the SOC host via `/etc/syslog.conf`:
```
*.*    @192.168.1.22
```

This is configured via IPFire WUI > Logs > Log Settings > Remote Syslog Server.

### 3.2 rsyslog Relay on SOC Host

rsyslog receives on UDP :514 and relays to Malcolm Filebeat syslog on :5514.

Config files:
- `/etc/rsyslog.d/10-ipfire-remote.conf` — UDP :514 listener (imudp module)
- `/etc/rsyslog.d/20-malcolm-forward.conf` — omfwd relay to 127.0.0.1:5514

Repo copy: `telemetry-malcolm/rsyslog/20-malcolm-forward.conf`

```bash
# Verify rsyslog is active
ssh opsadmin@192.168.1.22 "systemctl is-active rsyslog"

# Verify syslog data in Malcolm
ssh opsadmin@192.168.1.22 "docker exec malcolm-opensearch-1 \
  curl -sk -u '${CREDS}' 'https://localhost:9200/malcolm_beats_syslog_*/_count'"
# Expected: count > 0
```

### 3.3 Malcolm Filebeat Syslog Listener

Malcolm's Filebeat container listens on UDP :5514 for syslog.

Config: `/opt/malcolm/config/filebeat.env`
```
FILEBEAT_SYSLOG_UDP_LISTEN=true
FILEBEAT_SYSLOG_UDP_PORT=5514
```

Port :5514/udp is exposed in `/opt/malcolm/docker-compose.yml` under the filebeat service.

---

## Section 4: Validation

```bash
# Run full Phase 9 validation (Malcolm health)
bash scripts/validate-phase9.sh --full

# Run full Phase 10 validation (data flow + migration)
bash scripts/validate-phase10.sh

# Trigger a test Suricata alert
ssh root@192.168.1.1 "curl -s http://testmynids.org/uid/index.html > /dev/null"
# Wait 90 seconds, then check Malcolm Suricata Alerts dashboard
# Set time range to "Last 7 days" to see historical + new alerts
```

---

## Section 5: ISM Retention Policy

OpenSearch ISM policy `malcolm-retention` auto-deletes indices older than 30 days.

```bash
# Verify ISM policy
ssh opsadmin@192.168.1.22 "docker exec malcolm-opensearch-1 \
  curl -sk -u '${CREDS}' \
  'https://localhost:9200/_plugins/_ism/policies/malcolm-retention'"
```

Covered indices: `network-*`, `arkime_sessions3-*`

Additional safety: `OPENSEARCH_INDEX_SIZE_PRUNE_LIMIT=200g` in opensearch.env.

---

## Section 6: Troubleshooting

### No EVE data in Malcolm
1. Check SCP cron: `crontab -l | grep sync-eve`
2. Check eve.json freshness: `ls -la /opt/malcolm/suricata-logs/suricata-ipfire/`
3. Check Malcolm Filebeat logs: `docker logs malcolm-filebeat-1 --tail 20`
4. Check Logstash logs: `docker logs malcolm-logstash-1 --tail 20`
5. Check if Logstash OOM: `docker logs malcolm-logstash-1 2>&1 | grep OutOfMemory`

### No syslog data in Malcolm
1. Check rsyslog: `systemctl status rsyslog`
2. Check IPFire syslog target: `ssh root@192.168.1.1 "grep 192.168 /etc/syslog.conf"`
3. Check Malcolm Filebeat syslog port: `ss -ulnp | grep 5514`
4. Send test syslog: `logger "TEST_SYSLOG_$(date +%s)"` then search in Malcolm

### Malcolm containers unhealthy
1. Check RAM: `free -m` — if used > 14GB, OOM risk
2. Check for OOM kills: `sudo dmesg | grep -i oom`
3. Restart specific container: `cd /opt/malcolm && docker compose up -d --no-deps <container>`
4. Full restart: `cd /opt/malcolm && ./scripts/restart`

---

## Section 7: Disaster Recovery

### IPFire reboot/crash recovery
1. Verify SSH keys: `ssh root@192.168.1.1 "cat /root/.ssh/authorized_keys"` — should have 2 keys (management + eve_rsync)
2. If keys missing: restore from `configs/ssh/authorized_keys` in repo
3. Verify syslog target: `grep 192.168 /etc/syslog.conf` — should be 192.168.1.22
4. Test SCP: `/opt/malcolm/scripts/sync-eve.sh && echo OK`

### SOC host reboot recovery
1. Malcolm auto-starts via Docker restart policy (if configured) or: `cd /opt/malcolm && ./scripts/start`
2. rsyslog auto-starts via systemd
3. SCP cron persists in opsadmin's crontab
4. Verify: `bash scripts/validate-phase9.sh --full && bash scripts/validate-phase10.sh`

---

## Section 8: v1.0 Stack (Decommissioned)

The v1.0 telemetry stack (Grafana 12.4.1, Loki 3.6.0, Alloy 1.14.1, Prometheus 3.10.0, node-exporter 1.8.2) was decommissioned on 2026-04-06. Containers and volumes removed via `docker compose down -v` from `/opt/telemetry`.

Historical data from the Loki stack is not preserved — it was not migrated to Malcolm/OpenSearch (incompatible storage formats). EVE JSON historical data from March 25-28 was ingested into Malcolm from the SCP-pulled file.

The `/opt/telemetry` directory and repo `telemetry/` directory contain the v1.0 configs for reference only. They are no longer active.

---

*Last updated: 2026-04-06 after Phase 10 completion*
