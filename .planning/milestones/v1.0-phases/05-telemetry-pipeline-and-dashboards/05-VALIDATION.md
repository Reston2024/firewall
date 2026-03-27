---
phase: 5
slug: telemetry-pipeline-and-dashboards
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-22
---

# Phase 5 — Validation Strategy

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bash scripts + Docker Compose health checks |
| **Quick run command** | `bash /opt/telemetry/scripts/validate-phase5.sh` |
| **Full suite command** | `bash /opt/telemetry/scripts/validate-phase5.sh --full` |
| **Estimated runtime** | ~30 seconds |

## Sampling Rate

- **After every task commit:** Quick validate
- **After every plan wave:** Full suite
- **Max feedback latency:** 30 seconds

## Per-Task Verification Map

| Task ID | Requirement | Test Type | Status |
|---------|-------------|-----------|--------|
| 5-01-01 | TEL-03 | integration | Docker Compose stack running | ⬜ |
| 5-01-02 | TEL-01 | integration | Syslog receiver on UDP 514 | ⬜ |
| 5-01-03 | TEL-04 | integration | Alloy → Loki pipeline | ⬜ |
| 5-01-04 | TEL-05 | integration | Loki storing logs | ⬜ |
| 5-01-05 | TEL-06 | integration | Grafana dashboards loaded | ⬜ |
| 5-01-06 | DASH-01 | integration | Threat trace visible | ⬜ |
| 5-01-07 | TEL-08 | smoke | Retention policy configured | ⬜ |

## Manual-Only Verifications

| Behavior | Requirement | Why Manual |
|----------|-------------|------------|
| End-to-end threat trace | DASH-01 | Visual dashboard inspection |
| Firewall drop within 60s | TEL-06 | Timing-dependent |

## Validation Sign-Off

**Approval:** pending
