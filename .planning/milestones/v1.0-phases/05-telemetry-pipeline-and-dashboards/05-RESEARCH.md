# Phase 5: Telemetry Pipeline and Dashboards - Research

**Researched:** 2026-03-23
**Domain:** Off-box Docker Compose telemetry stack — Grafana Alloy, Loki, Grafana, Prometheus on Ubuntu 22.04 monitoring host; ingesting IPFire firewall syslog and Suricata EVE JSON
**Confidence:** HIGH (Docker Compose stack, Alloy config, Loki retention); MEDIUM (EVE JSON delivery path from IPFire off-box, suricata-reporter architecture); LOW (exact suricata.yaml two-output config on live CU200 system)

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TEL-01 | Remote syslog forwarding configured (UDP 514) for firewall logs | IPFire WUI: Logs > Log Settings > remote syslog IP field; UDP 514 is the only natively supported port; no TCP. Firewall logs in /var/log/messages forward via this path. |
| TEL-02 | IPS alert syslog forwarding configured (CU198+ feature) | CU198+ ships suricata-reporter which reads EVE JSON from a unix_dgram socket and writes to reporter.db for email/PDF reports; syslog path for IPS alerts is via WUI same setting as TEL-01 but only meta-events appear in syslog, not full EVE JSON. Full alerts require file-read path (TEL-04 file track). |
| TEL-03 | Off-box telemetry host provisioned with Docker Compose | supportTAK-server (192.168.1.101, Ubuntu 22.04, Docker pre-installed) — Docker Compose v2 stack with Grafana + Loki + Alloy + Prometheus. |
| TEL-04 | Grafana Alloy collector receiving syslog + reading EVE JSON | Alloy 1.14.1: loki.source.syslog for UDP 514 (firewall/system logs) + loki.source.file for EVE JSON. Critical path: EVE JSON file must be accessible on monitoring host — requires SSH-based delivery from IPFire (rsync-pull or SSH tunnel + tail). |
| TEL-05 | Loki ingesting parsed firewall and IDS logs | Loki 3.6.0 with filesystem storage, TSDB schema, retention policy. Alloy pipeline extracts labels from EVE JSON. |
| TEL-06 | Grafana dashboards displaying firewall drops and IDS alerts | Grafana 12.4.1; import dashboard 22247 (Suricata EVE JSON). Custom IPFire firewall drops panel from syslog stream with FORWARDFW label filter. |
| TEL-07 | Phased ingest: firewall logs first, then IDS, then auth/DHCP/DNS | Architecture pattern documented below. Wave structure: Wave 1 = syslog path, Wave 2 = EVE JSON path, Wave 3 = dashboards and retention. |
| TEL-08 | Log retention policy defined and configured | Loki compactor with retention_period in limits_config. Recommended: 30 days for EVE JSON alerts, 14 days for flow/DNS events, 7 days for system syslog. |
| DASH-01 | End-to-end threat trace: source IP to IDS alert to firewall action visible in single pane | LogQL correlation query joining EVE alert stream (src_ip label) with FORWARDFW syslog stream (src_ip extracted from log message). Single Grafana panel with dual-stream query. |
| DASH-02 | Time-series visualization of firewall drop events | LogQL count_over_time on FORWARDFW syslog stream grouped by time. Bar chart panel in Grafana. |
| DASH-03 | IPS alert severity breakdown dashboard | Dashboard 22247 provides this natively. Requires event_type, severity, category labels from Alloy pipeline. |
| DASH-04 | Top blocked IPs / top triggered rules views | LogQL topk() queries on src_ip label from syslog stream (blocked IPs) and signature label from EVE stream (top rules). Table panel in Grafana. |
</phase_requirements>

---

## Summary

Phase 5 deploys an off-box Docker Compose telemetry stack on the supportTAK-server host (192.168.1.101, Ubuntu 22.04, Docker pre-installed) and wires it to receive logs from IPFire 2.29 CU200. The stack uses Grafana Alloy 1.14.1 as the collector, Loki 3.6.0 as log storage, Grafana 12.4.1 for dashboards, and Prometheus 3.10.0 for metrics. The architecture divides into two log delivery paths: (1) UDP syslog on port 514 from IPFire for firewall drop events and system logs, received by Alloy's `loki.source.syslog` component; and (2) Suricata EVE JSON file-read for full IDS alert fidelity, where Alloy's `loki.source.file` tails a local copy of `/var/log/suricata/eve.json` delivered from IPFire via rsync-pull over SSH.

The critical discovery from Phase 4 is that IPFire CU200 runs a `suricata-reporter` process that reads EVE JSON from a unix_dgram socket at `/var/run/suricata/reporter.socket` and writes to `reporter.db` (SQLite) — this is used exclusively for the native email/PDF report feature, NOT for the main eve.json file. The IPFire nopaste config diff confirms that the primary eve-log output uses `filetype: regular` writing to `/var/log/suricata/eve.json`. The `unix_dgram` socket is a second, separate eve-log output added by IPFire's reporter integration, parallel to the standard file output. Both outputs can exist simultaneously. This means the standard `/var/log/suricata/eve.json` file IS the correct Phase 5 data source — it is actively written by IPFire CU200 and is not blocked by the reporter architecture.

The EVE JSON delivery path from off-box is the most operationally complex element. The recommended approach is rsync-pull from the monitoring host using an SSH key, triggered every 60 seconds by a cron job. This avoids NFS (security risk, stateful mount) and SSH tunnel complexity (process management overhead). The rsync approach is stateless, pull-based, and survivable across IPFire reboots. A firewall rule must allow the monitoring host (192.168.1.101) to SSH to IPFire (192.168.1.1) on port 22 using a dedicated read-only key.

