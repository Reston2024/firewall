# Telemetry Pipeline Deployment Runbook — Phase 5

**Date:** 2026-03-24
**Stack Versions:** Loki 3.6.0, Alloy 1.14.1, Grafana 12.4.1, Prometheus 3.10.0, node-exporter 1.8.2
**Telemetry host:** supportTAK-server (192.168.1.101)
**IPFire:** 192.168.1.1 (WUI at https://192.168.1.1:444)
**Repo root (dev machine):** C:\Users\ablan\Firewall

Complete sections in ORDER — the sequence below is mandatory for safe deployment.

---

## CRITICAL WARNINGS — Read Before Starting

- **Deploy Docker Compose stack BEFORE configuring IPFire syslog forwarding** — Alloy must be listening on UDP port 514 before IPFire starts sending logs. If syslog arrives before Alloy is ready, those logs are lost.
- **Verify UDP port 514 is NOT held by rsyslog before starting Alloy.** rsyslog binds port 514 by default on Ubuntu. If rsyslog holds 514, the Alloy container will fail to bind the port and syslog will be silently dropped (Section 2).
- **NEVER use `docker-compose` (v1 syntax)** — always use `docker compose` (v2 plugin, with a space) on supportTAK-server. The v1 binary is not installed on this host.
- **Grafana admin password "changeme" is the default.** Change it on first login. If you change it, update the TEL-06 Grafana API check in validate-phase5.sh accordingly (the script uses HTTP Basic Auth with admin:changeme by default).
- **EVE JSON path (rsync) is NOT configured in this runbook.** This runbook covers the syslog path (Path A) only. The rsync EVE JSON pipeline (Path B) is configured in Plan 03.
- **IPFire syslog uses RFC3164 format** (no year in timestamp). The Alloy config handles this via `rfc3164_default_to_current_year = true` — do not modify this setting or timestamps will land in Loki with year 0000.

---

## Section 1: Prerequisites

Before starting Phase 5 deployment, verify the following are complete:

- Phase 4 completed: Suricata running, `/var/log/suricata/eve.json` confirmed active
- SSH to supportTAK-server works: `ssh opsadmin@192.168.1.101`
- SSH to IPFire works: `ssh -i C:\Users\ablan\.ssh\ipfire_ed25519 root@192.168.1.1`
- WUI accessible from dev machine: https://192.168.1.1:444
- Dev machine: `C:\Users\ablan\Firewall` repo is at current commit with Plan 01 complete (all `telemetry/` files present)
- supportTAK-server: Docker is installed

**Verify Docker on supportTAK-server before starting:**
```bash
ssh opsadmin@192.168.1.101 'docker --version && docker compose version'
```

Expected: Docker 24+ and Docker Compose v2 plugin version lines.

- [ ] SSH to supportTAK-server confirmed working
- [ ] SSH to IPFire confirmed working
- [ ] WUI accessible at https://192.168.1.1:444
- [ ] Docker and Docker Compose v2 confirmed on supportTAK-server
- [ ] Repo is current on dev machine (`git pull`)

---

## Section 2: Check for rsyslog Conflict on supportTAK-server (Pre-Flight)

**Purpose:** rsyslog on Ubuntu binds UDP port 514 by default. If rsyslog is running and holding port 514, the Alloy container will fail to bind the port when the stack starts, causing silent syslog delivery failure.

### Step 2.1: Check if rsyslog is binding UDP port 514
```bash
ssh opsadmin@192.168.1.101 'sudo ss -ulnp | grep :514'
```

### Step 2.2: If rsyslog appears in the output — disable it
```bash
ssh opsadmin@192.168.1.101 'sudo systemctl stop rsyslog && sudo systemctl disable rsyslog'
```

Verify port is now free:
```bash
ssh opsadmin@192.168.1.101 'sudo ss -ulnp | grep :514'
```
Expected: no output (port is free).

### Step 2.3: If nothing appears — port is free, proceed to Section 3

**Note:** rsyslog.service is optional on monitoring hosts. Alloy will take over as the syslog receiver on this host. Disabling rsyslog does not affect syslog functionality — it is replaced by Alloy's `loki.source.syslog` component.

- [ ] UDP port 514 is free on supportTAK-server (rsyslog disabled if it was running)

---

## Section 3: Deploy Docker Compose Stack to supportTAK-server

### Step 3.1: Create stack root directory on supportTAK-server
```bash
ssh opsadmin@192.168.1.101 'sudo mkdir -p /opt/telemetry && sudo chown opsadmin:opsadmin /opt/telemetry'
```

### Step 3.2: SCP telemetry files from dev machine to supportTAK-server
```bash
scp -r C:/Users/ablan/Firewall/telemetry/ opsadmin@192.168.1.101:/opt/
```

This copies all config files:
- `telemetry/docker-compose.yml`
- `telemetry/alloy/config.alloy`
- `telemetry/loki/loki-config.yml`
- `telemetry/grafana/provisioning/datasources/datasources.yml`
- `telemetry/grafana/provisioning/dashboards/dashboards.yml`
- `telemetry/prometheus/prometheus.yml`
- `telemetry/scripts/rsync-eve.sh`

Verify files arrived:
```bash
ssh opsadmin@192.168.1.101 'find /opt/telemetry -type f | sort'
```
Expected: 7+ files listed under /opt/telemetry/.

### Step 3.3: Fix CRLF line endings on all scripts (required — files SCP'd from Windows)

Windows creates files with CRLF line endings. Linux bash scripts with CRLF endings fail with cryptic `/bin/bash^M: bad interpreter` errors.

```bash
ssh opsadmin@192.168.1.101 'find /opt/telemetry -name "*.sh" -exec sed -i "s/\r$//" {} \; && echo "CRLF fix: OK"'
```

### Step 3.4: Create EVE JSON staging directory
```bash
ssh opsadmin@192.168.1.101 'sudo mkdir -p /var/log/ipfire-eve && sudo chown opsadmin:opsadmin /var/log/ipfire-eve'
```

This directory is required by the Alloy file-read pipeline (Plan 03). Creating it now prevents a volume mount error when the Alloy container starts.

### Step 3.5: Pull Docker images (first-time pull may take 5-10 minutes)
```bash
ssh opsadmin@192.168.1.101 'docker compose -f /opt/telemetry/docker-compose.yml pull'
```

Expected: Pull messages for each image. Final line: "Pull complete" for all services.

### Step 3.6: Start the stack
```bash
ssh opsadmin@192.168.1.101 'docker compose -f /opt/telemetry/docker-compose.yml up -d'
```

Expected: `Container [name] Started` for all 5 services.

### Step 3.7: Verify all 5 containers are running
```bash
ssh opsadmin@192.168.1.101 'docker compose -f /opt/telemetry/docker-compose.yml ps'
```

Expected: All 5 services — `loki`, `alloy`, `prometheus`, `node-exporter`, `grafana` — with status `running`.

If any container shows `exited` immediately:
```bash
# Check logs for the failing container (replace [service-name] with the failing container)
ssh opsadmin@192.168.1.101 'docker compose -f /opt/telemetry/docker-compose.yml logs [service-name] --tail=50'
```

Common causes:
- Port conflict (alloy/514 or grafana/3000): check with `sudo ss -tlnp` and `sudo ss -ulnp`
- Config file parse error (alloy): check `docker compose logs alloy --tail=50` for River config syntax errors
- Permission error (loki): loki writes to `/opt/telemetry/loki/data/` — verify opsadmin owns `/opt/telemetry/`

### Step 3.8: Verify Loki is ready
```bash
curl -s http://192.168.1.101:3100/ready
```

Expected: `ready`

If not ready, wait 30 seconds and retry. Loki performs a startup migration on first run.

### Step 3.9: Verify Grafana is accessible
Open in browser: http://192.168.1.101:3000

Login: `admin` / `changeme`

Change password when prompted. **Record the new password — it is required for DASH-03 verification in Plan 04.**

After login, verify:
- Data sources: Go to Connections > Data Sources — Loki and Prometheus should be auto-provisioned
- Loki datasource should show green check when "Test" is clicked

### Step 3.10: Verify Alloy is binding UDP port 514
```bash
ssh opsadmin@192.168.1.101 'sudo ss -ulnp | grep 514'
```

Expected: A line showing `docker-proxy` or similar process listening on `*:514`.

Open Alloy debug UI: http://192.168.1.101:12345

Verify components page shows no errors. The `loki.source.syslog` component should show `healthy` status.

- [ ] All 5 containers running: loki, alloy, prometheus, node-exporter, grafana
- [ ] Loki /ready returns "ready"
- [ ] Grafana accessible at :3000, password changed
- [ ] Grafana Loki datasource shows connected
- [ ] Alloy debug UI at :12345 shows no errors
- [ ] UDP port 514 is bound (docker-proxy or alloy visible in ss output)

---

## Section 4: Deploy validate-phase5.sh to supportTAK-server

### Step 4.1: SCP validate-phase5.sh to supportTAK-server
```bash
scp C:/Users/ablan/Firewall/scripts/validate-phase5.sh opsadmin@192.168.1.101:/opt/telemetry/scripts/validate-phase5.sh
```

### Step 4.2: Fix CRLF and set executable
```bash
ssh opsadmin@192.168.1.101 'sed -i "s/\r$//" /opt/telemetry/scripts/validate-phase5.sh && chmod +x /opt/telemetry/scripts/validate-phase5.sh'
```

### Step 4.3: Verify script syntax
```bash
ssh opsadmin@192.168.1.101 'bash -n /opt/telemetry/scripts/validate-phase5.sh && echo "syntax OK"'
```

Expected: `syntax OK` — no parse errors.

- [ ] validate-phase5.sh deployed to /opt/telemetry/scripts/ and executable

---

## Section 5: Configure IPFire Syslog Forwarding (TEL-01)

**Context:** IPFire WUI writes `/etc/syslog.conf` when syslog forwarding is configured. The WUI setting is the only persistent way to configure syslog forwarding — manual edits to syslog.conf are overwritten on restart.

**CRITICAL:** The Docker Compose stack (Section 3) must be running and Alloy must be binding port 514 before completing this section.

### Step 5.1: Navigate to the IPFire syslog settings page
Open WUI: https://192.168.1.1:444

Navigate to: **Logs > Log Settings**

### Step 5.2: Configure remote logging
In the "Remote Logging" section:

- **Syslog server** field: enter `192.168.1.101`
- **Protocol:** UDP (only option — IPFire's native syslog daemon does not support TCP forwarding)
- Click **Save**

**Note:** Port 514 is hardcoded in IPFire's syslog forwarding. The WUI does not expose port selection. Port 514 must be free on supportTAK-server (confirmed in Section 2).

### Step 5.3: Verify syslog.conf was updated on IPFire
```bash
ssh -i C:/Users/ablan/.ssh/ipfire_ed25519 root@192.168.1.1 'grep "192.168.1.101" /etc/syslog.conf'
```

Expected: a line containing `@192.168.1.101` (UDP forwarding notation in syslog.conf syntax).

If the grep returns empty: the WUI Save may not have applied. Reload the Log Settings page and re-enter the value.

### Step 5.4: Restart IPFire syslog daemon to apply forwarding
```bash
ssh -i C:/Users/ablan/.ssh/ipfire_ed25519 root@192.168.1.1 '/etc/init.d/syslog restart'
```

Expected: `syslog restart: OK` or similar success message.

- [ ] IPFire WUI Logs > Log Settings: Syslog server = 192.168.1.101, UDP
- [ ] /etc/syslog.conf on IPFire contains @192.168.1.101
- [ ] IPFire syslog daemon restarted

---

## Section 6: Verify Syslog Path is Live — Firewall Drops Appearing in Loki (TEL-04, TEL-05)

### Step 6.1: Wait 60 seconds for first syslog entries to arrive from IPFire

After configuring syslog forwarding, IPFire immediately begins forwarding active log entries. Any network activity (DNS queries, NTP, LAN traffic) will generate firewall log entries. Wait at least 60 seconds before querying Loki.

### Step 6.2: Send a test FORWARDFW log line from dev machine (simulates IPFire drop event)

This command injects a test log line directly into Alloy's UDP 514 listener, bypassing IPFire. It verifies the Alloy → Loki pipeline independently:

```bash
logger -n 192.168.1.101 -P 514 --udp "$(date '+%b %d %H:%M:%S') ipfire kernel: FORWARDFW DROP SRC=203.0.113.42 DST=192.168.1.100 PROTO=TCP DPT=22"
```

**Note:** `logger` must be available on the dev machine (WSL, Git Bash, or Linux system). If `logger` is not available, SSH to supportTAK-server and run the logger command from there using `127.0.0.1` as target.

### Step 6.3: Query Loki for the test FORWARDFW entry (within 30 seconds)
```bash
curl -s -G 'http://192.168.1.101:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={job="ipfire-syslog"} |= "FORWARDFW"' \
  --data-urlencode 'limit=3' | jq '.data.result[0].values[-1][1]'
```

Expected: A JSON string containing the "FORWARDFW" log entry text.

If the result is `null`:
1. Check Alloy debug UI at http://192.168.1.101:12345 — the `loki.source.syslog` component should show received events count > 0
2. Verify Alloy is binding port 514: `ssh opsadmin@192.168.1.101 'sudo ss -ulnp | grep 514'`
3. Verify the logger command syntax — the test message must match RFC3164 format

### Step 6.4: Verify from Grafana Explore
1. Open http://192.168.1.101:3000
2. Click **Explore** (compass icon in left sidebar)
3. Select **Loki** as data source
4. In the query builder, run: `{job="ipfire-syslog"}`
5. Set time range to "Last 5 minutes"

Expected: Log entries from IPFire visible in the Explore panel timeline.

### Step 6.5: Verify real IPFire syslog entries are arriving (TEL-01)
```bash
curl -s -G 'http://192.168.1.101:3100/loki/api/v1/query' \
  --data-urlencode 'query=count_over_time({job="ipfire-syslog"}[5m])' | jq '.data.result | length'
```

Expected: `1` or greater (non-empty result array indicates log entries exist).

If result is `0`: IPFire syslog forwarding may not have taken effect yet. Check:
- Syslog.conf on IPFire: `ssh -i C:/Users/ablan/.ssh/ipfire_ed25519 root@192.168.1.1 'cat /etc/syslog.conf'`
- Alloy debug UI shows received events
- No firewall rules blocking UDP 514 from 192.168.1.1 to 192.168.1.101

- [ ] Test FORWARDFW log line appeared in Loki via Loki API query
- [ ] Real IPFire syslog entries visible in Grafana Explore
- [ ] Loki count_over_time query returns non-empty result

---

## Section 7: Run validate-phase5.sh (TEL-01 through TEL-08)

### Step 7.1: Run the validation suite from supportTAK-server
```bash
ssh opsadmin@192.168.1.101 'bash /opt/telemetry/scripts/validate-phase5.sh'
```

### Expected results at this stage

| Check | Expected Result | Notes |
|-------|----------------|-------|
| TEL-01 | PASS | IPFire syslog.conf contains 192.168.1.101 |
| TEL-02 | PASS | UDP 514 is held by docker-proxy (not rsyslog) |
| TEL-03 | PASS | 5 containers running |
| TEL-04 | PASS | Loki has {job="ipfire-syslog"} entries |
| TEL-05 | PASS | Loki /ready returns "ready" |
| TEL-06 | PASS | Grafana API returns Loki datasource |
| TEL-07 | SKIP | Always SKIP — phased ingest ordering is procedural |
| TEL-08 | PASS | loki-config.yml has retention_period: 720h |
| DASH-01 | SKIP | Requires --full flag and EVE JSON data (Plan 03) |
| DASH-02 | PASS or SKIP | PASS if FORWARDFW drops visible; SKIP if no traffic yet |
| DASH-03 | SKIP | Dashboard import is Plan 04 |
| DASH-04 | SKIP | Requires EVE JSON data (Plan 03) |

**Acceptable state to proceed to Plan 03:** TEL-01 PASS, TEL-02 PASS, TEL-03 PASS, TEL-04 PASS, TEL-05 PASS, TEL-06 PASS, TEL-07 SKIP, TEL-08 PASS. Zero FAIL.

### Step 7.2: If any TEL-0x check FAILS — troubleshooting

| FAIL | Root Cause | Fix |
|------|-----------|-----|
| TEL-01 FAIL | IPFire syslog.conf missing 192.168.1.101 | WUI > Logs > Log Settings — re-enter 192.168.1.101 and Save; restart syslog daemon |
| TEL-02 FAIL | rsyslog is holding UDP 514 | `sudo systemctl stop rsyslog && sudo systemctl disable rsyslog`; restart alloy container |
| TEL-03 FAIL | Container not running | `docker compose -f /opt/telemetry/docker-compose.yml logs [service] --tail=50` |
| TEL-04 FAIL | No entries in ipfire-syslog stream | Check Alloy debug UI; verify port 514 is bound; re-run logger test from Step 6.2 |
| TEL-05 FAIL | Loki not ready | Check loki container logs; verify loki-config.yml syntax |
| TEL-06 FAIL | Grafana auth changed | Update TEL-06 check in validate-phase5.sh with new admin password |
| TEL-08 FAIL | retention_period missing | Check /opt/telemetry/loki/loki-config.yml was SCP'd correctly from repo |

- [ ] validate-phase5.sh: ALL TEL-01 through TEL-08 checks PASS or SKIP (zero FAIL)

---

## Sign-Off Checklist

Complete all items before marking Phase 5 Plan 02 done.

**TEL-01: IPFire syslog forwarding configured**
- [ ] IPFire WUI Logs > Log Settings: Syslog server = 192.168.1.101, UDP
- [ ] /etc/syslog.conf on IPFire contains @192.168.1.101
- [ ] IPFire syslog daemon restarted after configuration

**TEL-02: UDP port 514 available on supportTAK-server**
- [ ] rsyslog not binding port 514 (disabled if present)
- [ ] docker-proxy or alloy visible in ss -ulnp output on port 514

**TEL-03: All 5 Docker containers running**
- [ ] loki — running
- [ ] alloy — running
- [ ] prometheus — running
- [ ] node-exporter — running
- [ ] grafana — running

**TEL-04: Alloy receiving syslog; Loki has {job="ipfire-syslog"} entries**
- [ ] Alloy debug UI at :12345 shows loki.source.syslog component healthy
- [ ] Loki API query for {job="ipfire-syslog"} returns entries
- [ ] FORWARDFW test log entry verified in Loki via curl query

**TEL-05: Loki /ready returns "ready"**
- [ ] curl http://192.168.1.101:3100/ready returns "ready"

**TEL-06: Grafana accessible at :3000, Loki datasource connected**
- [ ] Grafana login at http://192.168.1.101:3000 successful
- [ ] Password changed from default "changeme"
- [ ] Loki datasource shows connected (Test returns green)
- [ ] Prometheus datasource shows connected

**TEL-07: SKIP — phased ingest order is procedural**
- [ ] [SKIP — by design] Syslog path (Path A) is live; EVE JSON path (Path B) configured in Plan 03

**TEL-08: loki-config.yml has retention_period: 720h**
- [ ] grep retention_period /opt/telemetry/loki/loki-config.yml returns 720h

---

## After Completing This Runbook

Once all Sign-Off Checklist items are complete and validate-phase5.sh shows zero FAIL:

- **Signal to orchestrator:** Type `syslog-live` to confirm checkpoint passed
- **Next step:** Plan 03 — EVE JSON rsync pipeline setup (rsync-eve.sh cron, SSH key from supportTAK-server to IPFire, validate EVE JSON appearing in Loki)
- **Plan 04:** Dashboard import and Grafana configuration (depends on Plan 03 EVE JSON data)

What Plan 03 uses from this plan:
- Live Loki instance at http://192.168.1.101:3100 accepting writes
- Alloy running with Path B (EVE JSON file-read) configured in config.alloy — waiting for files in /var/log/ipfire-eve/
- /var/log/ipfire-eve/ directory already created (Step 3.4) and owned by opsadmin
- rsync-eve.sh script deployed to /opt/telemetry/scripts/ — needs SSH key and cron job added in Plan 03
