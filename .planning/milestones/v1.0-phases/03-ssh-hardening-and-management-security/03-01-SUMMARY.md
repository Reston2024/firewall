---
phase: 03-ssh-hardening-and-management-security
plan: "01"
subsystem: ssh-management
tags: [ssh, firewall, guardian, validation, runbook]
dependency_graph:
  requires: [02-02-PLAN.md]
  provides: [validate-phase3.sh, firewall.local-extended, sshd_config.hardened, ssh-management-runbook.md]
  affects: [03-02-PLAN.md]
tech_stack:
  added: []
  patterns: [validate-phase2.sh pass/fail/skip pattern, firewall.local CUSTOMINPUT extension, check-before-delete iptables pattern, zone-variable guards for ORANGE_DEV/BLUE_DEV]
key_files:
  created:
    - scripts/validate-phase3.sh
    - configs/ssh/sshd_config.hardened
    - docs/ssh-management-runbook.md
  modified:
    - configs/firewall/firewall.local
decisions:
  - "firewall.local extended (not replaced) — Phase 1 broad GREEN ACCEPT rules preserved as anti-lockout fallback while Phase 3 adds management-host-specific ACCEPT rules before them"
  - "Rule ordering in firewall.local: management host ACCEPT (192.168.1.100) -> broad GREEN ACCEPT -> ORANGE DROP -> BLUE DROP — ACCEPT must precede DROP for same port per iptables first-match-wins"
  - "sshd_config.hardened is reference-only — not deployed directly because sshctrl binary manages sshd_config via WUI saves; deploying manually risks being overwritten"
  - "ORANGE_DEV and BLUE_DEV guarded with [ -n ] in firewall.local — variables are unset if zones not configured; unguarded use causes iptables syntax errors"
  - "validate-phase3.sh uses same pass/fail/skip/exit pattern as validate-phase2.sh for consistency"
metrics:
  duration_minutes: 4
  completed_date: "2026-03-22"
  tasks_completed: 3
  files_created_or_modified: 4
---

# Phase 03 Plan 01: SSH Pre-Deployment Artifacts Summary

**One-liner:** Validation script, extended firewall.local with management-IP ACCEPTs and ORANGE/BLUE DROPs, and deployment runbook for IPFire SSH hardening phase.

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | Write validate-phase3.sh | d33b815 | scripts/validate-phase3.sh |
| 2 | Extend firewall.local and create sshd_config.hardened | f9e63ff | configs/firewall/firewall.local, configs/ssh/sshd_config.hardened |
| 3 | Write ssh-management-runbook.md | cdb6531 | docs/ssh-management-runbook.md |

## Files Created / Modified

### Created

**scripts/validate-phase3.sh**
- Bash validation suite following validate-phase2.sh pattern
- Covers SSH-01 through SSH-05 with automated checks and documented SKIP items
- SSH-01: PasswordAuthentication no, PubkeyAuthentication yes, Port 22, authorized_keys existence and permissions (600/700)
- SSH-02: CUSTOMINPUT iptables ACCEPT and DROP rules for port 22
- SSH-03: Guardian binary present, service running, log/config files exist, management host in ignore list
- SSH-04: CUSTOMINPUT ACCEPT and DROP rules for port 444
- SSH-05: runbook exists, 15-minute expiry documented
- Exits 0 on all-pass, exits 1 on any FAIL

**configs/ssh/sshd_config.hardened**
- Reference-only file documenting expected post-WUI sshd_config state
- Marked REFERENCE ONLY — not deployed directly to IPFire
- Documents WUI checkbox -> sshd_config directive mapping
- Contains: Port 22, PasswordAuthentication no, PubkeyAuthentication yes, AllowAgentForwarding no, AllowTcpForwarding no

**docs/ssh-management-runbook.md**
- 7 sections: key generation, WUI SSH settings, firewall.local deploy, Guardian, validation, config export, 15-min expiry
- Critical ordering warnings: deploy key BEFORE disabling password, whitelist mgmt host BEFORE enabling Guardian
- CRLF warning for Windows key deployment (dos2unix required)
- Section 7 documents SSH 15-minute expiry: how it works, when to use, timer verification, emergency recovery
- Sign-off checklist maps all SSH-01 through SSH-05 requirements