**Primary recommendation:** Deploy the Docker Compose stack first, wire UDP syslog (TEL-01 / TEL-04 syslog path) to confirm data flow, then add the EVE JSON rsync path. Import dashboard 22247 and validate with live traffic before building the custom DASH-01 threat-trace panel.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| grafana/alloy | 1.14.1 | Log and metrics collection agent | Mandatory replacement for EOL Promtail (EOL Feb 28, 2026). Single binary. Native `loki.source.syslog` UDP receiver and `loki.source.file` tail. River config language. |
| grafana/loki | 3.6.0 | Label-indexed log storage | 5-10x lighter than ELK. ~250 MB RAM at SOHO scale. No Kafka/Zookeeper. LogQL for correlation queries. |
| grafana/grafana | 12.4.1 | Dashboards and visualization | Latest stable (March 9, 2026). Dashboard 22247 available. Provisioning via config files. |
| prom/prometheus | 3.10.0 | Metrics storage | Latest stable (Feb 24, 2026). Scrapes Alloy self-metrics and node_exporter from monitoring host. |
| prom/node-exporter | 1.8.x | System metrics from monitoring host | Standard companion to Prometheus. Exposes CPU/RAM/disk/net for supportTAK-server. |
| Docker Compose v2 | v2 (pre-installed) | Stack orchestration | Pre-installed on supportTAK-server. Single docker-compose.yml for all services. |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| rsync | system (IPFire+Ubuntu) | Pull EVE JSON from IPFire to monitoring host | EVE JSON file delivery path — cron-triggered pull every 60s |
| openssh-client | system | SSH key auth for rsync | Monitoring host pulls from IPFire using dedicated SSH key |
| logrotate | system (IPFire) | IPFire rotates /var/log/suricata/eve.json | Alloy handles rotation via position tracking — no special config needed |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| rsync-pull for EVE JSON | NFS mount | NFS is stateful, has security concerns noted in project STACK.md, and mounts can hang. rsync is stateless pull. |
| rsync-pull for EVE JSON | SSH tunnel + tail | Requires persistent process management (supervisor or systemd on monitoring host). More complex failure modes. |
| rsync-pull for EVE JSON | suricata redis output | Would require Redis container addition and suricata.yaml modification that gets overwritten on Core Updates. |
| loki.source.file (Alloy) | filebeat | Java/Go dependency overhead; Alloy is already in the stack for syslog. |
| Prometheus | InfluxDB v2 | Prometheus is simpler for SOHO metrics scrape. InfluxDB adds write API complexity. |

**Installation:**

```bash
# On supportTAK-server (192.168.1.101) — Ubuntu 22.04
# Docker is pre-installed. Install Docker Compose plugin if not present:
sudo apt-get install docker-compose-plugin

# Create project directory
sudo mkdir -p /opt/telemetry
cd /opt/telemetry

# Verify Docker is available
docker --version
docker compose version
```

**Version verification:**

```bash
# Current verified versions (March 2026):
docker pull grafana/alloy:v1.14.1
docker pull grafana/loki:3.6.0
docker pull grafana/grafana:12.4.1
docker pull prom/prometheus:v3.10.0
docker pull prom/node-exporter:v1.8.2
```

---

## Architecture Patterns

### Recommended Project Structure

```
/opt/telemetry/                      # Stack root on supportTAK-server
├── docker-compose.yml               # All services defined here
├── alloy/
│   └── config.alloy                 # Alloy River config (syslog + file read)
├── loki/
│   └── loki-config.yml              # Storage, schema, retention
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   └── datasources.yml      # Auto-provision Loki + Prometheus
│   │   └── dashboards/
│   │       └── dashboards.yml       # Dashboard provider config
│   └── dashboards/
│       ├── suricata-22247.json      # Dashboard 22247 (imported)
│       └── ipfire-firewall.json     # Custom firewall drops dashboard
├── prometheus/
│   └── prometheus.yml               # Scrape configs
└── scripts/
    └── rsync-eve.sh                 # Cron script: pull eve.json from IPFire

/var/log/ipfire-eve/                 # EVE JSON staging directory on monitoring host
    eve.json                         # Rsync'd copy from IPFire
```

And in the repo (C:\Users\ablan\Firewall):
```
telemetry/
├── docker-compose.yml
├── alloy/config.alloy
├── loki/loki-config.yml
├── grafana/provisioning/datasources/datasources.yml
├── grafana/provisioning/dashboards/dashboards.yml
├── grafana/dashboards/suricata-22247.json
├── prometheus/prometheus.yml
└── scripts/rsync-eve.sh
```

### Pattern 1: Two-Path Log Ingestion

**What:** Syslog path handles IPFire firewall drops and system events. File-read path handles Suricata EVE JSON. These are separate Alloy components, separate Loki streams, and separate Grafana data sources.

**When to use:** Always on IPFire. EVE alerts never appear in syslog — two paths are mandatory.

```
IPFire (192.168.1.1)
  /var/log/messages ──── UDP syslog port 514 ────► Alloy loki.source.syslog
  /var/log/suricata/eve.json ──── rsync pull ────► /var/log/ipfire-eve/eve.json
                                                    ↓
                                             Alloy loki.source.file
                                                    ↓
                                                  Loki 3.6.0
                                                    ↓
                                              Grafana 12.4.1
```

### Pattern 2: Alloy River Configuration

**What:** Alloy uses a River configuration language (`.alloy` files). Pipeline is: source → process → write. Both syslog and file-read paths converge to a single `loki.write` endpoint.

