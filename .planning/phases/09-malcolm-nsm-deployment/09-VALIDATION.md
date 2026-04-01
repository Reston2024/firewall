---
phase: 9
slug: malcolm-nsm-deployment
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-01
---

# Phase 9 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Shell scripts + SSH remote commands |
| **Config file** | none — infrastructure validation only |
| **Quick run command** | `ssh opsadmin@192.168.1.22 "sudo docker compose -f /opt/malcolm/docker-compose.yml ps --format '{{.Name}} {{.Status}}'"` |
| **Full suite command** | `bash scripts/validate-phase9.sh` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick Docker ps check
- **After every plan wave:** Run `bash scripts/validate-phase9.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 09-01-01 | 01 | 1 | MAL-01 | integration | `ssh opsadmin@192.168.1.22 "docker compose -f /opt/malcolm/docker-compose.yml ps"` | ❌ W0 | ⬜ pending |
| 09-01-02 | 01 | 1 | MAL-05 | integration | `ssh opsadmin@192.168.1.22 "free -m \| grep Mem"` | ❌ W0 | ⬜ pending |
| 09-02-01 | 02 | 2 | MAL-04 | integration | `ssh opsadmin@192.168.1.22 "curl -sk https://localhost:5601/api/status"` | ❌ W0 | ⬜ pending |
| 09-02-02 | 02 | 2 | MAL-06 | integration | `ssh opsadmin@192.168.1.22 "docker stats --no-stream --format '{{.Name}} {{.MemUsage}}' \| grep arkime"` | ❌ W0 | ⬜ pending |
| 09-03-01 | 03 | 2 | MAL-04 | integration | `ssh opsadmin@192.168.1.22 "curl -sk -XGET 'https://localhost:9200/_plugins/_ism/policies'"` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scripts/validate-phase9.sh` — validation script covering MAL-01, MAL-04, MAL-05, MAL-06
- [ ] SSH key access from Windows PC to supportTAK-server (already established)

*Existing SSH infrastructure covers remote command execution.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| OpenSearch Dashboards visual inspection | MAL-04 | Dashboard rendering requires browser | Navigate to https://192.168.1.22:5601, verify prebuilt dashboards load |
| Arkime UI disabled state | MAL-06 | Visual confirmation of no active sessions | Navigate to Arkime UI, confirm no active PCAP sessions |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
