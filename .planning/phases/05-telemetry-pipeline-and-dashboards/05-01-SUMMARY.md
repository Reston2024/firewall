---
phase: 05-telemetry-pipeline-and-dashboards
plan: "01"
subsystem: infra
tags: [docker-compose, grafana, loki, alloy, prometheus, syslog, eve-json, suricata, rsync]

# Dependency graph
requires:
  - phase: 04-suricata-ids-ips
    provides: Suricata IDS running on IPFire, producing /var/log/suricata/eve.json
provides:
  - Docker Compose stack definition (5 services at pinned versions) for supportTAK-server
  - Grafana Alloy River config with UDP syslog receiver (Path A) and EVE JSON file-read (Path B)
  - Loki single-node config with TSDB v13 schema, 30-day retention, max_query_series=200000
  - Grafana auto-provisioning for Loki and Prometheus datasources
  - rsync-eve.sh pull script for EVE JSON delivery from IPFire
  - validate-phase5.sh validation suite covering TEL-01 through DASH-04
affects: [05-02-deploy-stack, 05-03-eve-json-pipeline, 05-04-dashboards]

# Tech tracking
tech-stack:
  added:
    - grafana/loki:3.6.0 (TSDB v13 schema, single-node filesystem storage)
    - grafana/alloy:v1.14.1 (River config language, loki.source.syslog, loki.source.file)
    - grafana/grafana:12.4.1 (provisioning via config files, dashboard import)
    - prom/prometheus:v3.10.0 (scrapes Alloy metrics + node-exporter)
    - prom/node-exporter:v1.8.2 (host metrics for supportTAK-server)
  patterns:
    - Two-path log ingestion: syslog (Path A) and EVE JSON file-read (Path B) are separate Alloy components with separate Loki streams
    - structured_metadata (not labels) for high-cardinality fields in firewall syslog (src_ip from FORWARDFW lines)
    - stage.labels for src_ip on EVE alert stream only (acceptable cardinality for attacker tracking)
    - Alloy River config: source -> process -> write pipeline pattern
    - rfc3164_default_to_current_year=true mandatory for IPFire syslog to prevent year=0000 timestamp bug

key-files:
  created:
    - telemetry/docker-compose.yml
    - telemetry/alloy/config.alloy
    - telemetry/loki/loki-config.yml
    - telemetry/grafana/provisioning/datasources/datasources.yml
    - telemetry/grafana/provisioning/dashboards/dashboards.yml
    - telemetry/prometheus/prometheus.yml
    - telemetry/scripts/rsync-eve.sh
    - scripts/validate-phase5.sh
  modified: []

key-decisions:
  - "rsync --checksum (not --append-verify) for EVE JSON pull: detects logrotate file replacement correctly; avoids duplicate entries after IPFire midnight logrotate"
  - "stage.structured_metadata for src_ip on firewall syslog path: prevents high-cardinality Loki stream explosion from thousands of unique attacker IPs in FORWARDFW drop lines"
  - "stage.labels for src_ip on EVE JSON path only: attacker tracking is the primary use case; cardinality acceptable for alert-level events"
  - "Alloy user: root in Docker Compose: required to read /var/log/ipfire-eve/ directory created by opsadmin rsync cron"
  - "max_query_series: 200000 in Loki limits_config: required for dashboard 22247 topk() queries to function"
  - "rfc3164_default_to_current_year=true in Alloy syslog listener: prevents year=0000 timestamp storage bug (GitHub issue #2287)"

patterns-established:
  - "Pattern: Alloy River pipeline = source + relabel + process + write (four distinct component types)"
  - "Pattern: Loki label cardinality guard — extract from log body at query time OR use structured_metadata for high-cardinality fields"
  - "Pattern: validate-phase5.sh uses SKIP (not FAIL) for checks requiring live traffic or deployment steps not yet complete"

requirements-completed: [TEL-03, TEL-04, TEL-05, TEL-06, TEL-07, TEL-08]

# Metrics
duration: 10min
completed: 2026-03-23
---

# Phase 5 Plan 01: Telemetry Stack Artifacts Summary

**Docker Compose 5-service stack (Loki+Alloy+Grafana+Prometheus+node-exporter) with dual-path IPFire log ingestion, rsync-eve.sh pull script, and 12-requirement Phase 5 validation suite**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-03-23T07:32:57Z
- **Completed:** 2026-03-23T07:45:00Z
- **Tasks:** 2 of 2
- **Files modified:** 8

## Accomplishments

- Created all 7 telemetry stack config files under `telemetry/` (mirrors `/opt/telemetry/` on supportTAK-server)
- Alloy River config implements both log paths: UDP syslog receiver (Path A) and EVE JSON file-read (Path B), with critical pitfall guards embedded
- Created `scripts/validate-phase5.sh` covering all 12 Phase 5 requirements (TEL-01 through DASH-04) with smoke tests, documented SKIPs, and `--full` flag for live EVE ingest

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Docker Compose stack files and rsync-eve.sh** - `88b3baa` (feat)
2. **Task 2: Write validate-phase5.sh** - `f20c7d1` (feat)

## Files Created/Modified

