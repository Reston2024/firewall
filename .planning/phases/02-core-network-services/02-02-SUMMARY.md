---
phase: 02-core-network-services
plan: "02"
subsystem: dns-ntp-config-templates
tags: [dns, ntp, dot, dnssec, templates, runbook]
dependency_graph:
  requires: []
  provides:
    - configs/dns/forward.conf.template
    - configs/dns/README.md
    - configs/ntp/time-settings.template
    - configs/ntp/README.md
    - docs/services-runbook.md
  affects:
    - "02-03 (Plan 03 checkpoint uses docs/services-runbook.md as procedure document)"
tech_stack:
  added: []
  patterns:
    - "WUI-generated config template pattern: document expected output, do not deploy"
    - "ISP DNS must be disabled before TLS protocol selection (mutual exclusivity)"
    - "NTP must be enabled before DHCP NTP option to avoid WARNING log"
    - "fixleases CSV requires WUI Enable toggle to write host block to dhcpd.conf"
key_files:
  created:
    - configs/dns/forward.conf.template
    - configs/dns/README.md
    - configs/ntp/time-settings.template
    - configs/ntp/README.md
    - docs/services-runbook.md
  modified: []
decisions:
  - "Templates document expected WUI output (not deployable configs) so human can verify WUI produced correct results"
  - "Runbook orders NTP first (Section 1) to prevent DHCP NTP WARNING log from reversed configuration order"
  - "ISP DNS disable documented as first step in DNS section — mutual exclusivity failure mode from RESEARCH.md"
metrics:
  duration_minutes: 10
  completed_date: "2026-03-22"
  tasks_completed: 2
  files_created: 5
  files_modified: 0
---

# Phase 02 Plan 02: DNS and NTP Config Templates + Services Runbook Summary

**One-liner:** DNS-over-TLS and NTP reference templates plus a complete human-executable WUI deployment runbook documenting all critical ordering constraints.

## What Was Built

### Task 1: DNS and NTP Config Reference Templates (commit: 45792af)

**configs/dns/forward.conf.template** — Reference for expected `/etc/unbound/forward.conf` after WUI DNS-over-TLS configuration. Contains `forward-tls-upstream: yes` and all four resolvers with `@853#hostname` entries (Cloudflare primary/secondary, Quad9 primary/secondary). The human compares the live IPFire file to this template after WUI configuration to verify TLS is active.

**configs/dns/README.md** — Documents:
- ISP DNS critical ordering (disable ISP DNS BEFORE selecting TLS protocol — mutual exclusivity failure mode)
- DNSSEC verification with `drill -D sigok.verteiltesysteme.net` (expect `ad` flag)
- DoT wire-level verification with tcpdump on port 853/53
- Export commands for committing live configs to git
- Phase 6 dependency: outgoing firewall must allow TCP 853 for DNS-over-TLS

**configs/ntp/time-settings.template** — Reference for expected `/var/ipfire/time/settings` after WUI NTP configuration. Contains `ENABLECLIENTS=on` (confirms "Provide time to local network" is enabled) and `FORCETIMEONBOOT=on`.

**configs/ntp/README.md** — Documents:
- NTP-before-DHCP ordering constraint (enable NTP serving before setting DHCP NTP option)
- `ntpq -p` verification (star prefix = synchronized source)
- Export commands for committing live configs to git
- Phase 6 dependency: outgoing firewall must allow UDP 123 for NTP upstream sync

### Task 2: Phase 2 Services Deployment Runbook (commit: ab727c2)

**docs/services-runbook.md** — Complete human-executable WUI procedure for all three Phase 2 services. Structure:

- **Section 1 (NTP first):** Enable "Provide time to local network" before DHCP NTP option — critical ordering documented with warning explanation
- **Section 2 (DHCP):** GREEN zone setup, dynamic pool 192.168.1.100-200, DNS/NTP options pointing to 192.168.1.1; Section 2a documents the fixleases workflow including the WUI Enable toggle requirement
- **Section 3 (DNS):** ISP DNS disable (Step 1) is explicitly first before adding any TLS resolvers; Cloudflare and Quad9 TLS hostnames documented; "Check DNS Servers" button confirmation required
- **Section 4:** Config export commands (DHCP, DNS, NTP) from IPFire to git
- **Section 5:** `scripts/validate-phase2.sh` call (all automated checks must pass)
- **Section 6:** Reboot persistence test confirming SVC-06
- **Sign-Off Criteria:** Checklist of all acceptance conditions including `ALL CHECKS PASS`

## Critical Patterns Documented

1. **ISP DNS + TLS mutual exclusivity** — IPFire enforces this constraint; the disable step MUST happen before TLS protocol selection or DNS breaks silently. Documented in DNS README, forward.conf.template header, and runbook Section 3 with "CRITICAL ORDER" callout.

2. **NTP before DHCP** — Enable "Provide time to local network" in Services > Time Server before setting the DHCP NTP option field. Reversed order generates a WARNING log about NTP option pointing to a disabled server. Documented in NTP README, time-settings.template header, and runbook Section 1.

3. **fixleases WUI toggle requirement** — Writing the `fixleases` CSV file with `enabled=on` is NOT sufficient. Each entry must be toggled Enable off/on in the WUI to force dhcpd.conf host block generation. Without the host block, the daemon does not assign the static IP. Documented in runbook Section 2a.

4. **Templates are not deployable** — Both config templates document expected WUI output for verification. They must not be deployed to IPFire — WUI would overwrite them. The pattern is: configure in WUI, export actual file, compare to template.

## What Plan 03 Uses

- **docs/services-runbook.md** is the procedure document for the Plan 03 checkpoint. The human follows it to configure DHCP, DNS, and NTP in the IPFire WUI before the Plan 03 checkpoint verification.
- **configs/dns/forward.conf.template** is the reference the runbook points to for verifying DNS-over-TLS configuration correctness.
- **scripts/validate-phase2.sh** (created in Plan 01) is called in runbook Section 5 — all checks must pass before sign-off.

## Deviations from Plan

None — plan executed exactly as written. Both tasks completed with all acceptance criteria verified.

## Known Stubs

None. All templates contain complete, accurate reference data. The runbook is complete and executable without additional information. No placeholder values or TODO items.

## Self-Check: PASSED

Files created:
- [x] configs/dns/forward.conf.template — FOUND
- [x] configs/dns/README.md — FOUND
- [x] configs/ntp/time-settings.template — FOUND
- [x] configs/ntp/README.md — FOUND
- [x] docs/services-runbook.md — FOUND

Commits:
- [x] 45792af — feat(02-02): add DNS and NTP config reference templates — FOUND
- [x] ab727c2 — docs(02-02): add Phase 2 services deployment runbook — FOUND
