---
phase: 04-suricata-ids-ips
plan: "01"
subsystem: suricata-ids-ips
tags: [suricata, ids, ips, validation, runbook, memcap, eve-json, integrity]
dependency_graph:
  requires: [03-01]
  provides: [validate-phase4.sh, check-suricata-integrity.sh, suricata-ids-runbook.md, suricata-yaml-eve-reference.yaml, suricata-yaml-memcap-reference.yaml]
  affects: [04-02]
tech_stack:
  added: []
  patterns: [bash-validation-suite, sha256-integrity-baseline, suricata-eve-json, n100-memcap-tuning]
key_files:
  created:
    - scripts/validate-phase4.sh
    - scripts/check-suricata-integrity.sh
    - docs/suricata-ids-runbook.md
    - configs/suricata/suricata-yaml-eve-reference.yaml
    - configs/suricata/suricata-yaml-memcap-reference.yaml
  modified: []
decisions:
  - "IDS-04 always SKIP in validate-phase4.sh — monitor mode cannot be read reliably from CLI; WUI-only verification"
  - "IDS-05 gated behind --full flag — memory check requires 30+ minutes of traffic and explicit intent"
  - "check-suricata-integrity.sh exit code 2 = WARN (hash mismatch), not FAIL — allows validate-phase4.sh to SKIP rather than FAIL on Core Update detection"
  - "stream.checksum-validation: no documented as required for Intel i226-V NIC hardware checksum offload"
  - "IDS-08 in validate-phase4.sh calls check-suricata-integrity.sh directly — single source of truth for integrity logic"
metrics:
  duration: "4 minutes"
  completed: "2026-03-22"
  tasks: 2
  files: 5
---

# Phase 04 Plan 01: Suricata IDS/IPS Pre-Deployment Artifacts Summary

**One-liner:** Created Phase 4 validation suite (IDS-01 through IDS-08), sha256-based suricata.yaml integrity script, ordered deployment runbook, and N100-tuned EVE JSON and memcap reference configs.

---

## What Was Built

### scripts/validate-phase4.sh (commit 7b62369)

Phase 4 validation suite covering all 8 IDS requirements. Follows validate-phase3.sh structure exactly: same `pass()`/`fail()`/`skip()` function signatures, same PASS/FAIL/SKIP counters, same section header style, same exit-on-FAIL pattern.

**Check coverage:**

| Req ID | Automated? | Method | Notes |
|--------|-----------|--------|-------|
| IDS-01 | Yes (PASS/FAIL) | `pgrep -o suricata` + `grep "rules loaded" suricata.log` | FAIL if no PID or < 1000 rules |
| IDS-02 | Yes (PASS/SKIP) | `grep -E "red0\|green0" suricata.log \| grep -i "running\|NFQ"` | SKIP if no zone evidence in log |
| IDS-03 | Yes (PASS/SKIP) | `find /var/lib/suricata -name "*.rules" -mmin -2880` | SKIP if < 24h since install or no rules |
| IDS-04 | Always SKIP | WUI-only — cannot read mode from CLI reliably | Documented in plan as intentional |
| IDS-05 | SKIP or PASS/FAIL | `cat /proc/$(pgrep)/status \| grep VmRSS` | Gated behind `--full` flag; FAIL if RSS > 2048MB |
| IDS-06 | Yes (PASS/FAIL) | File existence + `grep event_type` + `grep -A3 eve-log: ... enabled: yes` | FAIL if no file or no entries |
| IDS-07 | Yes (PASS/FAIL) | `grep "emerging-policy" /var/ipfire/suricata/suricata-used-rulefiles.yaml` | FAIL if emerging-policy in active rulefiles |
| IDS-08 | Yes (PASS/FAIL/SKIP) | `bash /usr/local/bin/check-suricata-integrity.sh` | Delegates to integrity script; SKIP on exit 2 (WARN) |

### scripts/check-suricata-integrity.sh (commit 7b62369)

Standalone integrity script deployed to `/usr/local/bin/check-suricata-integrity.sh` on IPFire. Designed to run after every Core Update.

- **Check 1:** `/etc/suricata/suricata.yaml` exists (exit 1 if missing)
- **Check 2:** sha256 baseline comparison (`sha256sum -c /root/suricata-yaml.sha256`). Auto-creates baseline on first run (exit 0 after creation). Prints WARN + remediation steps on hash mismatch (exit 2).
- **Check 3:** EVE JSON enabled confirmation (`grep -A2 "eve-log:" | grep "enabled: yes"`)
- **Check 4:** `stream.memcap` presence check (confirms custom tuning survived)

