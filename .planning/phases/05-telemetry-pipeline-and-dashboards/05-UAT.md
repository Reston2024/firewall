---
status: complete
phase: 05-telemetry-pipeline-and-dashboards
source: 05-01-SUMMARY.md
started: 2026-03-24T14:30:00Z
updated: 2026-03-24T15:00:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Cold Start Smoke Test
expected: All 5 Docker containers running with healthy status
result: pass

### 2. Grafana Login
expected: Grafana login page loads at http://192.168.1.101:3000, authentication works
result: pass

### 3. Loki & Prometheus Datasources Provisioned
expected: Both datasources appear in Grafana and return healthy status
result: pass

### 4. IPFire Syslog Flowing to Loki
expected: Loki has ipfire-syslog job with live log data
result: pass

### 5. Suricata Dashboard Imported
expected: "Suricata Log Eve JSON" dashboard appears in Grafana
result: pass

### 6. Internal Services Not LAN-Accessible
expected: Prometheus (9090) and Node-exporter (9100) unreachable from LAN; Grafana (3000) reachable
result: pass

### 7. EVE JSON Rsync Cron Active
expected: Cron job running every minute, eve.json file exists on monitoring host
result: pass

### 8. Syslog Pipeline Resilience
expected: New syslog lines arrive within 10 seconds after rsyslog restart
result: pass

## Summary

total: 8
passed: 8
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

[none]