```alloy
// === PATH A: UDP Syslog from IPFire (firewall drops, system events) ===

loki.source.syslog "ipfire_syslog" {
  listener {
    address                      = "0.0.0.0:514"
    protocol                     = "udp"
    use_incoming_timestamp       = true
    rfc3164_default_to_current_year = true
    syslog_format                = "rfc3164"
    max_message_length           = 0
    labels = {
      job      = "ipfire-syslog",
      host     = "ipfire",
    }
  }
  relabel_rules = loki.relabel.syslog_labels.rules
  forward_to    = [loki.process.firewall_parse.receiver]
}

// Retain __syslog_ labels as proper labels
loki.relabel "syslog_labels" {
  rule {
    source_labels = ["__syslog_message_hostname"]
    target_label  = "hostname"
  }
  rule {
    source_labels = ["__syslog_message_app_name"]
    target_label  = "app"
  }
}

// Parse FORWARDFW drops from syslog message body
loki.process "firewall_parse" {
  stage.regex {
    expression = `FORWARDFW.*SRC=(?P<src_ip>\d+\.\d+\.\d+\.\d+).*DST=(?P<dst_ip>\d+\.\d+\.\d+\.\d+).*PROTO=(?P<proto>\w+)`
  }
  stage.labels {
    values = {
      src_ip = "src_ip",
      proto  = "proto",
    }
  }
  forward_to = [loki.write.default.receiver]
}


// === PATH B: Suricata EVE JSON file-read (IDS alerts) ===

loki.source.file "suricata_eve" {
  targets = [
    {
      __path__ = "/var/log/ipfire-eve/eve.json",
      job      = "suricata-eve",
      host     = "ipfire",
    },
  ]
  tail_from_end = true
  forward_to    = [loki.process.eve_parse.receiver]
}

loki.process "eve_parse" {
  // Stage 1: Parse top-level EVE JSON fields
  stage.json {
    expressions = {
      event_type = "event_type",
      src_ip     = "src_ip",
      dest_ip    = "dest_ip",
      proto      = "proto",
      dest_port  = "dest_port",
      alert      = "alert",
    }
  }
  // Stage 2: Parse nested alert object
  stage.json {
    source = "alert"
    expressions = {
      signature    = "signature",
      category     = "category",
      severity     = "severity",
      signature_id = "signature_id",
    }
  }
  // Stage 3: Promote as Loki labels
  stage.labels {
    values = {
      event_type   = "event_type",
      src_ip       = "src_ip",
      proto        = "proto",
      dest_port    = "dest_port",
      signature    = "signature",
      category     = "category",
      severity     = "severity",
      signature_id = "signature_id",
    }
  }
  forward_to = [loki.write.default.receiver]
}


// === SHARED: Write to Loki ===

loki.write "default" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}
```

### Pattern 3: Loki Configuration (Single-Node Filesystem)

**What:** Single-node Loki with filesystem storage, TSDB schema v13, and compactor-based retention. The recommended configuration for SOHO scale.

```yaml
# loki-config.yml
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  instance_addr: 127.0.0.1
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory:  /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  retention_period: 720h   # 30 days global default
  max_query_series: 200000 # Required for Dashboard 22247 to function

compactor:
  working_directory:           /loki/compactor
  retention_enabled:           true
  retention_delete_delay:      2h
  retention_delete_worker_count: 150
  delete_request_store:        filesystem
  compaction_interval:         10m
```

### Pattern 4: Docker Compose Stack

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
      - ./loki/loki-config.yml:/etc/loki/loki-config.yml
      - loki-data:/loki
    restart: unless-stopped

  alloy:
    image: grafana/alloy:v1.14.1
    container_name: alloy
    user: root                          # Required to read /var/log/ipfire-eve/
    ports:
      - "514:514/udp"                   # Syslog receiver from IPFire
      - "12345:12345"                   # Alloy debugging UI
    volumes:
      - ./alloy/config.alloy:/etc/alloy/config.alloy
      - /var/log/ipfire-eve:/var/log/ipfire-eve:ro  # Rsync'd EVE JSON
    command:
      - run
      - --server.http.listen-addr=0.0.0.0:12345
      - --storage.path=/var/lib/alloy/data
      - /etc/alloy/config.alloy
    restart: unless-stopped
    depends_on:
      - loki

  prometheus:
    image: prom/prometheus:v3.10.0
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    restart: unless-stopped

  node-exporter:
    image: prom/node-exporter:v1.8.2
    container_name: node-exporter
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - --path.procfs=/host/proc
      - --path.sysfs=/host/sys
      - --collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)
    restart: unless-stopped

  grafana:
    image: grafana/grafana:12.4.1
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=changeme
      - GF_PATHS_PROVISIONING=/etc/grafana/provisioning
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning
      - ./grafana/dashboards:/var/lib/grafana/dashboards
      - grafana-data:/var/lib/grafana
    restart: unless-stopped
    depends_on:
      - loki
      - prometheus

volumes:
  loki-data:
  prometheus-data:
  grafana-data:
```

### Pattern 5: EVE JSON Delivery via Rsync-Pull

**What:** A cron job on the monitoring host pulls `/var/log/suricata/eve.json` from IPFire every 60 seconds using rsync over SSH with a dedicated read-only key. This is stateless (no persistent mount), pull-based (monitoring host initiates), and survives IPFire reboots.

**When to use:** Always — NFS is flagged as a security concern; SSH tunnel requires process management.

```bash
#!/bin/bash
# /opt/telemetry/scripts/rsync-eve.sh
# Run as cron on supportTAK-server: * * * * * /opt/telemetry/scripts/rsync-eve.sh

IPFIRE_IP="192.168.1.1"
IPFIRE_USER="root"
IPFIRE_KEY="/home/opsadmin/.ssh/eve_rsync_ed25519"   # Dedicated read-only key
REMOTE_PATH="/var/log/suricata/eve.json"
LOCAL_DIR="/var/log/ipfire-eve"
LOCAL_PATH="${LOCAL_DIR}/eve.json"

# Ensure staging directory exists
mkdir -p "${LOCAL_DIR}"

# Rsync: copy-only, no delete, SSH key auth
# --append-verify: append to local file, verify last bytes match
rsync -az \
  --append-verify \
  --timeout=30 \
  -e "ssh -i ${IPFIRE_KEY} -o StrictHostKeyChecking=yes -o ConnectTimeout=10" \
  "${IPFIRE_USER}@${IPFIRE_IP}:${REMOTE_PATH}" \
  "${LOCAL_PATH}" 2>/dev/null

