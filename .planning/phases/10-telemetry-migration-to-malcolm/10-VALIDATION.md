---
phase: 10
slug: telemetry-migration-to-malcolm
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-02
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Shell scripts + SSH remote commands |
| **Config file** | none — infrastructure validation only |
| **Quick run command** | `ssh opsadmin@192.168.1.22 "docker compose -f /opt/malcolm/docker-compose.yml ps --format '{{.Name}} {{.Status}}' \| head -10"` |
| **Full suite command** | `bash scripts/validate-phase10.sh` |
| **Estimated runtime** | ~45 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick Docker ps + data flow check
- **After every plan wave:** Run `bash scripts/validate-phase10.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 45 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 10-01-01 | 01 | 1 | MAL-02 | integration | `ssh opsadmin@192.168.1.22 "docker exec malcolm-opensearch-1 curl -sk ..." \| grep eve` | ❌ W0 | ⬜ pending |
| 10-01-02 | 01 | 1 | MAL-03 | integration | `ssh opsadmin@192.168.1.22 "docker exec malcolm-opensearch-1 curl -sk ..." \| grep syslog` | ❌ W0 | ⬜ pending |
| 10-02-01 | 02 | 2 | MIG-01 | integration | Parallel validation — both Loki and Malcolm receiving | ❌ W0 | ⬜ pending |
| 10-02-02 | 02 | 2 | MIG-02 | integration | `ssh opsadmin@192.168.1.22 "docker ps" \| grep -v malcolm` should be empty | ❌ W0 | ⬜ pending |
| 10-03-01 | 03 | 2 | MIG-03 | integration | `bash scripts/validate-phase10.sh --full` | ❌ W0 | ⬜ pending |
| 10-03-02 | 03 | 2 | MIG-04 | review | Runbook contains no Alloy/Loki/SCP references | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scripts/validate-phase10.sh` — validation script covering MAL-02, MAL-03, MIG-01 through MIG-04
- [ ] SSH key access to supportTAK-server (already established)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Suricata alert visible in Malcolm UI | MAL-02 | Requires browser inspection of dashboard data | Open https://192.168.1.22, navigate to Suricata Alerts dashboard, confirm alert events |
| Runbook accuracy review | MIG-04 | Requires human judgment on documentation | Read docs/telemetry-deployment-runbook.md, confirm no Alloy/Loki/SCP references |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 45s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
