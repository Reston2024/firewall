---
phase: 07-reproducibility-and-disaster-recovery
plan: 02
subsystem: decisions
tags: [adr, documentation, architecture, decisions]
dependency_graph:
  requires: []
  provides: [REPO-06]
  affects: [decisions/]
tech_stack:
  added: []
  patterns: [ADR format, retrospective decision capture]
key_files:
  created:
    - decisions/ADR-0005-ipfire-as-base-os.md
    - decisions/ADR-0006-guardian-over-fail2ban.md
    - decisions/ADR-0007-suricata-ids-monitor-first.md
    - decisions/ADR-0008-dns-over-tls-unbound.md
    - decisions/ADR-0009-sysctl-hardening-append.md
    - decisions/ADR-0010-ecdsa-only-wui-cert.md
    - decisions/ADR-0011-modular-validation-suite.md
    - decisions/ADR-0012-git-rebuild-as-ha-strategy.md
  modified: []
decisions:
  - "ADRs are retrospective captures of decisions already made (D-17) — all status Accepted"
  - "ADR location: decisions/ at repo root (not docs/decisions/) — matches established 4-file convention"
  - "12 total ADRs meets D-19 minimum of 8-12 ADRs for the decision log"
metrics:
  duration: 3 minutes
  completed_date: 2026-03-26
  tasks_completed: 2
  files_created: 8
---

# Phase 07 Plan 02: ADR Decision Log (ADRs 0005-0012) Summary

**One-liner:** 8 retrospective ADRs capturing IPFire base OS, Guardian brute-force, Suricata monitor-first, DNS-over-TLS, sysctl append strategy, ECDSA WUI cert, modular validation suite, and git-rebuild HA strategy.

## What Was Built

Extended the decisions/ directory from 4 to 12 ADRs, satisfying REPO-06 (decision log initialized with all architectural choices). All new ADRs follow the established format from ADR-0001 through ADR-0004 with Context, Decision, Rationale (bullet points), and Consequences sections. Status is Accepted for all (retrospective capture per D-17).

### ADRs Created

**Task 1: Platform and Security Decisions (ADRs 0005-0008)**

| ADR | Title | Key Decision |
|-----|-------|--------------|
| 0005 | IPFire as Base OS | IPFire 2.29 CU200 chosen for zone-based architecture, Pakfire, native Suricata; Docker rejected — telemetry off-box |
| 0006 | Guardian Over fail2ban | Guardian (Pakfire) chosen; fail2ban not available in Pakfire; WUI-managed brute-force protection |
| 0007 | Suricata Monitor-First | Monitor mode for initial deployment; switch to active IPS only after false-positive tuning |
| 0008 | DNS-over-TLS via Unbound | DoT to Cloudflare + Quad9 on port 853; ISP DNS disabled first (mutual exclusivity constraint) |

**Task 2: Operational and Architecture Decisions (ADRs 0009-0012)**

| ADR | Title | Key Decision |
|-----|-------|--------------|
| 0009 | Sysctl Hardening Append | Append (never overwrite) with grep-before-append idempotency; preserves ip_forward=1 |
| 0010 | ECDSA-Only WUI Cert | ECDSA-only is a platform constraint; cert not in git; documented in docs/wui-certificate.md |
| 0011 | Modular Validation Suite | Per-phase scripts (validate-phase1-6.sh) + validate-all.sh orchestrator; SKIP semantics |
| 0012 | Git-Rebuild as HA Strategy | Git repo + rebuild.sh as recovery; 15-minute RTO; IPFire never has git installed |

## Verification

- `ls decisions/ADR-*.md | wc -l` returns **12** (4 existing + 8 new)
- All 8 new ADRs contain `Status: Accepted` and all 4 required sections
- All ADRs dated 2026-03-25 (retrospective capture date)
- No ADRs created in docs/decisions/ — all in decisions/ matching established convention

## Commits

| Task | Commit | Files |
|------|--------|-------|
| Task 1: ADRs 0005-0008 | b9f45bf | ADR-0005, ADR-0006, ADR-0007, ADR-0008 |
| Task 2: ADRs 0009-0012 | 58d4001 | ADR-0009, ADR-0010, ADR-0011, ADR-0012 |

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None. All ADRs contain substantive, complete content derived from actual project decisions documented in STATE.md, CLAUDE.md, and the existing codebase. No placeholder text.

## Self-Check: PASSED