Exit code semantics: 0=OK, 1=FAIL (file missing or no baseline after creation attempt), 2=WARN (hash mismatch detected). This three-way exit allows `validate-phase4.sh` IDS-08 to map WARN to SKIP rather than FAIL.

### docs/suricata-ids-runbook.md (commit b8c26d3)

7-section ordered deployment procedure. Mirrors `ssh-management-runbook.md` structure: numbered sections, prerequisite blocks, verification commands after each step, sign-off checklist.

**Sections:**
1. Prerequisites (Phase 3 done, SSH key working)
2. Enable Suricata via WUI (IDS-01, IDS-02, IDS-04) — all 8 WUI steps with Surveillance mode emphasis
3. Verify EVE JSON output (IDS-06) — testmynids.org SID 2100498 test documented
4. Apply N100 memcap values (IDS-05) — sed commands for each value with fragility warning
5. Capture sha256 baseline (IDS-08) — deploy integrity script and capture initial hash
6. Run validation suite — deploy script, expected outcomes, troubleshooting table
7. Export live configs to git — post-deployment scp + commit workflow

### configs/suricata/suricata-yaml-eve-reference.yaml (commit b8c26d3)

Expected EVE JSON outputs block from IPFire CU200 suricata.yaml template. Includes `enabled: yes`, all sub-types (alert with payload/packet/metadata, http extended, dns v3, tls extended, flow). Used for comparison when a Core Update is suspected to have disabled EVE JSON.

### configs/suricata/suricata-yaml-memcap-reference.yaml (commit b8c26d3)

N100 16GB single-channel DDR5 conservative starting values: defrag 64mb, flow 128mb/prealloc 30000, stream 256mb/reassembly 512mb/depth 1mb. Documents `checksum-validation: no` requirement for i226-V hardware with explanation. Includes post-deployment verification commands as comments.

---

## Decisions Made

1. **IDS-04 always SKIP** — Monitor mode state is not readable from CLI on IPFire. The WUI writes it to internal config files not directly parseable. SKIP with WUI path instruction is correct behavior.

2. **IDS-05 gated behind `--full` flag** — Memory check requires 30+ minutes of actual traffic to be meaningful. Default run skips it with a clear instruction to use `--full`. Avoids false PASSes on freshly started Suricata.

3. **Exit code 2 = WARN in check-suricata-integrity.sh** — Using a three-way exit (0/1/2) allows `validate-phase4.sh` to distinguish between "no baseline and creation failed" (FAIL) and "hash changed = Core Update detected" (SKIP). The WARN is not a hard failure because the human must inspect and re-apply settings — it cannot be automated.

4. **`stream.checksum-validation: no`** — Intel i226-V NICs perform hardware checksum offloading. Suricata inspects packets before NIC finalizes checksums, generating floods of false positive ICMP invalid checksum alerts. Setting `no` is required hardware accommodation, not a security regression.

5. **IDS-08 delegates entirely to check-suricata-integrity.sh** — Avoids duplicating integrity logic. The script is the single source of truth and can be run standalone after Core Updates. `validate-phase4.sh` just invokes it and maps its exit code.

---

## What Plan 02 Uses from This Plan

Plan 02 is the human deployment checkpoint. It uses every artifact from Plan 01:

- `scripts/validate-phase4.sh` — Deployed to IPFire and run at end of Plan 02 to verify all IDS requirements
- `scripts/check-suricata-integrity.sh` — Deployed to `/usr/local/bin/` on IPFire in Plan 02 Section 5
- `docs/suricata-ids-runbook.md` — This IS the Plan 02 human procedure. Plan 02 is the checkpoint that gates on the human following this runbook and confirming the sign-off checklist.
- `configs/suricata/suricata-yaml-eve-reference.yaml` — Used by human in Plan 02 Section 3 to diagnose/fix EVE JSON state
- `configs/suricata/suricata-yaml-memcap-reference.yaml` — Used by human in Plan 02 Section 4 to apply correct memcap values

---

## Deviations from Plan

None — plan executed exactly as written.

The CRLF warnings from git (`LF will be replaced by CRLF the next time Git touches it`) are git autocrlf behavior on Windows. The files were written with LF-only line endings by the Write tool. The files will be served with LF endings when read; SCP/CRLF fix steps in the runbook handle any remaining CRLF issues on deployment to IPFire.

---

## Known Stubs

None. All 5 files are complete and executable. No placeholder values, no pseudocode, no TODO markers.

---

## Self-Check: PASSED

All created files exist on disk. Both commits (7b62369, b8c26d3) verified in git log.