### Modified

**configs/firewall/firewall.local**
- Extended with Phase 3 rules (Phase 1 rules preserved intact)
- Added MGMT_HOST variable (192.168.1.100)
- Added management-host-specific ACCEPT rules (before broad GREEN ACCEPT): port 22 and 444 from 192.168.1.100 on GREEN_DEV
- Added ORANGE_DEV DROP rules for ports 22 and 444 with `[ -n "${ORANGE_DEV}" ]` guard
- Added BLUE_DEV DROP rules for ports 22 and 444 with `[ -n "${BLUE_DEV}" ]` guard
- Mirrored all Phase 3 rules in stop case with check-before-delete pattern
- Updated header comment with Phase 3 deployment notes including CRLF fix instruction

## Key Decisions

1. **Phase 1 ACCEPT rules preserved as fallback:** The plan specification required adding management-host-specific ACCEPT rules while keeping the broad GREEN ACCEPT rules as a safety net. This is anti-lockout defense-in-depth: if the management host IP changes, the broad GREEN rule still allows management access while the specific 192.168.1.100 rule is the primary intended path.

2. **Rule ordering is critical:** iptables CUSTOMINPUT uses first-match-wins. The management host ACCEPT (192.168.1.100) is added first, then the broad GREEN ACCEPT, then ORANGE DROP, then BLUE DROP. Reversed order would cause the DROP to match before the ACCEPT.

3. **Zone-variable guards:** ORANGE_DEV and BLUE_DEV are only defined in `/var/ipfire/ethernet/settings` if those zones are configured. Unguarded use produces iptables syntax errors (empty interface name). All Phase 3 zone-specific rules use `[ -n "${VAR}" ] &&` guards.

4. **sshd_config.hardened is reference, not deployment:** The sshctrl binary modifies sshd_config on every WUI SSH save, targeting the Port directive. Manual edits risk being overwritten. The reference file documents expected state for human comparison, not for deployment.

5. **validate-phase3.sh pattern matches validate-phase2.sh:** Same pass()/fail()/skip() functions, same PASS/FAIL counters, same exit pattern. Consistency makes the validation suite predictable for operators.

## Critical Patterns Established

**firewall.local Extension Pattern:**
- Source `/var/ipfire/ethernet/settings` for zone variables
- Use `[ -n "${VAR}" ]` guards before any command using ORANGE_DEV or BLUE_DEV
- ACCEPT before DROP for same port — iptables is first-match-wins
- Check-before-delete (-C before -D) in stop case
- Preserve Phase 1 rules — Phase 3 is additive, not replacement

**validate-phase3.sh Validation Pattern:**
- `RULES=$(iptables -L CUSTOMINPUT -n)` capture once, reuse for SSH-02 and SSH-04 checks
- SKIP (not FAIL) for tests requiring live hosts on ORANGE/BLUE zones (zones may be empty)
- FAIL with actionable fix instructions embedded in message

## What Plan 02 Uses From This Plan

Plan 02 (human checkpoint) uses:
- `scripts/validate-phase3.sh` — run via `ssh root@192.168.1.1 'bash /root/firewall-repo/scripts/validate-phase3.sh'`
- `configs/firewall/firewall.local` — deploy via SCP + CRLF fix + firewall restart
- `docs/ssh-management-runbook.md` — the complete human-executable procedure (Sections 1-6 are the deployment steps)
- `configs/ssh/sshd_config.hardened` — reference for comparing live sshd_config after WUI configuration

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — all files are complete and executable. sshd_config.hardened is intentionally reference-only (by design, not a stub).

## Self-Check: PASSED

Files exist:
- scripts/validate-phase3.sh: FOUND
- configs/firewall/firewall.local: FOUND (modified)
- configs/ssh/sshd_config.hardened: FOUND
- docs/ssh-management-runbook.md: FOUND

Commits exist:
- d33b815: feat(03-01): add validate-phase3.sh
- f9e63ff: feat(03-01): extend firewall.local and add sshd_config.hardened
- cdb6531: feat(03-01): add ssh-management-runbook.md