# Log errors to syslog (not stdout — cron mails stdout)
if [ $? -ne 0 ]; then
  logger -t rsync-eve "WARNING: rsync from ${IPFIRE_IP}:${REMOTE_PATH} failed"
fi
```

**Dedicated SSH key setup:**
```bash
# On supportTAK-server: generate dedicated read-only key
ssh-keygen -t ed25519 -f /home/opsadmin/.ssh/eve_rsync_ed25519 -C "eve-rsync@supportTAK" -N ""

# On IPFire: add key with forced command (read-only restriction)
# Add to /root/.ssh/authorized_keys:
# command="cat /var/log/suricata/eve.json",no-port-forwarding,no-X11-forwarding,no-agent-forwarding ssh-ed25519 AAAA...

# Note: forced command approach blocks rsync (rsync requires its own server command)
# Alternative: use a separate SSH key restricted to rsync:
# command="/usr/bin/rsync --server --sender -az . /var/log/suricata/eve.json",no-port-forwarding ssh-ed25519 AAAA...
```

**Cron entry on supportTAK-server:**
```bash
# As opsadmin - add to crontab:
* * * * * /opt/telemetry/scripts/rsync-eve.sh
```

### Pattern 6: IPFire Syslog Configuration

**What:** Configure IPFire to forward syslog to the monitoring host. This is a WUI-only action with no IPFire CLI equivalent that persists across restarts.

**WUI path:** Logs > Log Settings

**Steps:**
1. Set "Syslog server" field to `192.168.1.101`
2. Set Protocol to UDP (TCP is not supported in current IPFire syslog daemon)
3. Save
4. Port 514 is hardcoded — cannot be changed via WUI

**What gets forwarded:** `/var/log/messages` content — includes iptables FORWARDFW kernel log lines (firewall drops), system daemon events, SSH auth events. Does NOT include Suricata EVE alert JSON.

**Firewall rule required:** The monitoring host must be allowed to receive UDP 514 inbound. On supportTAK-server Ubuntu 22.04 with ufw:
```bash
sudo ufw allow from 192.168.1.1 to any port 514 proto udp
# Or if ufw is not active, ensure iptables INPUT chain allows UDP 514
```

### Pattern 7: Grafana Provisioning

**What:** Pre-provision Loki and Prometheus datasources and dashboard 22247 so they are available immediately on first start.

```yaml
# grafana/provisioning/datasources/datasources.yml
apiVersion: 1
datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    isDefault: true
    jsonData:
      maxLines: 5000
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
```

```yaml
# grafana/provisioning/dashboards/dashboards.yml
apiVersion: 1
providers:
  - name: default
    type: file
    disableDeletion: false
    options:
      path: /var/lib/grafana/dashboards
```

Dashboard 22247 JSON must be downloaded from Grafana Labs and placed at `grafana/dashboards/suricata-22247.json`. Download URL: `https://grafana.com/api/dashboards/22247/revisions/latest/download`

### Anti-Patterns to Avoid

- **Promtail instead of Alloy:** Promtail reached EOL February 28, 2026. Do not use it.
- **NFS mount of /var/log/suricata from IPFire:** Security concern (noted in project STACK.md), stateful, mount can hang and block Alloy.
- **Relying on syslog for EVE JSON alerts:** IPFire's Suricata only sends engine start/stop meta-events to syslog. EVE alerts are exclusively in `/var/log/suricata/eve.json`.
- **Adding too many high-cardinality Loki labels:** Labels like `src_ip` and `dst_ip` create high-cardinality streams. Use src_ip only for EVE alerts (where it identifies attackers), not for all firewall log lines (too many unique IPs).
- **Running Docker on IPFire host:** Explicitly rejected by IPFire developers; compromises zone isolation.
- **Using `docker-compose` (v1) instead of `docker compose` (v2):** v1 is deprecated; Ubuntu 22.04 with Docker CE uses `docker compose` as a plugin.
- **Omitting `rfc3164_default_to_current_year: true`:** IPFire syslog uses RFC3164 which has no year in the timestamp. Without this setting, Alloy/Loki stores all timestamps as year 0000, breaking time-range queries.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Syslog reception on monitoring host | Custom UDP listener (Python/Go) | Alloy `loki.source.syslog` | Already in the stack; handles RFC3164/RFC5424 parsing, label extraction, forwarding |
| JSON log parsing | Custom jq pipeline | Alloy `loki.process` with `stage.json` | Built-in two-stage nested JSON extraction; handles partial records gracefully |
| Log storage and indexing | Custom SQLite/PostgreSQL schema | Loki 3.6.0 | Label-based indexing; LogQL built-in; 5-10x lighter than ELK; retention via compactor |
| Suricata alert visualization | Custom dashboard from scratch | Grafana dashboard 22247 | Community-maintained dashboard designed for EVE JSON labels; import in 30 seconds |
| IPFire metrics collection | SNMP scraping or custom exporter | Prometheus + node_exporter on monitoring host only (IPFire metrics deferred to v2) | node_exporter cannot install natively on IPFire; collectd bridge is non-trivial; SOHO scale works with monitoring host metrics only for Phase 5 |
| Log rotation handling | Custom scripts | Alloy position tracking + IPFire logrotate | Alloy tracks byte positions in a positions file; survives rotation automatically |

**Key insight:** The entire Phase 5 stack is off-the-shelf. The only custom element is the rsync-pull cron script (15 lines) and the Alloy regex for FORWARDFW log parsing. Everything else is configuration, not code.

---

## Critical EVE JSON Architecture Discovery

### The suricata-reporter Architecture in IPFire CU200

IPFire CU200 ships `suricata-reporter 0.6`. This process:

1. Reads EVE JSON events from a **second** eve-log output configured with `filetype: unix_dgram` pointing to `/var/run/suricata/reporter.socket`
2. Writes processed alerts to `/var/log/suricata/reporter.db` (SQLite)
3. `suricata-report-cron` (fcron daily) reads from `reporter.db` to generate email/PDF reports

