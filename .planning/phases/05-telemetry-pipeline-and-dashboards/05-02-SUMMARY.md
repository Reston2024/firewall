---
phase: 05-telemetry-pipeline-and-dashboards
plan: "02"
subsystem: infra
tags: [runbook, deployment, docker-compose, syslog, alloy, loki, ipfire, grafana, checkpoint]

# Dependency graph
requires:
  - phase: 05-01
    provides: Docker Compose stack files, Alloy/Loki/Grafana/Prometheus configs, validate-phase5.sh
provides:
  - docs/telemetry-deployment-runbook.md — complete ordered procedure for deploying Phase 5 stack and wiring IPFire syslog
  - Live Docker Compose stack on 192.168.1.101 with all 5 containers running (post-checkpoint)
  - IPFire syslog forwarding active to 192.168.1.101:514 (post-checkpoint)
  - Syslog entries appearing in Loki {job="ipfire-syslog"} stream (post-checkpoint)
affects: [05-03-eve-json-pipeline, 05-04-dashboards]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Runbook structure mirrors suricata-ids-runbook.md: numbered sections, prereqs, verification after each step, sign-off checklist
    - rsyslog pre-flight check as mandatory Section 2 before stack deploy
    - FORWARDFW log injection test using logger -n to verify end-to-end syslog path before IPFire is configured

key-files:
  created:
    - docs/telemetry-deployment-runbook.md
  modified: []

key-decisions:
  - "Deploy stack before IPFire syslog forwarding: Alloy must bind UDP 514 before logs arrive or first entries are silently lost"
  - "rsyslog pre-flight check placed as Section 2 (before Section 3 stack deploy): stopping rsyslog before docker compose up prevents port binding race"

# Metrics
duration: 5min
completed: 2026-03-24
---

# Phase 5 Plan 02: Telemetry Deployment Runbook and Stack Deployment Summary

**Complete 7-section deployment runbook for Phase 5 telemetry stack covering rsyslog pre-flight, Docker Compose deploy, IPFire syslog configuration, and syslog path verification**

## Performance

- **Duration:** ~5 min (Task 1 only — checkpoint pending)
- **Started:** 2026-03-24T15:01:02Z
- **Completed:** 2026-03-24 (Task 1); human checkpoint pending
- **Tasks:** 1 of 2 (Task 2 is a human checkpoint)
- **Files modified:** 1

## Accomplishments

- Created `docs/telemetry-deployment-runbook.md` — 7-section ordered procedure mirroring suricata-ids-runbook.md structure
- Runbook covers: prerequisites, rsyslog conflict pre-flight, Docker Compose stack deploy, validate-phase5.sh deploy, IPFire syslog WUI configuration, syslog path live verification, and validate-phase5.sh execution guide
- Contains sign-off checklist for all 8 TEL-0x requirements
- Embedded FORWARDFW test log injection command for end-to-end pipeline verification before relying on live IPFire traffic

## Task Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Write telemetry-deployment-runbook.md | 7c05f2d | docs/telemetry-deployment-runbook.md |
| 2 | Human checkpoint: deploy stack and verify syslog | PENDING | Live stack on 192.168.1.101 |

## Files Created/Modified

- `docs/telemetry-deployment-runbook.md` — 7 sections, ~411 lines; covers rsyslog pre-flight, Docker Compose deploy, IPFire WUI syslog config, Loki verification, and sign-off checklist covering TEL-01 through TEL-08

## Runbook Sections

| Section | Content |
|---------|---------|
| 1 | Prerequisites — SSH, Docker, repo current |
| 2 | rsyslog conflict check on supportTAK-server (pre-flight) |
| 3 | Docker Compose stack deploy — SCP files, CRLF fix, pull images, start, verify all 5 containers |
| 4 | Deploy validate-phase5.sh to supportTAK-server |
| 5 | Configure IPFire syslog forwarding via WUI (TEL-01) |
| 6 | Verify syslog path live — FORWARDFW test injection and Loki query verification |
| 7 | Run validate-phase5.sh TEL-01 through TEL-08 |

## Decisions Made

- **Deploy stack BEFORE IPFire syslog:** Stack (Alloy) must bind UDP 514 before IPFire starts forwarding. If IPFire forwards before Alloy is listening, early log entries are lost.
- **rsyslog pre-flight as Section 2:** rsyslog is stopped before docker compose up to prevent a race condition where rsyslog holds port 514 while docker-proxy attempts to bind it.

## Checkpoint: Human Verification Required

**Status:** Task 1 complete. Waiting for human to execute the runbook.

The human deployer must:
1. `scp -r C:/Users/ablan/Firewall/telemetry/ opsadmin@192.168.1.101:/opt/`
2. `ssh opsadmin@192.168.1.101 'docker compose -f /opt/telemetry/docker-compose.yml up -d'`
3. Configure IPFire syslog via WUI: https://192.168.1.1:444 > Logs > Log Settings > 192.168.1.101
4. Run `validate-phase5.sh` and confirm TEL-01 through TEL-08 pass or SKIP

**Resume signal:** Type `syslog-live` when validate-phase5.sh shows TEL-01 through TEL-08 passing (TEL-07 SKIP acceptable).

## Deviations from Plan

None — plan executed exactly as written.

## What Plan 03 Uses From This Plan

- Live Loki instance at http://192.168.1.101:3100 accepting writes
- Alloy running with Path B (EVE JSON file-read) configured in config.alloy — waiting for files in /var/log/ipfire-eve/
- /var/log/ipfire-eve/ directory created and owned by opsadmin (Step 3.4)
- rsync-eve.sh deployed to /opt/telemetry/scripts/ — needs SSH key and cron job in Plan 03

## Self-Check: PASSED

- `docs/telemetry-deployment-runbook.md` exists: FOUND
- Commit 7c05f2d (Task 1 - runbook): FOUND
