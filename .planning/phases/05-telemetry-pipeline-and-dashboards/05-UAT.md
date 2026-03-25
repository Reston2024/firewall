---
status: complete
phase: 05-telemetry-pipeline-and-dashboards
source: 05-01-SUMMARY.md, 05-02-SUMMARY.md, 05-03-SUMMARY.md, 05-04-SUMMARY.md
started: 2026-03-25T10:50:00Z
updated: 2026-03-25T10:53:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Cold Start Smoke Test
expected: All 5 Docker containers running with healthy status. Loki /ready returns "ready".
result: pass

### 2. IPFire Syslog Forwarding Active
expected: IPFire syslog.conf contains @192.168.1.101. rsyslog on supportTAK-server receiving UDP 514. Loki has entries in {job="ipfire-syslog"}.
result: pass

### 3. EVE JSON Pipeline End-to-End
expected: rsync-eve.sh cron every minute. eve.json exists on supportTAK-server. Loki has suricata-eve entries.
result: pass

### 4. Grafana Login and Datasources
expected: Grafana accessible at :3000. Loki and Prometheus datasources auto-provisioned.
result: pass

### 5. IPFire Firewall Dashboard Panels
expected: Custom dashboard with 4 panels: Firewall Drops, Top Blocked IPs, Top Suricata Rules, Threat Trace.
result: pass

### 6. Suricata Dashboard Present
expected: Suricata dashboard exists in Grafana.
result: pass

### 7. Threat Trace Cross-Stream Query
expected: Known attacker IP returns entries from BOTH ipfire-syslog AND suricata-eve streams.
result: pass

### 8. Internal Services Not LAN-Accessible
expected: Prometheus/Node-exporter/Loki/Alloy bound to 127.0.0.1. Only Grafana on 0.0.0.0.
result: pass

### 9. Loki Retention Configured
expected: retention_period: 720h (30 days).
result: pass

### 10. Full Validation Suite Passes
expected: validate-phase5.sh --full returns 11 PASS, 0 FAIL, 1 SKIP.
result: pass

## Summary

total: 10
passed: 10
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

[none]
