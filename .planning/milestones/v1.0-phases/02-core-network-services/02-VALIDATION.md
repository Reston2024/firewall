---
phase: 2
slug: core-network-services
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-22
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bash shell scripts (IPFire appliance) |
| **Config file** | None — scripts in `scripts/` directory |
| **Quick run command** | `bash /root/firewall-repo/scripts/validate-services.sh` |
| **Full suite command** | `bash /root/firewall-repo/scripts/validate-phase2.sh` |
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
| 2-01-01 | 01 | 1 | SVC-01 | integration | DHCP lease from GREEN client | ⬜ pending |
| 2-01-02 | 01 | 1 | SVC-02 | integration | Static lease assignment | ⬜ pending |
| 2-01-03 | 01 | 1 | SVC-03 | integration | `drill -D sigok.verteiltesysteme.net` AD flag | ⬜ pending |
| 2-01-04 | 01 | 1 | SVC-04 | integration | `grep forward-tls-upstream /etc/unbound/forward.conf` | ⬜ pending |
| 2-01-05 | 01 | 1 | SVC-05 | integration | `ntpq -p` shows sync | ⬜ pending |
| 2-01-06 | 01 | 1 | SVC-06 | integration | Services running after reboot | ⬜ pending |

---

## Wave 0 Requirements

- [ ] `scripts/validate-services.sh` — checks DHCP, DNS, NTP on IPFire
- [ ] `scripts/validate-phase2.sh` — full Phase 2 integration tests
- [ ] `configs/dhcp/` — DHCP config exports
- [ ] `configs/dns/` — DNS/Unbound config exports

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Client gets correct DHCP lease | SVC-01 | Needs GREEN client | Release/renew DHCP on client, verify IP/gateway/DNS/NTP |
| DoT active on wire | SVC-04 | Needs tcpdump | `tcpdump -i red0 port 853` shows TLS traffic |
| NTP client sync | SVC-05 | Needs client | Check client clock convergence |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Wave 0 covers all MISSING references
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