The **primary eve-log output** (the one Phase 5 needs) uses `filetype: regular` writing to `/var/log/suricata/eve.json`. This is confirmed by the IPFire CU200 nopaste config diff (nopaste.ipfire.org/view/mKfhrhSu) which shows `filetype: regular` as the active setting with the comment `#regular|syslog|unix_dgram|unix_stream|redis`.

**Conclusion:** There are TWO eve-log outputs in CU200:
- Output 1: `filetype: regular` → `/var/log/suricata/eve.json` (the Phase 5 data source)
- Output 2: `filetype: unix_dgram` → `/var/run/suricata/reporter.socket` (reporter.db pipeline only)

The Phase 4 "critical discovery" that IPFire "uses `filetype: unix_dgram`" refers to the SECOND output used by the reporter — not the replacement of the primary file output. The fast.log and eve.json are still written normally. Phase 5 should target `/var/log/suricata/eve.json` as planned.

**Verification step (first task in Phase 5):** SSH to IPFire and run:
```bash
grep -A5 "eve-log:" /etc/suricata/suricata.yaml | grep filetype
# Expected: filetype: regular (primary output)
# May also see: filetype: unix_dgram (secondary reporter output)

ls -la /var/log/suricata/eve.json
tail -3 /var/log/suricata/eve.json | jq '.event_type'
# Expected: "dns", "flow", "alert" — file is actively written
```

---

## Common Pitfalls

### Pitfall 1: RFC3164 Timestamp Year = 0000

**What goes wrong:** Alloy receives IPFire syslog in RFC3164 format. RFC3164 does not include a year in the timestamp. Loki stores events at year 0000, breaking all time-range queries in Grafana. Dashboard shows "no data" for any time window.

**Why it happens:** Alloy's `loki.source.syslog` `rfc3164_default_to_current_year` defaults to `false`. Known issue documented in GitHub issue #2287 (December 2024).

**How to avoid:** Always set `rfc3164_default_to_current_year = true` AND `use_incoming_timestamp = true` together in the listener block.

**Warning signs:** Grafana shows no data; Loki query `{job="ipfire-syslog"}` returns results but with timestamps in year 0000.

### Pitfall 2: High-Cardinality Loki Labels from src_ip

**What goes wrong:** Adding `src_ip` as a Loki label on every syslog line (including firewall DROP entries) creates thousands of unique label combinations. Loki performance degrades. Query speed drops. Storage grows faster than expected.

**Why it happens:** Loki indexes by label — every unique label combination is a separate stream. High-cardinality labels (unique IPs) create enormous numbers of streams.

**How to avoid:**
- Apply `src_ip` label ONLY to EVE alert events (where tracking the attacking IP is the primary use case)
- For firewall syslog, extract `src_ip` as a structured metadata field (using `stage.structured_metadata`) rather than as a label, or leave it in the log line for LogQL regex extraction at query time
- Limit total distinct label values per label key to ~1000

**Warning signs:** Loki logs "stream limit exceeded" errors; query times increase beyond 5 seconds; Loki container RSS exceeds 1 GB.

### Pitfall 3: Alloy Cannot Read /var/log/ipfire-eve/ Without root

**What goes wrong:** Alloy container fails to tail `/var/log/ipfire-eve/eve.json` with "permission denied". No entries appear in Loki for the EVE stream.

**Why it happens:** The `/var/log/ipfire-eve/` directory is created by the rsync cron running as opsadmin. Default Docker containers run as non-root users. Alloy's `loki.source.file` needs read access to the file.

**How to avoid:** Set `user: root` in the Alloy Docker Compose service, OR set appropriate group ownership on `/var/log/ipfire-eve/` and use a non-root Alloy user that matches.

**Warning signs:** Alloy debugging UI (port 12345) shows `loki.source.file` component in error state; no EVE entries in Loki.

### Pitfall 4: Docker UDP Port 514 Binding Conflict

**What goes wrong:** Running `docker compose up` fails with "Bind for 0.0.0.0:514 failed: port is already allocated" or similar error.

**Why it happens:** Ubuntu 22.04 may have rsyslog running on the host and already bound to UDP 514. Docker cannot bind the port for Alloy.

**How to avoid:** Check before deploying: `sudo ss -ulnp | grep 514`. If rsyslog is listening, either:
1. Disable rsyslog host syslog listener (`sudo systemctl stop rsyslog`) and reconfigure Alloy to use port 514, OR
2. Configure IPFire to send to a non-standard port (requires manual `/etc/syslog.conf` edit on IPFire that reverts on restart — not recommended), OR
3. Move Alloy syslog listener to port 1514 and use iptables REDIRECT to map host UDP 514 to container port 1514.

**Warning signs:** `docker compose up` fails with port binding error.

### Pitfall 5: Loki max_query_series Limit Blocks Dashboard 22247

**What goes wrong:** Dashboard 22247 loads but panels show "maximum of series limit reached" error. Alert severity breakdown and top attackers panels show no data.

**Why it happens:** Loki's default `max_query_series` is 500. Dashboard 22247 uses topk() queries that can match thousands of series when `src_ip` is a label.

**How to avoid:** Set `max_query_series: 200000` in the `limits_config` section of `loki-config.yml`. This was discovered as a required change by the community blog reference (hardill.me.uk, January 2025).

**Warning signs:** Panels show partial data or error messages about series limits; logcli queries succeed from CLI but dashboard shows limits.

### Pitfall 6: Rsync Appends to Rotated File

**What goes wrong:** After IPFire's logrotate rotates `eve.json`, rsync `--append-verify` may attempt to append to a local file whose content no longer matches the rotated remote source, causing checksum errors or duplicate entries.

