# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0 — Firewall Appliance

**Shipped:** 2026-03-26
**Phases:** 8 | **Plans:** 27 | **Commits:** 124

### What Was Built
- Fully hardened IPFire firewall appliance on Intel N100 6-NIC mini-PC
- Off-box telemetry pipeline (rsyslog→Alloy→Loki→Grafana) with threat-tracing dashboards
- Complete reproducibility: rebuild.sh restores from git in <15 minutes
- 12 ADRs documenting all architectural decisions
- 7-category rollback procedures with tested scripts
- Full validation suite (validate-all.sh) covering 6 verification phases

### What Worked
- **Artifact-first planning**: Building configs, scripts, and validation in git before touching the live appliance meant deployment was just SCP + run. Zero rework on the appliance itself.
- **Phase dependency chain**: Strict ordering (NIC→services→SSH→IDS→telemetry→hardening→reproducibility) prevented backtracking. Each phase built cleanly on the previous.
- **Validation scripts per phase**: Automated pass/fail checks meant deployment verification was instant — no manual checklists to forget.
- **Human checkpoint plans**: Separating "code execution" plans from "WUI deployment" plans made the workflow natural — Claude builds artifacts, human deploys via WUI, Claude validates via SSH.
- **Off-box telemetry decision**: Moving Docker to supportTAK-server avoided the Docker-on-IPFire trap entirely. Clean architecture separation.

### What Was Inefficient
- **Live config export timing**: Should have exported live configs (dhcpd.conf, sshd_config, etc.) immediately after each phase WUI deployment, not as a batch at milestone end. Created a gap closure phase that was avoidable.
- **Suricata dashboard placeholder**: Grafana Labs API was unavailable during execution, forcing a placeholder JSON. Should have had a fallback plan (manual export from another Grafana instance).
- **Runbook Section 2 rsyslog error**: The initial telemetry runbook incorrectly instructed to disable rsyslog, when the actual architecture requires rsyslog as a relay. Discovered during live deployment — should have been caught by research agent.
- **STATE.md plan counts out of sync**: The roadmap showed "In Progress" for phases that had been deployed on the live box but whose human checkpoint SUMMARY.md files hadn't been written. State tracking should reflect deployment reality, not just SUMMARY.md existence.

### Patterns Established
- **WUI-managed file exclusion**: Files that IPFire WUI overwrites (ethernet/settings) must NOT be in drift detection or git-managed deploys — discovered as INT-4A gap
- **check-before-modify pattern**: grep-before-append for sysctl, iptables -C before -D, idempotent everywhere
- **SKIP vs FAIL in validation**: SKIP is acceptable (manual-only check, optional infrastructure); FAIL is never acceptable
- **Zone-variable guards**: `[ -n "$ORANGE_DEV" ]` before using zone variables in firewall.local — prevents syntax errors when zones aren't configured
- **SHA256 integrity baselines**: Capture hash immediately after config changes, before Core Updates can overwrite

### Key Lessons
1. **Export live configs in the same session you deploy them** — eliminates an entire gap closure cycle
2. **rsyslog is always a relay on IPFire** — it receives syslog, writes to file, Alloy tails the file. Never try to replace it.
3. **IPFire WUI owns certain files** — sshd_config (via sshctrl), ethernet/settings, guardian.conf. Reference-only copies in git, not deployable.
4. **Test the research agent's assumptions against live behavior** — the rsyslog architecture mismatch was the single biggest rework item
5. **Human checkpoint plans work best when they're just "follow runbook + type signal word"** — minimal cognitive load on the human

### Cost Observations
- Model mix: ~70% sonnet, ~25% opus (planning/verification), ~5% haiku (research)
- Sessions: ~15 across 6 days
- Notable: Phase 8 gap closure could have been avoided with better Phase 5 config export discipline

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Commits | Phases | Key Change |
|-----------|---------|--------|------------|
| v1.0 | 124 | 8 | Established artifact-first pattern with human checkpoint separation |

### Cumulative Quality

| Milestone | Validation Scripts | Requirements | Gap Closure Phases |
|-----------|-------------------|--------------|-------------------|
| v1.0 | 7 (per-phase + validate-all.sh) | 65/65 | 1 (Phase 8) |

### Top Lessons (Verified Across Milestones)

1. Build artifacts in git first, deploy second — catches 90% of issues before touching production
2. WUI-managed files are reference-only in git — never deploy directly, always export after WUI save