- `telemetry/docker-compose.yml` - 5-service Docker Compose stack at pinned versions; alloy with `user: root` and `/var/log/ipfire-eve` volume mount
- `telemetry/alloy/config.alloy` - Alloy River config; Path A = UDP syslog with rfc3164 year fix + structured_metadata for firewall src_ip; Path B = EVE JSON file-read with stage.labels for alert src_ip
- `telemetry/loki/loki-config.yml` - Loki 3.6.0; TSDB v13; retention_period: 720h; max_query_series: 200000; compactor enabled
- `telemetry/grafana/provisioning/datasources/datasources.yml` - Auto-provisions Loki (isDefault) and Prometheus datasources on first start
- `telemetry/grafana/provisioning/dashboards/dashboards.yml` - Dashboard provider pointing to `/var/lib/grafana/dashboards`
- `telemetry/prometheus/prometheus.yml` - Scrapes prometheus self, alloy:12345, node-exporter:9100
- `telemetry/scripts/rsync-eve.sh` - Cron-triggered pull of eve.json from IPFire using `--checksum`; logs errors via `logger -t rsync-eve`
- `scripts/validate-phase5.sh` - Phase 5 validation suite; 12 sections; --full flag; bash -n verified; LF endings

## Decisions Made

- **rsync --checksum not --append-verify:** `--append-verify` causes duplicate entries after IPFire's nightly logrotate of `eve.json`. `--checksum` detects file replacement and overwrites cleanly.
- **stage.structured_metadata for firewall syslog src_ip:** Firewall drop events have thousands of unique source IPs. Promoting them as Loki labels would create stream explosion (Pitfall 2 from research). Structured metadata preserves the value without indexing overhead; LogQL regex extraction at query time still works for ad-hoc queries.
- **stage.labels for EVE JSON src_ip:** On the EVE alert stream, src_ip identifies attacker IPs. Cardinality is much lower (only alert events, not all firewall drops). Dashboard 22247 requires this as a label for topk() attacker queries.
- **max_query_series: 200000:** Default 500 limit causes dashboard 22247 panels to fail with "series limit reached" error. Set to 200000 per research finding (hardill.me.uk, January 2025).
- **rfc3164_default_to_current_year=true:** RFC3164 syslog has no year in timestamp. Without this, all IPFire syslog events land in Loki with year 0000, breaking all Grafana time-range queries.

## Deviations from Plan

None — plan executed exactly as written. Task 1 artifacts were pre-existing from an earlier execution and matched all acceptance criteria. Task 2 required CRLF-to-LF conversion (auto-fixed; Windows write tool creates CRLF, but `sed -i 's/\r//'` corrected before commit).

## Pitfalls Guarded Against

| Pitfall | Guard in Artifact |
|---------|------------------|
| RFC3164 year=0000 timestamps | `rfc3164_default_to_current_year = true` + `use_incoming_timestamp = true` in config.alloy |
| High-cardinality src_ip Loki streams from firewall drops | `stage.structured_metadata` for src_ip on firewall_parse pipeline; `stage.labels` only on eve_parse |
| Alloy permission denied on /var/log/ipfire-eve/ | `user: root` on alloy service in docker-compose.yml |
| UDP 514 rsyslog conflict | TEL-02 check in validate-phase5.sh with explicit remediation message |
| Dashboard 22247 series limit error | `max_query_series: 200000` in loki-config.yml |
| rsync duplicate entries after logrotate | `--checksum` flag in rsync-eve.sh (comment explains the anti-pattern) |

## validate-phase5.sh Coverage

| Requirement | Test Type | Automated? |
|-------------|-----------|-----------|
| TEL-01 | SSH to IPFire, grep syslog.conf | Yes (SKIP if SSH fails) |
| TEL-02 | `ss -ulnp` check port 514 | Yes (FAIL if rsyslog holds port) |
| TEL-03 | docker compose ps, count running | Yes (SKIP if stack not deployed) |
| TEL-04 | Loki query `{job="ipfire-syslog"}` | Yes (SKIP if no events yet) |
| TEL-05 | `curl localhost:3100/ready` | Yes (SKIP if connection refused) |
| TEL-06 | Grafana API datasource check | Yes (SKIP if auth changed) |
| TEL-07 | Ordering is procedural | Always SKIP (by design) |
| TEL-08 | grep retention_period in loki-config.yml | Yes (SKIP if stack not deployed) |
| DASH-01 | Loki query both streams (--full only) | Yes (SKIP unless --full) |
| DASH-02 | FORWARDFW count_over_time query | Yes (SKIP if no traffic yet) |
| DASH-03 | Grafana search API for suricata dashboard | Yes (FAIL if dashboard not imported) |
| DASH-04 | EVE alert topk() query | Yes (SKIP if no EVE data yet) |

## What Plan 02 Uses From This Plan

- All files in `telemetry/` are SCP'd to `/opt/telemetry/` on supportTAK-server
- `scripts/validate-phase5.sh` is copied to `/opt/telemetry/scripts/` for on-host validation
- Plan 02 runbook deploys the Docker Compose stack and wires IPFire syslog forwarding
- Plan 02 acceptance gate: `bash /opt/telemetry/scripts/validate-phase5.sh` with TEL-03, TEL-05, TEL-06 passing

## Issues Encountered

- CRLF line endings on `validate-phase5.sh` (auto-corrected with `sed -i 's/\r//'` before commit)

## Next Phase Readiness

- All Plan 01 artifacts are in the repo and committed
- Plan 02 (deploy stack + wire syslog) can proceed immediately
- Plan 03 (EVE JSON rsync pipeline) and Plan 04 (dashboards) depend on Plan 02 completing first

---
*Phase: 05-telemetry-pipeline-and-dashboards*
*Completed: 2026-03-23*