**Why it happens:** `--append-verify` compares last bytes before appending; if IPFire rotates to `eve.json.1` and starts a new `eve.json`, the rsync next run downloads the fresh short file but local copy is the old large file.

**How to avoid:** Use `--checksum` instead of `--append-verify` — rsync will detect the local vs remote differ and overwrite. Or run rsync without append flags and rely on Alloy's position tracking to avoid re-reading already-ingested lines.

**Warning signs:** Alloy ingests duplicate EVE entries; alert counts spike artificially after IPFire midnight logrotate.

---

## Code Examples

### Verify Stack Health After Deploy

```bash
# Source: Standard Docker Compose operations
# Run on supportTAK-server as opsadmin

# Check all containers are running
docker compose -f /opt/telemetry/docker-compose.yml ps

# Check Loki readiness
curl -s http://localhost:3100/ready
# Expected: "ready"

# Check Alloy UI (debugging pipeline visualization)
# Open in browser: http://192.168.1.101:12345

# Send a test syslog message (simulate IPFire)
logger -n 192.168.1.101 -P 514 --udp "test FORWARDFW DROP SRC=1.2.3.4 DST=192.168.1.100 PROTO=TCP"

# Query Loki for the test message (within 60 seconds)
curl -s -G 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={job="ipfire-syslog"}' \
  --data-urlencode 'limit=5' | jq '.data.result[0].values[-1][1]'
```

### Verify EVE JSON Ingest

```bash
# Source: Grafana Alloy loki.source.file documentation
# Run on supportTAK-server after rsync has populated /var/log/ipfire-eve/eve.json

# Check rsync is working
ls -la /var/log/ipfire-eve/eve.json
# File should exist and mtime should update every ~60 seconds

# Trigger a test alert on IPFire (run on IPFire via SSH)
# ssh -i C:\Users\ablan\.ssh\ipfire_ed25519 root@192.168.1.1
# curl -s http://testmynids.org/uid/index.html

# Wait 90 seconds (60s for rsync + 30s for Alloy to pick up new lines)

# Query Loki for EVE alerts
curl -s -G 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={job="suricata-eve", event_type="alert"}' \
  --data-urlencode 'limit=5' | jq '.data.result[0].values[-1][1]'
# Expected: JSON EVE alert entry with signature_id 2100498
```

### LogQL: Firewall Drop Time-Series (DASH-02)

```logql
# Source: Project-specific, based on IPFire syslog FORWARDFW format
# Panel type: Time series (bar chart)

# Count firewall drops per minute
sum(count_over_time({job="ipfire-syslog"} |= "FORWARDFW" [1m]))
```

### LogQL: Top Blocked Source IPs (DASH-04)

```logql
# Source: Project-specific, based on Loki LogQL documentation
# Panel type: Table

# Top 10 source IPs in FORWARDFW drops (extracts from log line at query time)
topk(10,
  sum by (src_ip) (
    count_over_time(
      {job="ipfire-syslog"} |= "FORWARDFW"
      | regexp `SRC=(?P<src_ip>\d+\.\d+\.\d+\.\d+)`
      [1h]
    )
  )
)
```

### LogQL: Top Triggered Suricata Rules (DASH-04)

```logql
# Source: Project-specific, using signature label from Alloy pipeline
# Panel type: Table

topk(10,
  sum by (signature) (
    count_over_time({job="suricata-eve", event_type="alert"}[1h])
  )
)
```

### LogQL: Threat Trace Correlation (DASH-01)

```logql
# Source: Project-specific — correlate EVE alert with firewall DROP from same src_ip
# Panel type: Logs (combined stream view)

# This query shows all log entries (firewall or IDS) involving the same IP
{job=~"ipfire-syslog|suricata-eve"} |= "203.0.113.42"
```

### Alloy Config: Preserve RFC3164 Syslog Headers as Labels

