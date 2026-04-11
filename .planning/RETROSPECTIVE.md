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

## Milestone: v2.0 — Local AI SOC

**Shipped:** 2026-04-10 (passed_with_partial — TRI-06 desktop-side forwarder v2.1)
**Phases:** 6 (9, 10, 11 retracted, 12, 13, 14) | **Plans:** 12 | **Commits:** 5 in closure session + prior work

### What Was Built
- Malcolm NSM on supportTAK-server: 27/27 containers, OpenSearch 6 GB heap + Logstash 2 GB heap under 16 GB RAM budget, 123K+ Suricata alerts + 628K+ syslog docs indexed
- Complete telemetry migration from Loki/Alloy/Grafana to Malcolm (Phase 10)
- Live SPAN capture via GS308EP managed switch + USB 2.5GbE adapter, Zeek (2 workers) + Suricata live (2 threads) + Arkime all healthy
- ChromaDB RAG pipeline on supportTAK, 387 chunks, all-MiniLM-L6-v2, 10/10 query validation (Phase 12)
- ADR-E04 data-layer / analysis-layer split: all AI inference on desktop SOC (RTX 5080, qwen3:14b), supportTAK is data layer only
- Execution-receipt schema v1.0.0 and 6-gate executor contract per ADR-E01
- TRI-06 E2E validation rails (validate-tri06.sh), reference emitter (emit-receipt.sh), one-page "railroad meeting point" contract, 5 reference receipt examples
- Host-aware validate-all.sh orchestrator (v1.0 phases 1-6 + v2.0 phases 9, 10, 13, 14 + TRI-06)
- Supply chain: syft 1.42.4 + grype 0.111.0 + cosign 3.0.6 on supportTAK, CycloneDX SBOMs (repo + dpkg-scoped system), distro-aware grype with 68 High / 14,423 Medium CVEs disclosed, cosign v3 keyless Sigstore signature on release bundle

### What Worked
- **"Meet in the middle like the railroad" contract pattern.** Rather than trying to own both the data layer and the analysis layer, the Firewall repo owns the schema + rails and the local-ai-soc repo owns the forwarder. Both repos point at the same `contracts/execution-receipt.schema.json`, and `validate-tri06.sh` reads field names from the schema file so the validator can't drift from the contract. Clean separation.
- **Fix-at-discovery > fix-at-audit.** Phase 3 orchestration work exposed four stale checks in other validators (MAL-01c equality check, MAL-01e over-broad OOM grep, MAL-06 assuming pre-SPAN world, validate-phase14.sh FAIL-when-releases-missing). All four were fixed in-situ rather than carried as tech debt. The resulting validators now reflect reality and the release gate passes honestly.
- **Smoke test with a dedicated prefix.** Writing the TRI-06 write-path smoke test to `triage-results-smoketest-YYYYMMDD` rather than the real `triage-results-*` prefix — combined with a `must_not wildcard _index smoketest-*` in validate-tri06.sh — meant I could exercise the rails without polluting the audit gate. Defense in depth for operator-left debris.
- **Narrow syft scope when OOM matters.** The original `syft packages /` OOM-killed the scanner on the memory-constrained N150. Switching to `syft scan dir:/var/lib/dpkg` captured the actionable CVE signal (all Ubuntu packages with CPEs) in a bounded memory footprint. Scope matters more than completeness when resources are tight.
- **Distro-aware grype.** The narrow syft scope lost the /etc/os-release signal, so grype initially reported zero CVEs — a dangerous false negative. Detecting the distro at grype-run time and passing `--distro ubuntu:22.04` explicitly turned zero findings into 68 High + 14K Medium, which is the real world. Industry best practice: CVE reports at release time are audit evidence, not go/no-go gates (NIST SSDF PO.1.1).
- **Cosign v3 keyless for a local-first project.** No CI infrastructure needed, just one OAuth device flow per release. Signature is anchored to a real GitHub identity in the Sigstore transparency log (Rekor). v2.1 can move to GitHub Actions OIDC for automation.

### What Was Inefficient
- **Two cosign device flow cycles.** First attempt expired while I was explaining options to the user. Lesson: warn about the 300-second timer *before* starting cosign, not during.
- **Initial SBOM dry run OOM'd.** Could have predicted it from Phase 0 preflight (supportTAK was at 77% RAM + 99% swap before starting) but chose to try the full scope first. Should have gone narrow from the start; lost ~5 min + generated an OOM entry in dmesg that then had to be filtered out in MAL-01e.
- **Validate-all.sh wasn't covering v2.0 phases** — latent since Phase 9 deployment. Meant the "release gate passes" claim in CLAUDE.md was untestable until this session. Should have extended the orchestrator incrementally at each v2.0 phase completion.
- **Three stale Phase 9 checks** carried latent for weeks because nobody ran the full suite after SPAN hardware was acquired. validate-phase9.sh MAL-06 literally asserted "Arkime disabled" after Arkime was explicitly re-enabled. Validators drift invisibly unless they're run.
- **.gitignore `*.tar.gz` rule was too broad.** Would have silently dropped the signed release bundle. Caught by testing `git check-ignore` before commit. Lesson: always test negation-override rules in gitignore with a dummy file before relying on them.

