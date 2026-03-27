---
phase: 1
slug: platform-foundation-and-firewall
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-21
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bash shell scripts (IPFire appliance — no external test framework) |
| **Config file** | None — scripts live in `scripts/` directory in the git repo |
| **Quick run command** | `bash /root/firewall-repo/scripts/validate-nics.sh` |
| **Full suite command** | `bash /root/firewall-repo/scripts/validate-phase1.sh` |
| **Estimated runtime** | ~15 seconds (excluding reboot persistence test) |

---

## Sampling Rate

- **After every task commit:** Run `bash /root/firewall-repo/scripts/validate-nics.sh`
- **After every plan wave:** Run `bash /root/firewall-repo/scripts/validate-phase1.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 1-01-01 | 01 | 1 | PLAT-01 | integration | `bash scripts/validate-nics.sh` | ❌ W0 | ⬜ pending |
| 1-01-02 | 01 | 1 | PLAT-01 | integration | `reboot; ssh ipfire bash scripts/validate-nics.sh` | ❌ W0 | ⬜ pending |
| 1-01-03 | 01 | 1 | PLAT-02 | integration | `nc -zv 192.168.1.1 222` | ❌ W0 | ⬜ pending |
| 1-01-04 | 01 | 1 | PLAT-02 | integration | `curl -sk https://192.168.1.1:444` | ❌ W0 | ⬜ pending |
| 1-01-05 | 01 | 1 | PLAT-03 | smoke | `ls /root/firewall-repo/{configs,scripts,docs,...}` | ❌ W0 | ⬜ pending |
| 1-01-06 | 01 | 1 | PLAT-05 | smoke | `grep udev /var/ipfire/backup/include.user` | ❌ W0 | ⬜ pending |
| 1-02-01 | 02 | 2 | FW-01 | integration | `nmap -Pn -p 80,443,22 <RED_IP>` | Manual | ⬜ pending |
| 1-02-02 | 02 | 2 | FW-02 | integration | `curl http://checkip.amazonaws.com` from GREEN | Manual | ⬜ pending |
| 1-02-03 | 02 | 2 | FW-03 | integration | `ping ORANGE_IP` from GREEN — should timeout | Manual | ⬜ pending |
| 1-02-04 | 02 | 2 | FW-05 | smoke | `grep 'DROP\|FORWARDFW' /var/log/messages` | ❌ W0 | ⬜ pending |
| 1-02-05 | 02 | 2 | FW-06 | integration | `iptables -L` after reboot — rules present | ❌ W0 | ⬜ pending |
| 1-02-06 | 02 | 2 | FW-07 | smoke | `iptables -L CUSTOMINPUT -n -v` shows 222+444 | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scripts/validate-nics.sh` — validates PLAT-01 MAC-to-zone mapping
- [ ] `scripts/validate-phase1.sh` — runs all Phase 1 integration tests
- [ ] `docs/nic-map.md` — physical port documentation template
- [ ] `configs/udev/30-persistent-network.rules` — template with correct structure
- [ ] `configs/firewall/firewall.local` — working template with management allow rules

*All test files require live hardware to determine actual MAC addresses — Wave 0 creates the framework with placeholder values.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Inbound from RED blocked | FW-01 | Requires external vantage point | nmap from outside WAN against RED IP — all ports filtered |
| GREEN reaches internet | FW-02 | Requires GREEN client | curl checkip.amazonaws.com from GREEN host |
| GREEN cannot reach ORANGE | FW-03 | Requires GREEN + ORANGE hosts | ping ORANGE IP from GREEN — must timeout |
| Hostname set correctly | PLAT-04 | One-time WUI/console check | `hostname` returns expected value |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