```alloy
// Source: Grafana Alloy loki.source.syslog documentation + GitHub issue #2287
// Critical: rfc3164_default_to_current_year prevents year=0000 timestamps

loki.relabel "syslog_relabel" {
  rule {
    source_labels = ["__syslog_message_hostname"]
    target_label  = "hostname"
  }
  rule {
    source_labels = ["__syslog_message_severity"]
    target_label  = "severity"
  }
  rule {
    source_labels = ["__syslog_message_app_name"]
    target_label  = "app"
  }
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|-----------------|--------------|--------|
| Promtail as log agent | Grafana Alloy 1.14.1 | EOL Feb 28, 2026 | Alloy is mandatory. Promtail configs can be migrated via official Alloy migration tool. |
| Grafana Agent Flow | Grafana Alloy | EOL Oct 31, 2025 | Alloy is the unified replacement for both Promtail and Grafana Agent. |
| Loki BoltDB-Shipper | Loki TSDB schema v13 | Loki 2.8+ (2022), stable in 3.x | TSDB is faster, has better compaction. Use schema v13 in loki-config.yml. |
| loki.source.syslog without rfc3164_default_to_current_year | Add rfc3164_default_to_current_year = true | Alloy after 2024 (issue #2287) | Without this, all RFC3164 timestamps stored as year 0000. |
| IPFire Promtail/EveBox on-box | Off-box Alloy + Loki | Always for IPFire | Docker is rejected by IPFire developers. Off-box is the only supported path. |
| dashboard 12637 (pfSense/IDS) | dashboard 22247 (Suricata EVE JSON) | 2023-2024 | 22247 is specifically designed for EVE JSON labels from Loki pipeline. 12637 requires more label remapping. |

**Deprecated/outdated:**
- Promtail: EOL February 28, 2026. All documentation referencing Promtail is stale.
- Grafana Agent Static/Flow: EOL October 31, 2025.
- Loki BoltDB-Shipper: Legacy. Use TSDB schema v13 for new deployments.
- Docker Compose v1 (`docker-compose` binary): Deprecated. Use `docker compose` (v2 plugin).

---

## Open Questions

1. **Exact suricata.yaml two-output configuration on live CU200**
   - What we know: The IPFire nopaste diff shows `filetype: regular` as the primary eve-log. CU200 release notes confirm `suricata-reporter 0.6`. A second `unix_dgram` output for the reporter socket likely exists as a separate eve-log block.
   - What's unclear: Whether the live CU200 suricata.yaml has ONE eve-log block (filetype: regular) or TWO (one regular + one unix_dgram). The Phase 4 critical discovery suggests two outputs exist.
   - Recommendation: First SSH verification task in Phase 5 Wave 1 — count eve-log blocks in suricata.yaml: `grep -c "eve-log:" /etc/suricata/suricata.yaml`. If two blocks, identify which uses unix_dgram and which uses regular. Confirm `/var/log/suricata/eve.json` is actively receiving entries.

2. **fast.log as fallback if eve.json is empty**
   - What we know: fast.log is confirmed active in Phase 4. It uses a simpler one-line format: `[timestamp] [1:SID:rev] SIGNATURE [Priority: N] {PROTO} SRC:port -> DST:port`
   - What's unclear: Whether fast.log provides enough structure for Loki labels (requires regex extraction vs EVE JSON's native structure).
   - Recommendation: If eve.json is empty after Phase 4 verification, Phase 5 Plan 01 should add an Alloy `loki.source.file` target for `fast.log` as a temporary fallback with regex parsing, while the EVE JSON issue is diagnosed.

3. **rsync SSH key restricted command compatibility**
   - What we know: The standard approach for read-only rsync restriction uses a `command=` line in authorized_keys. However, rsync requires its own server-side `rsync --server` command, which conflicts with a simple `cat` forced command.
   - What's unclear: Whether IPFire's sshd version supports the rsync-restricted command syntax (`command="/usr/bin/rsync --server --sender -az . /var/log/suricata/eve.json"`) correctly.
   - Recommendation: Test on live system. If restricted command is too complex, use an alternative: create a dedicated `eve-reader` shell user on IPFire with access only to `/var/log/suricata/` directory (read-only), using standard SSH key without forced command but with AllowUsers restriction in sshd_config (via `/etc/ssh/sshd_config.d/` drop-in if supported, or document as manual step).

4. **Loki storage sizing for 30-day EVE retention**
   - What we know: EVE JSON generates 10-100 MB/day at SOHO scale (from project ARCHITECTURE.md). Loki's label-based compression is typically 10:1 for structured log data.
   - What's unclear: Exact disk usage for 30 days of EVE JSON + firewall syslog on the supportTAK-server. The server has unknown disk capacity.
   - Recommendation: Check disk on supportTAK-server before deploying: `df -h /`. Plan for 30 days at 100 MB/day uncompressed = ~300 MB compressed. If disk is limited, use a 14-day retention default and document how to adjust.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | bash shell scripts (same pattern as Phases 1-4) |
| Config file | none — standalone scripts in `scripts/` |
| Quick run command | `bash scripts/validate-phase5.sh` (run from dev machine or supportTAK-server) |
| Full suite command | `bash scripts/validate-phase5.sh --full` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | Notes |
|--------|----------|-----------|-------------------|-------|
| TEL-01 | IPFire syslog forwarding configured to 192.168.1.101 UDP 514 | smoke | `ssh root@192.168.1.1 'grep -i "syslog" /etc/syslog.conf \| grep 192.168.1.101'` | WUI-configured; verify from syslog.conf content |
| TEL-02 | IPS syslog entry arriving at monitoring host | smoke | `timeout 5 nc -u -l 514 \| grep -c "suricata\|kernel" \| test ... -gt 0` | SKIP if cannot bind 514 (rsyslog conflict) |
| TEL-03 | Docker Compose stack running (all 5 containers) | smoke | `docker compose -f /opt/telemetry/docker-compose.yml ps \| grep -c "running"` | FAIL if count < 5 |
| TEL-04 | Alloy receiving syslog entries and EVE JSON | smoke | `curl -s http://localhost:3100/loki/api/v1/query_range?query={job="ipfire-syslog"}&limit=1 \| jq '.data.resultType'` | FAIL if no results |
| TEL-05 | Loki ingesting and storing logs | smoke | `curl -s http://localhost:3100/ready \| grep -q ready` | FAIL if not ready |
| TEL-06 | Grafana accessible and datasources healthy | smoke | `curl -s -u admin:changeme http://localhost:3000/api/datasources \| jq '.[].name'` | FAIL if Loki not listed |
| TEL-07 | Phased ingest order validated | integration | Manual — syslog arrives before EVE stream is confirmed | SKIP (ordering is a deployment procedure) |
| TEL-08 | Loki retention configured | smoke | `grep -q "retention_period" /opt/telemetry/loki/loki-config.yml` | FAIL if not found |
| DASH-01 | Threat trace panel returns data for known test alert | integration | Run testmynids.org on IPFire, wait 90s, query LogQL correlation | SKIP if no live traffic |
| DASH-02 | Firewall drops time-series panel populated | smoke | `curl -s -G 'http://localhost:3100/loki/api/v1/query' --data-urlencode 'query=count_over_time({job="ipfire-syslog"} \|= "FORWARDFW" [1h])' \| jq '.data.result\|length \|. > 0'` | SKIP if no traffic yet |
| DASH-03 | Dashboard 22247 imported and panels load | smoke | `curl -s -u admin:changeme http://localhost:3000/api/dashboards/uid/22247 \| jq '.dashboard.title'` | FAIL if dashboard not found |
| DASH-04 | Top blocked IPs query returns results | smoke | `curl -s -G 'http://localhost:3100/loki/api/v1/query' --data-urlencode 'query=topk(5,sum by (src_ip)(count_over_time({job="suricata-eve",event_type="alert"}[24h])))' \| jq '.data.result\|length'` | SKIP if less than 1h of data |

### Sampling Rate

