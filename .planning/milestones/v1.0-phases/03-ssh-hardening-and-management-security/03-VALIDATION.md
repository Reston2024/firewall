---
phase: 3
slug: ssh-hardening-and-management-security
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-22
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bash shell scripts (IPFire appliance) |
| **Config file** | None — scripts in `scripts/` directory |
| **Quick run command** | `bash /root/firewall-repo/scripts/validate-ssh.sh` |
| **Full suite command** | `bash /root/firewall-repo/scripts/validate-phase3.sh` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick validate
- **After every plan wave:** Run full suite
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | Status |
|---------|------|------|-------------|-----------|-------------------|--------|
| 3-01-01 | 01 | 1 | SSH-01 | integration | `ssh -o PasswordAuthentication=yes` rejected | ⬜ pending |
| 3-01-02 | 01 | 1 | SSH-01 | integration | `ssh -i key` succeeds from whitelist | ⬜ pending |
| 3-01-03 | 01 | 1 | SSH-02 | integration | `iptables -L CUSTOMINPUT` shows DROP for non-GREEN | ⬜ pending |
| 3-01-04 | 01 | 1 | SSH-03 | integration | `guardian.cgi` shows Guardian active | ⬜ pending |
| 3-01-05 | 01 | 1 | SSH-04 | integration | `curl -sk https://192.168.1.1:444` from GREEN | ⬜ pending |
| 3-01-06 | 01 | 1 | SSH-05 | smoke | SSH 15-min docs present | ⬜ pending |

---

## Wave 0 Requirements

- [ ] `scripts/validate-phase3.sh` — Phase 3 validation suite
- [ ] `configs/ssh/` — SSH config exports directory

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| SSH from ORANGE/BLUE dropped | SSH-02 | Needs host on ORANGE/BLUE zone | Attempt SSH from non-GREEN host |
| WUI from ORANGE/BLUE blocked | SSH-04 | Needs host on ORANGE/BLUE zone | Attempt WUI access from non-GREEN host |
| Guardian blocks visible in WUI | SSH-03 | WUI visual check | Check WUI Guardian panel after brute-force test |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Wave 0 covers all MISSING references
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
