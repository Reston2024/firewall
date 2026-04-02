# Phase 10: Telemetry Migration to Malcolm — Research

**Researched:** 2026-04-02
**Domain:** Filebeat Suricata module, Malcolm Logstash ingestion, rsyslog/Malcolm syslog port conflict, Loki decommission
**Confidence:** HIGH (Malcolm syslog/Beats configuration verified via official docs and GitHub); HIGH (Filebeat Suricata module — stable documented path); MEDIUM (EVE JSON delivery via Filebeat without native SSH — requires indirect approach)

---

## Summary

Phase 10 is a migration phase: IPFire's Suricata EVE JSON and syslog must flow into Malcolm's OpenSearch instead of Loki/Alloy, the Loki stack must be decommissioned, and validation scripts must reflect the new architecture. Malcolm is already running with 27 containers healthy (Phase 9 outcome). This phase wires the data.

The two core data paths are: (1) Filebeat with the Suricata module ships EVE JSON from supportTAK-server to Malcolm Logstash at TCP :5044 — this is the documented Malcolm "external beats forwarder" path; (2) IPFire rsyslog forwards syslog to supportTAK-server UDP :514, but rsyslog currently holds that port. The resolution is to configure Malcolm's internal Filebeat syslog listener on a non-standard port (e.g., UDP :5514), then redirect rsyslog's output from writing a file to forwarding to :5514 — OR to reconfigure IPFire's syslog target to a different port (which IPFire does not natively support since port 514 is hardcoded in the WUI). This is the primary complexity of the phase.

The decommission sequence must be: validate Malcolm is receiving data in parallel → archive Loki data → stop Loki stack → free the 1.7GB swap + ~500MB RAM. Doing this in the wrong order creates a telemetry dark period.

**Primary recommendation:** Configure Malcolm's Filebeat syslog listener on UDP :5514 (not :514). Reconfigure rsyslog on supportTAK-server to forward to localhost :5514 instead of writing to a file. IPFire continues forwarding to :514 on supportTAK-server (unchanged WUI config). This avoids any IPFire changes and resolves the port conflict with a relay-style redirect.

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MAL-02 | Suricata EVE JSON from IPFire ingested into Malcolm via Filebeat with Suricata module | Filebeat Suricata module ships EVE JSON to Malcolm Logstash :5044 — documented Malcolm ingestion path |
| MAL-03 | IPFire syslog forwarded to Malcolm Logstash replacing the rsyslog→Alloy→Loki path | rsyslog relay pattern: rsyslog receives :514, forwards to Malcolm Filebeat syslog listener at :5514 |
| MIG-01 | Parallel validation window (2-4 weeks) where both Loki and Malcolm ingest simultaneously | RAM budget analysis shows Loki (~250MB) can run alongside Malcolm (~12.5GB) — tight but feasible short-term |
| MIG-02 | Loki/Alloy/Grafana/Prometheus Docker Compose stack decommissioned after Malcolm validation | docker compose down at /opt/telemetry; remove volumes; verify only Malcolm containers in docker ps |
| MIG-03 | validate-phase5.sh updated to check Malcolm endpoints instead of Loki/Grafana | Replace Loki/Grafana API checks with Malcolm nginx :443 + OpenSearch index count checks |
| MIG-04 | Telemetry runbook updated for Malcolm architecture (replaces Loki-era runbook) | Full runbook rewrite: Filebeat-to-Malcolm path, rsyslog relay config, decommission steps |
</phase_requirements>

---

## Standard Stack

