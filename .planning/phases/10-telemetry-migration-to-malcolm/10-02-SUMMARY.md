---
phase: 10-telemetry-migration-to-malcolm
plan: 02
status: complete
started: 2026-04-06
completed: 2026-04-06
duration_minutes: 30
---

# Plan 10-02 Summary: Decommission Loki + Validation + Runbook

## What Was Built

Loki/Alloy/Grafana/Prometheus stack decommissioned. Malcolm is now the sole telemetry backend. Validation script and runbook updated for v2.0 architecture.

## Key Outcomes

- **Loki stack removed:** 5 containers + 3 volumes removed via `docker compose down -v`
- **RAM freed:** 12.5GB → 11.7GB (800MB freed from Loki/Alloy/Grafana/Prometheus)
- **validate-phase10.sh:** 10 checks covering all 6 requirements (MAL-02, MAL-03, MIG-01-04)
- **Telemetry runbook:** Full rewrite — 8 sections covering Malcolm architecture, EVE JSON path, syslog path, validation, ISM retention, troubleshooting, disaster recovery, v1.0 decommission notes
- **rsyslog simplified:** Removed file-write config (10-ipfire-remote.conf) — now receive-only with omfwd relay

## Validation Results

10 PASS, 0 FAIL, 0 SKIP:
- 225K EVE JSON docs in arkime_sessions3-*
- 53K Suricata alerts (event.dataset:alert)
- 628K syslog docs in malcolm_beats_syslog_*
- Only Malcolm containers running
- 27/27 containers healthy
- RAM at 11.7GB (under 14GB threshold)
- Malcolm web UI returning 401 (auth working)
- Runbook has 55 Malcolm references, 0 deprecated Alloy/Loki references