### Patterns Established
- **Receipt contract as a shared schema.** `contracts/execution-receipt.schema.json` is the single source of truth, referenced by `scripts/validate-tri06.sh`, `scripts/emit-receipt.sh`, `docs/tri06-receipt-contract.md`, `examples/receipts/*`. One file to update, everything else follows.
- **Host-aware validation orchestrator.** `validate-all.sh` detects its host (IPFire vs supportTAK vs laptop) and scopes phases to what can actually run there. No more "run this from IPFire OR the laptop and manually combine".
- **SCA tooling on the host with the tools, not the repo.** `generate-sbom.sh` auto-detects when it's running on supportTAK and skips the self-loopback SSH. Works from any checkout location with the right tools.
- **SKIP-acceptable for temporal gates.** TRI-06.3 and TRI-06.4 SKIP when no real receipts exist yet, PASS when they do. Same script, different gate state. Non-zero exit only on FAIL.
- **Placeholder rejection at emit time.** `emit-receipt.sh` explicitly rejects `REPLACE_WITH_FRESH_UUID` so examples can't be used unsubstituted. Catches operator errors before they pollute the audit trail.

### Key Lessons
1. **Run the full validation suite whenever the world changes, not just at milestone closure.** Three stale Phase 9 checks went undetected for a month because nobody ran them after the SPAN hardware was acquired. Validators are tests; untested tests rot.
2. **Narrow scope beats complete scope when memory is bounded.** Full rootfs SBOM was academically correct and operationally OOM-inducing. dpkg-only scope is the right answer for a N150 running Malcolm, and it's the answer NIST SSDF actually asks for (actionable CVE signal, not exhaustive inventory).
3. **Distro-aware CVE scans are non-negotiable.** An SBOM without distro metadata gives grype zero signal; the tooling doesn't warn loudly, it silently returns zero findings. Always pass `--distro` explicitly when the SBOM doesn't embed it.
4. **Cosign v3 is a breaking change from v2.** `--bundle` is mandatory, keyless verify requires `--certificate-identity` (or `-regexp`). Scripts written for v2 will silently fail to verify under v3. Pin the version.
5. **Cross-repo contracts need a single schema file, owned by exactly one repo.** Two copies drift. Neither repo owning unilaterally invites ambiguity. Firewall owns `contracts/execution-receipt.schema.json`; local-ai-soc reads it and conforms.
6. **SKIP is a legitimate signal, not a failure in disguise.** CLAUDE.md says "SKIP ≠ FAIL" and the v2.0 audit leans into that hard: 8 SKIPs on the final validate-all.sh run, every one with a documented reason, and the release ships honestly with TRI-06 as a partial closure rather than a fake PASS from a hand-crafted test receipt.
7. **Two-party E2E tests need a contract-first handoff.** The desktop team doesn't need to know the Firewall repo; they need the schema, the reference emitter, and the validation script. The contract document is the API.

### Cost Observations
- Model mix: single-session Opus 4.6 (1M context)
- Single session: ~6 hours elapsed, 5 git commits + v2.0.0 tag
- Notable: host-aware orchestrator refactor + 4 stale-check fixes in Phase 3 was unplanned scope creep; the plan said "extend validate-all.sh" but the extension surfaced debt that had to be fixed to make the release gate pass. Net cost was small (~30 min) and yielded a healthier validator suite than started with.

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Commits | Phases | Key Change |
|-----------|---------|--------|------------|
| v1.0 | 124 | 8 | Established artifact-first pattern with human checkpoint separation |
| v2.0 | 5 (closure) + prior | 6 (1 retracted) | Two-repo "railroad" contract pattern; host-aware orchestration; SCA/Sigstore keyless signing |

### Cumulative Quality

| Milestone | Validation Scripts | Requirements | Gap Closure Phases |
|-----------|-------------------|--------------|-------------------|
| v1.0 | 7 (per-phase + validate-all.sh) | 65/65 | 1 (Phase 8) |
| v2.0 | 12 (per-phase + validate-tri06.sh + validate-all.sh with host detection) | 32/33 (1 partial) | 0 (stale checks fixed in situ) |

### Top Lessons (Verified Across Milestones)

1. Build artifacts in git first, deploy second — catches 90% of issues before touching production
2. WUI-managed files are reference-only in git — never deploy directly, always export after WUI save
3. Run the full validation suite whenever the world changes (v2.0 re-confirmed the v1.0 lesson about stale validators, this time for a stale capture config and a stale OOM grep)
4. SKIP is a first-class signal; don't conflate it with FAIL; document the reason every time
5. Cross-repo contracts live in the repo whose infrastructure hosts the artifact (schema owned by Firewall because supportTAK hosts the index)