### Core — Phase 10 Components

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Filebeat (Elastic) | 8.x (match Malcolm's bundled version) | Ships EVE JSON to Malcolm Logstash Beats :5044 with Suricata module | Malcolm's documented external forwarder path; Suricata module parses EVE JSON natively |
| Malcolm Filebeat (internal) | Bundled in Malcolm | Receives syslog via configurable UDP/TCP port (FILEBEAT_SYSLOG_UDP_PORT in filebeat.env) | Already running inside Malcolm; just needs port config and exposure |
| rsyslog | System default (Ubuntu 22.04) | Relay: receives IPFire UDP :514, forwards to Malcolm's syslog listener | Already installed and running on supportTAK-server; becomes a relay not a file writer |
| Malcolm Logstash | Bundled in Malcolm v26.02.0 | Ingests Beats (Filebeat Suricata module output) on TCP :5044 | Already running; requires port to be exposed externally |
| Malcolm OpenSearch | 3.5.0 (bundled) | Indexes all ingested events; provides dashboards | Already running with ISM policy and 27 containers healthy |

### EVE JSON Delivery Architecture Choices

Three approaches for getting EVE JSON from IPFire into Filebeat on supportTAK-server:

| Approach | Method | Pros | Cons | Recommendation |
|----------|--------|------|------|---------------|
| **A: SCP pull cron (keep existing pattern)** | cron on supportTAK-server SCPs eve.json from IPFire to local file; Filebeat tails local copy | Proven from v1.0; no new SSH setup needed | 60s latency; file rotation complexity | **Recommended for Phase 10** |
| B: Filebeat with `input.type: filestream` + SSH plugin | Filebeat native SSH file tailing | Single tool; real-time | Filebeat SSH plugin is experimental; adds complexity | Defer |
| C: rsync cron (replacing SCP cron) | rsync instead of scp | Better incremental sync; handles rotation | rsync not available on IPFire (only basic tools) | Not viable — IPFire lacks rsync |

**Decision: Keep the SCP pull pattern from v1.0 (already proven).** cron on supportTAK-server SCPs `/var/log/suricata/eve.json` from IPFire (root@192.168.1.1) to `/var/log/ipfire-eve/eve.json` every 60 seconds. Filebeat tails the local copy with the Suricata module. This is functionally identical to what Alloy was doing in v1.0, just shipping to Logstash :5044 instead of to Loki.

### Syslog Relay Architecture (Port Conflict Resolution)

**Problem:** IPFire hardcodes syslog forwarding to UDP :514 (WUI does not expose port selection). rsyslog on supportTAK-server currently holds UDP :514. Malcolm's internal Filebeat syslog listener also defaults to UDP :514. Three things want the same port.

**Resolution (recommended):**

```
IPFire rsyslog → UDP :514 → supportTAK rsyslog (existing — no change to IPFire)
supportTAK rsyslog → UDP :5514 → Malcolm Filebeat syslog listener (new redirect)
```

This approach:
1. Leaves IPFire WUI syslog configuration completely unchanged (still forwards to 192.168.1.22 UDP :514)
2. Keeps rsyslog on supportTAK-server as the :514 receiver (no port conflict)
3. Configures Malcolm's `FILEBEAT_SYSLOG_UDP_PORT=5514` in `/opt/malcolm/config/filebeat.env`
4. Adds an rsyslog forwarding rule to relay received syslog to localhost :5514

Malcolm's syslog listener is part of its internal Filebeat container. The port is set via `FILEBEAT_SYSLOG_UDP_PORT` in `/opt/malcolm/config/filebeat.env`. The port must also be exposed in Malcolm's Docker Compose network config (or the Malcolm configure script exposes it when syslog acceptance is enabled).

**Installation summary:**
```bash
# No new packages — existing tools reused
# Filebeat for EVE JSON — install system Filebeat alongside Malcolm's internal Filebeat:
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elastic.gpg
echo "deb [signed-by=/usr/share/keyrings/elastic.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list
sudo apt update && sudo apt install filebeat
```

**Version verification:** Filebeat version should match the version bundled in Malcolm v26.02.0 to avoid Beats protocol mismatches. Check with: `docker exec malcolm-filebeat-1 filebeat version`.

---

## Architecture Patterns

### Pattern 1: EVE JSON Path (Filebeat Suricata Module → Malcolm Logstash)

```
IPFire /var/log/suricata/eve.json
    ↓ SCP cron (60s, existing SSH key)
supportTAK /var/log/ipfire-eve/eve.json
    ↓ Filebeat (system service, Suricata module)
Malcolm Logstash :5044 (TCP, Beats protocol)
    ↓
Malcolm OpenSearch arkime_sessions3-* / network-* indices
    ↓
Malcolm OpenSearch Dashboards (Suricata Alerts dashboard)
```

**Filebeat configuration for EVE JSON:**
```yaml
# /etc/filebeat/filebeat.yml
filebeat.modules:
  - module: suricata
    eve:
      enabled: true
      var.paths:
        - /var/log/ipfire-eve/eve.json

output.logstash:
  hosts: ["localhost:5044"]

# Malcolm Logstash is in the same Docker network exposed on host :5044
# If Malcolm Logstash exposes port externally, use: ["192.168.1.22:5044"]
# Check: docker compose -f /opt/malcolm/docker-compose.yml ps | grep logstash
```

**Malcolm Logstash port exposure:** The Malcolm configure script asks "Expose Logstash Beats port to external hosts?" During Phase 9, this may or may not have been enabled. If the system Filebeat is on the same host as Malcolm, it can connect to the Docker container's host-mapped port. Verify with: `ss -tlnp | grep 5044`.

### Pattern 2: Syslog Path (rsyslog Relay → Malcolm Filebeat)

```
IPFire syslog (BusyBox, RFC3164, UDP)
    ↓ UDP :514 (WUI config — unchanged)
supportTAK rsyslog :514 (existing receiver — no change)
    ↓ UDP :5514 (new omfwd rule in rsyslog)
Malcolm Filebeat syslog listener :5514 (FILEBEAT_SYSLOG_UDP_PORT=5514)
    ↓
Malcolm Logstash
    ↓
Malcolm OpenSearch
```

**rsyslog configuration to forward to Malcolm:**
```conf
# /etc/rsyslog.d/20-malcolm-forward.conf
# Forward all received syslog to Malcolm's Filebeat syslog listener
*.* @127.0.0.1:5514
```

**Malcolm filebeat.env configuration:**
```bash
# /opt/malcolm/config/filebeat.env
FILEBEAT_SYSLOG_UDP_LISTEN=true
FILEBEAT_SYSLOG_UDP_PORT=5514
FILEBEAT_SYSLOG_UDP_FORMAT=auto
```

After editing filebeat.env, Malcolm must be restarted to apply:
```bash
cd /opt/malcolm && docker compose restart filebeat
```

### Pattern 3: Parallel Validation Window (MIG-01)

Run both stacks simultaneously for 2-4 weeks before decommissioning Loki:

```
IPFire syslog → rsyslog :514 → [BOTH]
    A) File /var/log/ipfire/syslog.log → Alloy → Loki (EXISTING, keep during validation)
    B) rsyslog forward → Malcolm Filebeat :5514 → Malcolm (NEW)

IPFire eve.json → SCP cron → /var/log/ipfire-eve/eve.json → [BOTH]
    A) Alloy file tail → Loki (EXISTING)
    B) Filebeat Suricata module → Malcolm Logstash (NEW)
```

RAM budget during parallel validation:
| Stack | RAM |
|-------|-----|
| Malcolm (running) | ~12.5GB |
| Loki (existing) | ~250MB |
| Alloy (existing) | ~200MB |
| Grafana (existing) | ~256MB |
| Prometheus (existing) | ~200MB |
| **Total** | **~13.4GB** |

This is within the 16GB limit with ~2.6GB headroom. **Dual-stack parallel validation is RAM-viable.** The 6GB swap provides additional safety.

### Pattern 4: Decommission Sequence (MIG-02)

**Order is critical:**
1. Validate Malcolm is receiving EVE JSON (see success criteria — live alert within 5 min of test scan)
2. Validate Malcolm is receiving syslog (FORWARDFW, CUSTOMINPUT, GUARDIAN appear in OpenSearch)
3. Archive: export last 7 days of EVE JSON from Loki to flat files (optional but good practice)
4. Document data break in ADR: "Loki historical data (dates) not migrated to OpenSearch — accepted."
5. Stop rsyslog-to-file path (update rsyslog config — remove file output for ipfire stream)
6. `docker compose -f /opt/telemetry/docker-compose.yml down -v` (stops and removes volumes)
7. Verify: `docker ps | grep -E 'loki|alloy|grafana|prometheus'` returns empty
8. Reclaim disk: `sudo rm -rf /opt/telemetry/loki/data/ /opt/telemetry/prometheus/data/`

**Do NOT:**
- Stop Alloy before Filebeat Suricata module is confirmed shipping to Malcolm
- Remove the SCP cron until Filebeat is confirmed reading from the local eve.json
- Run decommission if Malcolm container restart count is non-zero (unstable)

### Recommended Project Structure (Phase 10 deliverables)

```
scripts/
├── validate-phase5.sh      # REPLACE — new Malcolm validation script
telemetry/
├── docker-compose.yml      # DECOMMISSION — stop and remove
├── alloy/                  # DECOMMISSION
└── loki/                   # DECOMMISSION
telemetry-malcolm/          # NEW directory (or update telemetry/)
├── filebeat/
│   └── filebeat.yml        # External Filebeat Suricata module config
└── rsyslog/
    └── 20-malcolm-forward.conf  # rsyslog forward-to-Malcolm rule
docs/
└── telemetry-deployment-runbook.md  # REPLACE with Malcolm architecture runbook
```

### Anti-Patterns to Avoid

- **Trying to change IPFire's syslog destination port:** IPFire WUI hardcodes UDP :514. Editing `/etc/syslog.conf` on IPFire is overwritten on restart. Do not attempt.
- **Pointing Filebeat at eve.json directly on IPFire:** IPFire lacks Filebeat. Filebeat with SSH file input is experimental and unreliable. Keep SCP pull pattern.
- **Running Malcolm Logstash on the default container-internal network:** External Filebeat cannot reach internal Docker Logstash without host port exposure. Verify `5044/tcp` is in `ss -tlnp` output on supportTAK-server.
- **Decommissioning Loki before Malcolm validation:** 2-4 week parallel window exists for a reason. The decommission is one-way — historical Loki data cannot be recovered once volumes are removed.
- **Using Malcolm's internal Filebeat (in Docker) to read host filesystem files:** Malcolm's internal Filebeat runs inside Docker and cannot access `/var/log/ipfire-eve/` on the host without a volume mount change. Install a separate system-level Filebeat for EVE JSON, OR mount the directory into Malcolm's Filebeat container. System-level Filebeat is simpler and avoids Malcolm container changes.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Syslog parsing (FORWARDFW format, RFC3164) | Custom parser | rsyslog native + Malcolm Filebeat with `auto` format | rsyslog handles IPFire's non-standard BusyBox syslog; Malcolm Filebeat auto-detects RFC3164/RFC5424 |
| EVE JSON parsing | Custom JSON parser | Filebeat Suricata module | Native Suricata EVE schema parsing, field extraction, timestamp normalization — tested against Suricata 8.x |
| Beats protocol to Logstash | Custom TCP forwarder | Filebeat | Beats protocol has ACK, compression, TLS, backpressure handling — critical for reliability |
| Validation script logic | Rewrite from scratch | Update validate-phase9.sh as base | Phase 9 script already has Malcolm API patterns, SSH credential discovery, container health checks |
| Log archival before cutover | Complex export pipeline | Simple LogQL range export via Loki API + save to file | Limited duration (7 days), no need to migrate to OpenSearch |

**Key insight:** Both EVE JSON and syslog are well-solved problems in the Elastic ecosystem. The Filebeat Suricata module handles EVE JSON with zero custom code. Malcolm's Filebeat syslog listener handles syslog with a config change. The only custom work is glue: rsyslog forwarding rule, Filebeat yaml config, and the validation script.

---

## Common Pitfalls

### Pitfall 1: Malcolm Logstash Port 5044 Not Exposed to Host

**What goes wrong:** System Filebeat on supportTAK-server tries to connect to `localhost:5044` but the Malcolm Logstash container only exposes port 5044 internally within the Docker network. Connection refused.

**Why it happens:** Malcolm's configure script asks whether to "expose Logstash port to external hosts" — if answered No (default for security), port 5044 is not bound on the host interface.

**How to avoid:** Before installing Filebeat, verify: `ss -tlnp | grep 5044` on supportTAK-server. If empty, the port is not host-exposed. Fix: in Malcolm's `docker-compose.yml`, ensure the logstash service has `ports: ["5044:5044"]`, then `docker compose up -d --no-deps logstash` to restart only Logstash with the new port binding. Alternatively, run the Malcolm configure wizard again and answer Y to expose Logstash.

**Warning signs:** `filebeat -e` output shows "connection refused" to localhost:5044; Malcolm's Logstash container shows no incoming connection logs.

### Pitfall 2: rsyslog on supportTAK-server Cannot Forward UDP to Malcolm's Port 5514

**What goes wrong:** The rsyslog `omfwd` module is used for forwarding. `@127.0.0.1:5514` syntax sends UDP to localhost :5514. If Malcolm's Filebeat container is not bound to `0.0.0.0:5514` (only container-internal network), UDP packets are dropped silently.

**Why it happens:** Malcolm's Filebeat syslog listener port must be exposed in Docker Compose with a host binding. Setting `FILEBEAT_SYSLOG_UDP_PORT=5514` in filebeat.env tells the Filebeat process what port to listen on inside the container, but Docker must also expose that port to the host.

**How to avoid:** After configuring `FILEBEAT_SYSLOG_UDP_PORT=5514`, verify: `ss -ulnp | grep 5514` shows a docker-proxy or Malcolm process bound on the host. If empty, the port is not host-exposed. Check Malcolm's docker-compose.yml filebeat service for ports mapping.

**Warning signs:** `echo "test syslog" | nc -u 127.0.0.1 5514` sends but nothing appears in Malcolm; `ss -ulnp | grep 5514` returns empty.

### Pitfall 3: IPFire Syslog Format Incompatibility (No RFC5424)

**What goes wrong:** IPFire uses BusyBox syslogd which produces non-standard RFC3164 with no year in the timestamp. Malcolm's Filebeat syslog listener with `FILEBEAT_SYSLOG_UDP_FORMAT=rfc5424` (strict) will reject or misparse these messages.

**Why it happens:** IPFire's kernel is from 2026 but its syslog daemon is BusyBox vintage. The timestamp format is `MMM DD HH:MM:SS hostname message` with no year field. This caused issues in v1.0 (Alloy needed `rfc3164_default_to_current_year = true`).

**How to avoid:** Set `FILEBEAT_SYSLOG_UDP_FORMAT=auto` in filebeat.env. This allows Malcolm's Filebeat to auto-detect and handle both RFC3164 and RFC5424. The rsyslog relay (which re-wraps before forwarding to :5514) may add proper RFC3164 headers automatically.

**Warning signs:** Malcolm receives UDP packets on :5514 (confirmed via nc test) but no syslog events appear in OpenSearch; Malcolm Filebeat container logs show parse errors.

### Pitfall 4: Filebeat Suricata Module Not Writing to Malcolm's Expected Index

**What goes wrong:** Filebeat ships EVE JSON to Logstash :5044, but the data appears in a `filebeat-*` index rather than Malcolm's `network-*` or `arkime_sessions3-*` indices, making it invisible to Malcolm dashboards.

**Why it happens:** Malcolm's Logstash pipeline processes incoming Beats data through its own pipeline which routes to Malcolm's index naming schema. If Filebeat sends with Suricata module's default index template, Logstash may route it differently. The Filebeat Suricata module expects to talk to Elasticsearch with its own index, not to Malcolm's Logstash.

**How to avoid:** When shipping to Malcolm Logstash (not Elasticsearch directly), disable the Filebeat Suricata module's ILM and index template: set `setup.ilm.enabled: false` and `setup.template.enabled: false` in filebeat.yml. Malcolm's Logstash pipeline handles routing internally. Verify events appear in Malcolm's `network-*` index by checking OpenSearch after sending a test event.

**Alternative:** Use raw filebeat with `filebeat.inputs: [{type: filestream, paths: [/var/log/ipfire-eve/eve.json]}]` without the module if the module causes routing conflicts. Malcolm's Logstash has its own Suricata EVE JSON parsing pipeline.

**Warning signs:** `docker exec malcolm-opensearch-1 curl -sk -u "..." https://localhost:9200/_cat/indices | grep filebeat` shows a filebeat index but Malcolm dashboards show no Suricata data.

### Pitfall 5: EVE JSON File Rotation Causes Filebeat to Miss Events

**What goes wrong:** Suricata on IPFire rotates eve.json (typically daily). When SCP cron copies the file to `/var/log/ipfire-eve/eve.json`, if the file is replaced (not appended), Filebeat's position tracking (registry) points to the old inode and it misses new content or re-reads from the start.

**Why it happens:** Filebeat tracks log position via file inode + offset. When SCP overwrites the file, the inode may change (OS-dependent). Filebeat detects the new file and either reads from the beginning (duplicate events) or ignores it (missed events).

**How to avoid:** Use `scp` to a temporary file and then `mv` (atomic rename preserves inode) OR configure Filebeat with `close_renamed: false` and `clean_removed: false` to handle rotation gracefully. Best practice: SCP to a staging file and `cat >>` append to the destination, or SCP to `/var/log/ipfire-eve/eve.json.tmp` and `mv` atomically.

**Warning signs:** Malcolm shows duplicate events (same alert twice in close succession) or long gaps with no events after IPFire's daily log rotation.

### Pitfall 6: validate-phase5.sh Checks the Wrong Host

**What goes wrong:** validate-phase5.sh currently runs ON supportTAK-server (192.168.1.101 — old IP) and checks Loki at localhost:3100. The new script must check Malcolm at 192.168.1.22 (current IP) via SSH from the dev machine, consistent with validate-phase9.sh.

**Why it happens:** The Phase 5 runbook deployed validate-phase5.sh to supportTAK-server and ran it locally there. The Phase 9 validation script (validate-phase9.sh) uses a different pattern: runs from the local Windows machine and SSHes to check Malcolm. The replacement script should follow the Phase 9 pattern.

**Note:** The runbook also shows supportTAK-server had IP 192.168.1.101 in v1.0 and 192.168.1.22 in v2.0. The current IP is 192.168.1.22 (confirmed in Phase 9 summaries).

**How to avoid:** Model the new validation script on validate-phase9.sh, not validate-phase5.sh. Run from dev machine, SSH to 192.168.1.22, check Malcolm endpoints (HTTPS :443, OpenSearch internal API, Filebeat log counts).

---

## Code Examples

### Malcolm OpenSearch — Check Suricata Alert Index Count

```bash
# Source: Malcolm Phase 9 validation pattern (validate-phase9.sh)
INTERNAL_CREDS=$(ssh opsadmin@192.168.1.22 \
  "docker exec malcolm-dashboards-helper-1 cat /var/local/curlrc/.opensearch.primary.curlrc \
   | grep '^user:' | sed 's/^user: \"//;s/\"$//'" 2>/dev/null)

ssh opsadmin@192.168.1.22 \
  "docker exec malcolm-opensearch-1 curl -sk -u \"${INTERNAL_CREDS}\" \
   'https://localhost:9200/arkime_sessions3-*/_count?q=event.module:suricata' 2>/dev/null" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('count', 0))"
```

### rsyslog Forward Rule (Relay to Malcolm)

```conf
# /etc/rsyslog.d/20-malcolm-forward.conf
# Forward all syslog received from IPFire to Malcolm's Filebeat syslog listener
# Source: rsyslog omfwd documentation (https://www.rsyslog.com/doc/configuration/modules/omfwd.html)
*.* action(type="omfwd"
           target="127.0.0.1"
           port="5514"
           protocol="udp"
           action.resumeRetryCount="3"
           queue.type="LinkedList"
           queue.size="10000")
```

### Malcolm filebeat.env Syslog Configuration

```bash
# Edit on supportTAK-server at /opt/malcolm/config/filebeat.env
# Source: Malcolm config documentation (https://cisagov.github.io/Malcolm/docs/malcolm-config.html)
FILEBEAT_SYSLOG_UDP_LISTEN=true
FILEBEAT_SYSLOG_UDP_PORT=5514
FILEBEAT_SYSLOG_UDP_FORMAT=auto
# TCP disabled — IPFire uses UDP only
FILEBEAT_SYSLOG_TCP_LISTEN=false
```

### External Filebeat Config for EVE JSON → Malcolm Logstash

```yaml
# /etc/filebeat/filebeat.yml on supportTAK-server
# Source: Elastic Filebeat Suricata module documentation + Malcolm ingestion docs

filebeat.modules:
  - module: suricata
    eve:
      enabled: true
      var.paths:
        - /var/log/ipfire-eve/eve.json

# Disable Elasticsearch template management — Malcolm Logstash handles routing
setup.ilm.enabled: false
setup.template.enabled: false

output.logstash:
  hosts: ["localhost:5044"]

# Logging
logging.level: info
logging.to_files: true
logging.files:
  path: /var/log/filebeat
  name: filebeat
  keepfiles: 7
```

### SCP Cron for EVE JSON Pull (Retained from v1.0)

```bash
# /etc/cron.d/ipfire-eve-pull or crontab -e as opsadmin
# Pull IPFire EVE JSON every 60 seconds
* * * * * opsadmin /opt/telemetry/scripts/scp-eve.sh >> /var/log/scp-eve.log 2>&1

# /opt/telemetry/scripts/scp-eve.sh (or telemetry-malcolm/filebeat/scp-eve.sh)
#!/bin/bash
set -e
SRC="root@192.168.1.1:/var/log/suricata/eve.json"
DEST="/var/log/ipfire-eve/eve.json"
TMP="${DEST}.tmp"
SSH_KEY="/home/opsadmin/.ssh/ipfire_ed25519"
scp -q -i "${SSH_KEY}" -o StrictHostKeyChecking=no "${SRC}" "${TMP}" && mv "${TMP}" "${DEST}"
```

**Note on atomic rename:** Using `scp to .tmp` then `mv` preserves Filebeat's ability to track the file position because `mv` on the same filesystem is atomic and preserves the inode in many OS configurations. Test this on Ubuntu 22.04 — if inode changes on `mv`, switch to `cat >> DEST < TMP` append pattern.

### Loki Archive Before Decommission

```bash
# Export last 7 days of syslog from Loki (from supportTAK-server where Loki is running)
# Source: Loki API documentation
START=$(date -d '7 days ago' +%s)000000000
END=$(date +%s)000000000
curl -s -G 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={job="ipfire-syslog"}' \
  --data-urlencode "start=${START}" \
  --data-urlencode "end=${END}" \
  --data-urlencode 'limit=5000' \
  > /opt/loki-archive/ipfire-syslog-$(date +%Y%m%d).json

# Same for EVE JSON stream
curl -s -G 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={job="suricata-eve"}' \
  --data-urlencode "start=${START}" \
  --data-urlencode "end=${END}" \
  --data-urlencode 'limit=5000' \
  > /opt/loki-archive/suricata-eve-$(date +%Y%m%d).json
```

### Test Syslog Delivery to Malcolm

```bash
# Send test syslog to rsyslog relay; confirm it reaches Malcolm OpenSearch
# Run from supportTAK-server
logger -p local0.info "FORWARDFW TEST DROP SRC=203.0.113.42 DST=192.168.1.22 PROTO=TCP DPT=22"

# Wait 30 seconds, then query Malcolm OpenSearch for the test string
INTERNAL_CREDS=$(docker exec malcolm-dashboards-helper-1 \
  cat /var/local/curlrc/.opensearch.primary.curlrc \
  | grep '^user:' | sed 's/^user: \"//;s/\"$//'; 2>/dev/null)

docker exec malcolm-opensearch-1 curl -sk -u "${INTERNAL_CREDS}" \
  'https://localhost:9200/_search?q=FORWARDFW+TEST&size=1' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['hits']['total']['value'])"
```

### Trigger Suricata Alert for Validation

```bash
# Run from supportTAK-server — triggers EICAR-like Suricata rule match
# Source: Suricata community validation pattern
ssh -i /home/opsadmin/.ssh/ipfire_ed25519 root@192.168.1.1 \
  'curl -s http://testmynids.org/uid/index.html > /dev/null'

# Wait 90 seconds for: Suricata alert → SCP cron pull → Filebeat → Logstash → OpenSearch index
# Then check Malcolm for recent Suricata alerts
```

---

## State of the Art

| Old Approach (v1.0) | Current Approach (v2.0) | Impact |
|---------------------|-------------------------|--------|
| SCP cron + Alloy file tail → Loki | SCP cron + Filebeat Suricata module → Malcolm Logstash | Structured EVE JSON parsing; indexed for search, not label-filtered |
| rsyslog → file → Alloy tail → Loki | rsyslog → relay UDP :5514 → Malcolm Filebeat → OpenSearch | Full-text searchable syslog; FORWARDFW/CUSTOMINPUT/GUARDIAN queryable |
| Grafana dashboards at :3000 | Malcolm OpenSearch Dashboards at :443 | Pre-built NSM dashboards (Suricata Alerts, Zeek, Connections, Threat Intel) |
| Loki label-based search (high cardinality risk) | OpenSearch inverted index full-text search | Arbitrary field queries; no label cardinality constraints |
| validate-phase5.sh checks Loki API | validate-phase10.sh checks Malcolm API | Tests reflect actual production architecture |

**Deprecated/outdated in Phase 10:**
- `/opt/telemetry/docker-compose.yml` — stop and remove after validation
- `/opt/telemetry/alloy/config.alloy` — superseded by Filebeat + rsyslog relay
- `telemetry-deployment-runbook.md` (current Loki runbook) — replace with Malcolm architecture runbook
- `validate-phase5.sh` Loki/Grafana checks — replace with Malcolm OpenSearch checks

---

## Open Questions

1. **Malcolm Logstash Port 5044 Exposure from Phase 9**
   - What we know: Phase 9 ran the interactive install.py. It's unknown whether the executor answered Y to "expose Logstash port."
   - What's unclear: Whether `5044/tcp` is currently host-exposed on supportTAK-server.
   - Recommendation: **First action in Phase 10** — SSH to supportTAK-server and run `ss -tlnp | grep 5044`. If empty, must expose port before Filebeat can connect. Fix by adding `5044:5044` to Malcolm's docker-compose.yml logstash ports section and restarting logstash container.

2. **Malcolm Filebeat Container Port Exposure for Syslog**
   - What we know: `FILEBEAT_SYSLOG_UDP_PORT` configures the internal port. Malcolm must also expose it in Docker Compose.
   - What's unclear: Whether the Phase 9 configure wizard exposed any syslog port, and what docker-compose.yml currently shows for the filebeat service.
   - Recommendation: SSH and check `cat /opt/malcolm/docker-compose.yml | grep -A5 'filebeat'` and `ss -ulnp | grep 5514` after config change.

3. **IPFire syslog.conf Current State**
   - What we know: Phase 5 v1.0 configured IPFire to forward to 192.168.1.101. supportTAK-server was renumbered to 192.168.1.22 between v1.0 and v2.0.
   - What's unclear: Whether `/etc/syslog.conf` on IPFire still points to 192.168.1.101 (old) or was updated to 192.168.1.22.
   - Recommendation: SSH to IPFire and `grep "192.168" /etc/syslog.conf`. If pointing to old IP (.101), update via WUI Logs > Log Settings to 192.168.1.22.

4. **EVE JSON SCP Cron — Still Running?**
   - What we know: v1.0 configured rsync/SCP cron pulling from IPFire. Phase 9 outcome is silent on whether this cron was removed.
   - What's unclear: Whether a cron job is already copying eve.json to `/var/log/ipfire-eve/eve.json` on supportTAK-server.
   - Recommendation: `crontab -l` as opsadmin on supportTAK-server; `ls -la /var/log/ipfire-eve/` to check if file exists and is recent.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Bash validation scripts (project standard — validate-phase9.sh pattern) |
| Config file | None — standalone bash scripts |
| Quick run command | `bash scripts/validate-phase10.sh` (from local dev machine) |
| Full suite command | `bash scripts/validate-phase10.sh --full` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MAL-02 | Suricata EVE events appear in Malcolm OpenSearch (arkime_sessions3-* or network-* index) | smoke | Query OpenSearch `_count` on suricata index | ❌ Wave 0 |
| MAL-02 | Live Suricata alert within 5 min of testmynids.org trigger | integration | Trigger scan + wait 5 min + count query | ❌ Wave 0 |
| MAL-03 | IPFire FORWARDFW/CUSTOMINPUT/GUARDIAN appear in OpenSearch | smoke | Query OpenSearch for syslog keywords | ❌ Wave 0 |
| MIG-01 | Both Loki and Malcolm receiving data during parallel window | integration | Loki query + OpenSearch query both return non-zero | ❌ Wave 0 |
| MIG-02 | No Loki/Alloy/Grafana/Prometheus containers in docker ps | smoke | `docker ps` returns no Loki stack containers | ❌ Wave 0 |
| MIG-03 | Replacement validation script checks Malcolm endpoints | unit | Script syntax check + endpoint reachability | ❌ Wave 0 |
| MIG-04 | Runbook describes Filebeat-to-Malcolm architecture, no Alloy/Loki/SCP references | manual | Grep runbook for deprecated terms | Manual |

### Sampling Rate
- **Per task commit:** `bash scripts/validate-phase10.sh` (quick checks: Malcolm health, OpenSearch count, docker ps)
- **Per wave merge:** `bash scripts/validate-phase10.sh --full` (includes live trigger test and syslog keyword check)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `scripts/validate-phase10.sh` — new validation script covering MAL-02, MAL-03, MIG-02, MIG-03
- [ ] Script must follow validate-phase9.sh pattern (runs from dev machine via SSH)
- [ ] Script must NOT require Loki/Grafana to be running

---

## Sources

### Primary (HIGH confidence)
- [Malcolm Configuration Documentation](https://cisagov.github.io/Malcolm/docs/malcolm-config.html) — `FILEBEAT_SYSLOG_UDP_PORT`, `FILEBEAT_SYSLOG_UDP_LISTEN`, `LOGSTASH_HOST` variables verified
- [Malcolm Forwarding Third-Party Logs](https://malcolm.fyi/docs/third-party-logs.html) — syslog ingestion configuration; FILEBEAT_SYSLOG_TCP_PORT and FILEBEAT_SYSLOG_UDP_PORT variables; format options (auto/rfc3164/rfc5424)
- [Malcolm GitHub Issue #354 — Enhanced Syslog Ingestion](https://github.com/cisagov/Malcolm/issues/354) — confirms configurable syslog ports, TCP/UDP options, disable-by-setting-to-zero behavior
- [Elastic Filebeat Suricata Module Reference](https://www.elastic.co/guide/en/beats/filebeat/8.19/filebeat-module-suricata.html) — Suricata module configuration, var.paths, EVE JSON parsing
- [Elastic Filebeat Logstash Output](https://www.elastic.co/guide/en/beats/filebeat/8.19/logstash-output.html) — Beats protocol to Logstash :5044 configuration
- [rsyslog omfwd Module](https://www.rsyslog.com/doc/configuration/modules/omfwd.html) — UDP forwarding configuration, action syntax, queue settings
- Phase 9 SUMMARY files (09-01-SUMMARY.md, 09-02-SUMMARY.md) — confirmed Malcolm RAM at 12.5GB, 27 containers running, ISM policy configured, UDP :514 conflict noted and deferred to Phase 10

### Secondary (MEDIUM confidence)
- [Malcolm Live Analysis Documentation](https://malcolm.fyi/docs/live-analysis.html) — Malcolm Logstash Beats port exposure configuration reference
- [rsyslog UDP Relay Documentation](https://docs.rsyslog.com/doc/tutorials/tls_cert_udp_relay.html) — relay architecture pattern; applicable to rsyslog-to-Malcolm forward scenario
- STACK.md, ARCHITECTURE.md, PITFALLS.md (.planning/research/) — project-level architectural context, RAM budget constraints, Loki migration dark period patterns

### Tertiary (LOW confidence, verify during execution)
- Malcolm docker-compose.yml port exposure behavior — whether Phase 9 configure script exposed Logstash :5044 and Filebeat syslog port; must verify on actual running system
- IPFire syslog.conf current IP target — may still point to 192.168.1.101 (old IP) from v1.0 setup

---

## Metadata

**Confidence breakdown:**
- Standard stack (Filebeat Suricata module → Logstash :5044): HIGH — documented Malcolm path
- Syslog relay architecture (rsyslog :514 → rsyslog → Malcolm :5514): HIGH — rsyslog omfwd is stable; Malcolm FILEBEAT_SYSLOG_UDP_PORT verified in official docs
- EVE JSON SCP-pull pattern: HIGH — proven in v1.0; unchanged approach
- Port exposure state on actual running Malcolm: LOW — must verify `ss -tlnp` and `ss -ulnp` before building
- IPFire syslog.conf current state: LOW — may point to old IP; must verify before configuration

**Research date:** 2026-04-02
**Valid until:** 2026-05-02 (Malcolm documentation is stable; Filebeat module is stable)

**Key unknowns to resolve at Phase 10 start (pre-planning discovery):**
1. `ss -tlnp | grep 5044` on supportTAK-server — Logstash port exposed?
2. `cat /opt/malcolm/docker-compose.yml | grep -A10 'filebeat'` — filebeat ports section
3. `ssh root@192.168.1.1 'grep "192.168" /etc/syslog.conf'` — IPFire syslog target IP
4. `crontab -l` as opsadmin on supportTAK-server — SCP cron present?
5. `ls -la /var/log/ipfire-eve/` — eve.json file present and recent?