- **Per task commit:** `bash scripts/validate-phase5.sh` (TEL-03, TEL-05, TEL-06, TEL-08 quick checks)
- **Per wave merge:** Full suite including EVE JSON ingest verification
- **Phase gate:** Full suite green before marking Phase 5 complete

### Wave 0 Gaps

- [ ] `scripts/validate-phase5.sh` — covers TEL-01 through TEL-08 and DASH-01 through DASH-04
- [ ] `/opt/telemetry/` directory on supportTAK-server — created during Wave 1
- [ ] `/var/log/ipfire-eve/` directory on supportTAK-server — created by rsync script setup
- [ ] Dashboard 22247 JSON file download — required before Wave 3

---

## Sources

### Primary (HIGH confidence)

- [Grafana Alloy v1.14.1 Release](https://github.com/grafana/alloy/releases) — Current stable March 17, 2026. Version confirmed.
- [Grafana Alloy loki.source.syslog Documentation](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.syslog/) — RFC3164 support, rfc3164_default_to_current_year option, relabel_rules for __syslog_ labels
- [Grafana Alloy loki.source.file Documentation](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.file/) — tail_from_end, __path__ label, position tracking, logrotate behavior
- [Grafana Alloy loki.process Documentation](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.process/) — stage.json two-stage nested parsing, stage.labels, stage.regex
- [Grafana Loki v3.6 Release Notes](https://grafana.com/docs/loki/latest/release-notes/v3-6/) — TSDB schema v13, compactor retention config
- [Grafana Loki Log Retention Documentation](https://grafana.com/docs/loki/latest/operations/storage/retention/) — limits_config.retention_period, compactor settings
- [Grafana Loki Docker Install Documentation](https://grafana.com/docs/loki/latest/setup/install/docker/) — Official Docker Compose examples for v3.6.0
- [IPFire Log Settings (WUI)](https://www.ipfire.org/docs/configuration/logs/logsettings) — UDP-only syslog, port 514 hardcoded, WUI path: Logs > Log Settings
- [IPFire CU200 Release Notes](https://www.ipfire.org/blog/ipfire-2-29-core-update-200-released) — suricata-reporter 0.6 confirmed, SQLite 3.51.100, reporter generates email/PDF reports from alerts
- [IPFire Nopaste CU200 suricata.yaml diff](https://nopaste.ipfire.org/view/mKfhrhSu) — Confirms `filetype: regular` for primary eve-log, `filename: eve.json`
- [Suricata EVE JSON Output Documentation](https://docs.suricata.io/en/latest/output/eve/eve-json-output.html) — All filetype options (regular, unix_dgram, unix_stream, syslog, redis)
- [Suricata Logs Eve JSON Dashboard 22247](https://grafana.com/grafana/dashboards/22247-suricata-logs-json/) — Required labels: event_type, src_ip, proto, dest_port, signature, category, severity, signature_id

### Secondary (MEDIUM confidence)

- [GitHub Issue #2287: loki.source.syslog rfc3164 timestamp not parsed](https://github.com/grafana/alloy/issues/2287) — RFC3164 year=0000 bug documented December 2024; rfc3164_default_to_current_year fix confirmed
- [Network Monitoring and IDS blog post (January 2025)](https://blog.hardill.me.uk/2025/01/11/network-monitoring-and-intrusion-detection/) — Promtail (Alloy equivalent) pipeline for Suricata EVE JSON; max_query_series: 200000 required for dashboard 22247
- [IPFire Community: suricata-report-cron in CU200](https://community.ipfire.org/t/usr-bin/suricata-report-cron-in-cu-200/15543) — reporter.db schema confirmed (alerts table with JSON event field); reporter reads from unix_dgram socket; CU200 introduced DNS query field issues
- [IPFire Community: IPS Suricata does not log into syslog](https://community.ipfire.org/t/ips-suricata-does-not-log-into-syslog/9302) — Confirmed: EVE alerts never in syslog on IPFire; file-read mandatory
- [Blog: elhacker.net Grafana Suricata EVE JSON (November 2024)](https://blog.elhacker.net/2024/11/visualizar-con-grafana-los-eventos-del-ids-suricata-eve-json.html) — Promtail pipeline config showing two-stage JSON extraction for dashboard 22247 labels (direct Alloy equivalent)
- [Grafana Alloy GitHub: loki.source.syslog RFC3164 config example](https://community.grafana.com/t/labeling-required-to-receive-syslog-data-and-forward-to-loki/145318) — Working UDP RFC3164 listener config with relabel_rules

### Tertiary (LOW confidence — require live system verification)

- suricata.yaml two-output architecture (regular + unix_dgram) on live CU200 — inferred from CU200 release notes + nopaste diff + community reporter.db discussion; exact suricata.yaml block count requires on-system grep
- rsync SSH forced-command compatibility with IPFire sshd — standard approach, but IPFire's sshd_config.d/ drop-in support unverified
- Disk usage projection for Loki 30-day retention on supportTAK-server — estimated from general Suricata traffic volume guidance; actual disk capacity of supportTAK-server unknown

---

## Metadata

**Confidence breakdown:**
- Docker Compose stack (versions, config): HIGH — all versions verified from official GitHub releases March 2026
- Alloy River configuration (syslog path, file path): HIGH — directly from official Alloy docs; RFC3164 year fix verified from GitHub issue
- Loki configuration (retention, schema): HIGH — from official Loki docs
- EVE JSON delivery path (rsync-pull): MEDIUM — pattern is well-established; IPFire-specific rsync key restriction requires live verification
- suricata-reporter / two-output architecture: MEDIUM — confirmed from CU200 release notes and community thread; exact suricata.yaml structure requires live grep
- Dashboard 22247 label requirements: HIGH — multiple sources confirm same label set (event_type, src_ip, proto, dest_port, signature, category, severity, signature_id)

**Research date:** 2026-03-23
**Valid until:** 2026-04-23 (30 days for stable stack; IPFire CU201 may change suricata-reporter behavior)
