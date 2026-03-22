---
phase: 4
slug: suricata-ids-ips
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-22
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bash shell scripts (IPFire appliance) |
| **Config file** | None — scripts in `scripts/` directory |
| **Quick run command** | `bash /root/firewall-repo/scripts/validate-suricata.sh` |
| **Full suite command** | `bash /root/firewall-repo/scripts/validate-phase4.sh` |
| **Estimated runtime** | ~30 seconds (includes EVE JSON wait) |

---

## Sampling Rate

- **After every task commit:** Run quick validate
- **After every plan wave:** Run full suite
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | Status |
|---------|------|------|-------------|-----------|-------------------|--------|
| 4-01-01 | 01 | 1 | IDS-01 | integration | Suricata running, eve.json exists | ⬜ pending |
| 4-01-02 | 01 | 1 | IDS-02 | integration | Zone selection verified in WUI | ⬜ pending |
| 4-01-03 | 01 | 1 | IDS-03 | integration | Rule update cron active | ⬜ pending |
| 4-01-04 | 01 | 1 | IDS-04 | integration | Monitor mode active | ⬜ pending |
| 4-01-05 | 01 | 1 | IDS-05 | integration | Memory check after traffic | ⬜ pending |
| 4-01-06 | 01 | 1 | IDS-06 | integration | EVE JSON entries present | ⬜ pending |
| 4-01-07 | 01 | 1 | IDS-07 | smoke | Safe rule categories only | ⬜ pending |
| 4-01-08 | 01 | 1 | IDS-08 | integration | Post-update config hash check | ⬜ pending |

---

## Wave 0 Requirements

- [ ] `scripts/validate-phase4.sh` — Phase 4 validation suite
- [ ] `scripts/check-suricata-config.sh` — Post-Core-Update suricata.yaml integrity check
- [ ] `configs/suricata/` — Suricata config exports directory

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Test signature alert | IDS-01/02 | Requires curl to test-IDS URL | `curl http://testmynids.org/uid/index.html` then check eve.json |
| Memory after 30 min | IDS-05 | Requires time passage | Check VmRSS after 30 min normal traffic |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Wave 0 covers all MISSING references
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
