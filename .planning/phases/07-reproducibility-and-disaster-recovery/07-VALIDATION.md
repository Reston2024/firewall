---
phase: 07
slug: reproducibility-and-disaster-recovery
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-25
---

# Phase 07 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash scripts (validate-all.sh, check-drift.sh, check-integrity.sh) |
| **Config file** | none — uses existing validation infrastructure |
| **Quick run command** | `ssh -i ~/.ssh/ipfire_ed25519 root@192.168.1.1 'bash /root/firewall-repo/scripts/validate-phase6.sh'` |
| **Full suite command** | `ssh -i ~/.ssh/ipfire_ed25519 root@192.168.1.1 'bash /root/firewall-repo/scripts/validate-all.sh'` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick validation (relevant script)
- **After every plan wave:** Run full suite via validate-all.sh
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 07-01-01 | 01 | 1 | REPO-01 | file-check | `ls configs/ -R` | ✅ | ⬜ pending |
| 07-01-02 | 01 | 1 | REPO-04 | script | `bash check-drift.sh` | ❌ W0 | ⬜ pending |
| 07-02-01 | 02 | 2 | REPO-02 | script | `bash rebuild.sh --dry-run` | ❌ W0 | ⬜ pending |
| 07-03-01 | 03 | 3 | REPO-05 | file-check | `ls rollback/` | ❌ W0 | ⬜ pending |
| 07-04-01 | 04 | 4 | REPO-06 | file-check | `ls decisions/ADR-*.md` | ✅ partial | ⬜ pending |
| 07-04-02 | 04 | 4 | REPO-03 | script | `diff pakfire-manifest-expected.txt pakfire-manifest.txt` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scripts/check-drift.sh` — full file manifest drift detection script
- [ ] `scripts/rebuild.sh` — master rebuild orchestrator
- [ ] `rollback/README.md` — rollback procedure documentation

*Created during plan execution, not as prerequisites.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Rebuild on fresh IPFire | REPO-02 | Requires fresh IPFire install | Install fresh IPFire, run rebuild.sh, verify validate-all.sh passes |
| Rollback tested per category | REPO-05 | Requires intentional config change + rollback | Make a change, run rollback script, verify original state restored |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
