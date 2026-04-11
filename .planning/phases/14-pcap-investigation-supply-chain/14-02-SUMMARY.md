---
phase: 14-pcap-investigation-supply-chain
plan: 02
status: complete
started: 2026-04-10
completed: 2026-04-10
duration_minutes: 75
---

# Phase 14 Plan 02 Summary: SCA-01..04 tooling + signed release bundle

## What Was Built

Live supply-chain tooling on supportTAK-server and a signed CycloneDX
release bundle for `v2.0.0`, closing SCA-01 through SCA-04. The tooling
in Plan 01 was script-only; this plan actually installed the tools,
fixed the scripts against three correctness issues discovered during
the dry run, and produced real artifacts.

### Tools installed on supportTAK-server (`/usr/local/bin`)

| Tool | Version | Purpose |
|---|---|---|
| syft | 1.42.4 | CycloneDX SBOM generation (repo + system) |
| grype | 0.111.0 | CVE scan against generated SBOMs |
| cosign | 3.0.6 | Keyless Sigstore bundle signing (`--bundle`) |

### Correctness fixes in `scripts/generate-sbom.sh`

1. **Narrow system scope (OOM avoidance).** Original script called
   `sudo syft packages /`. On the N150 with Malcolm 27/27 containers
   and ~11 GB baseline RAM use, the full rootfs scan OOM-killed syft
   at 3.14 GB RSS. Switched to `syft scan dir:/var/lib/dpkg` which
   captures every installed Debian package with CPE strings in a
   ~5 MB CycloneDX document, bounded memory, no Docker layer overhead.
   The dpkg DB is the right scope for OS-level CVE matching; Python
   venvs on this box are installed via dpkg (python3-*), so they're
   captured.
2. **Distro-aware grype (false-negative fix).** With the dpkg-only
   scope, syft cannot embed the distro in SBOM metadata; grype without
   a distro silently matches against a distro-agnostic feed and
   reports **ZERO** Ubuntu CVEs — a dangerous false negative. Fixed by
   sourcing `/etc/os-release` at script run time and passing
   `--distro "${ID}:${VERSION_ID}"` to grype explicitly. Before fix:
   0 CVEs reported. After fix: 68 High, 14,423 Medium, 990 Low, 280
   Negligible, 0 Critical on the live Ubuntu 22.04 system.
3. **Cosign v3 version assertion + install hint.** Script previously
   pointed at `go install github.com/sigstore/cosign/v2/cmd/cosign@latest`
   (v2 module). Replaced with v3 binary download (cosign v3 is required
   because `--bundle` is mandatory in v3). Added runtime assertion that
   `cosign version` reports v3.x; script exits with a clear error on
   v2.x.
4. **Local-vs-SSH detection for SCA-02.** Original script always
   SSHed `opsadmin@192.168.1.22` for the system SBOM. When the script
   runs on supportTAK itself (as it does for the release run), that's
   self-loopback SSH which requires separate key setup. Fixed with a
   hostname/IP detect that runs `sudo syft scan ...` locally if already
   on supportTAK, otherwise SSH as before.

### New files

- `scripts/validate-phase14.sh` — SCA-01..05 + PCAP-01/04 checks. Skips
  SCA-01..04 cleanly when `releases/${TAG}/` is absent (orchestration
  friendly). PCAP-02/03 are fixed SKIPs per ADR-E03 deferral state.
  Cosign verify uses `--certificate-identity-regexp` and
  `--certificate-oidc-issuer-regexp` (permissive by default, pin via
  `FIREWALL_COSIGN_IDENTITY` / `FIREWALL_COSIGN_ISSUER` env vars).

### Release artifacts (`releases/v2.0.0/`)

| File | Purpose |
|---|---|
| `sbom-repo.json` | CycloneDX JSON, repo scope (`syft dir:.`) |
| `sbom-system.json` | CycloneDX JSON, system scope (`syft scan dir:/var/lib/dpkg`, 5.1 MB) |
| `grype-repo.txt` | Grype table output against repo SBOM (no vulns — shell-script repo has no manifests) |
| `grype-system.txt` | Grype table output against system SBOM with `--distro ubuntu:22.04` (14,762 lines) |
| `v2.0.0-bundle.tar.gz` | Tarball of the four above |
| `v2.0.0-bundle.cosign` | Cosign v3 Sigstore bundle (keyless, Rekor tlog entry) |

### CVE findings (disclosed, non-blocking)

Ubuntu 22.04 LTS system scan:

| Severity | Count |
|---|---|
| Critical | 0 |
| High | 68 |
| Medium | 14,423 |
| Low | 990 |
| Negligible | 280 |

Representative Highs include CVE-2023-44487 (HTTP/2 rapid reset, CISA
KEV) in nodejs 12.22.9 (EOL), CVE-2024-9680 in libmozjs-91-0, and
multiple libqt5webkit5 "won't fix" findings inherited from the upstream
archive. Per NIST SSDF PO.1.1/PS.3.2 the CVE report is **audit
evidence at release time**, not a go/no-go gate. Remediation is tracked
in v2.1+: triage each High, either upgrade, mitigate, or accept-with-
rationale; SPDX/CycloneDX VEX statements can be added to future bundles
as findings are dispositioned.

### Signing identity (pinnable for strict verify)

- Identity: `ablanks10@gmail.com`
- Issuer: `https://github.com/login/oauth`
- Verify command with strict pinning:
  ```bash
  cosign verify-blob --bundle releases/v2.0.0/v2.0.0-bundle.cosign \
    --certificate-identity='ablanks10@gmail.com' \
    --certificate-oidc-issuer='https://github.com/login/oauth' \
    releases/v2.0.0/v2.0.0-bundle.tar.gz
  ```

## Key Outcomes

- `scripts/validate-phase14.sh`: 7 PASS / 0 FAIL / 2 SKIP (PCAP-02/03
  deferred) against dry-run `releases/v2.0.0-rc/` artifacts.
- `cosign verify-blob --bundle` succeeds on supportTAK with both the
  permissive default regex and the strict pinned identity/issuer.
- Release process is fully reproducible: `scripts/generate-sbom.sh
  v2.0.0` on a host with syft + grype + cosign-v3 produces the signed
  bundle, and `scripts/validate-phase14.sh` confirms it end-to-end.

## Decisions

- **SBOM artifacts commit to git.** `.gitignore` updated with
  `!releases/**/*.tar.gz` negation so the top-level `*.tar.gz` rule
  doesn't silently drop signed bundles. `releases/*-rc/` and
  `releases/*-dev/` gitignored so dry-run artifacts never leak in.
  Rationale in the approved plan: CLAUDE.md release gate says "cosign
  bundle on v2.0.0 git tag", NIST SSDF PO.1.1/PS.3.2 recommends SBOMs
  stored alongside released artifacts, SLSA L3 expects immutable
  provenance co-located with source snapshot, no package registry
  exists for this project.
- **dpkg-only system SBOM for N150 memory budget.** Full rootfs scan
  OOM'd syft. The dpkg DB captures all Debian packages with CPE strings,
  which is the actionable CVE signal; Docker image layer packages are
  out of scope for v2.0 (documented in release-process.md "SBOM Scope
  Limitations"). Tracked as v2.1 consideration once supportTAK gets
  more RAM.
- **CVE findings are audit evidence, not release gate.** Per NIST SSDF.
  The `validate-phase14.sh` SCA-03 check reports Critical/High counts
  but does not FAIL on them. Ships-with-disclosed-findings is industry
  best practice when no in-session remediation is possible.

## Files Modified

| File | Location | Change |
|---|---|---|
| `scripts/generate-sbom.sh` | Firewall repo | cosign v3 hint + version assertion; dpkg scope; distro detection + pass-through; local-vs-ssh detection |
| `scripts/validate-phase14.sh` | Firewall repo | NEW — SCA-01..05 + PCAP-01/04 with SKIP-when-releases-missing |
| `docs/release-process.md` | Firewall repo | Fixed cosign v3 install (was v2 `go install`); added "Where to Run" section describing tar-over-ssh pattern |
| `.gitignore` | Firewall repo | `!releases/**/*.tar.gz` negation; `releases/*-rc/` and `releases/*-dev/` exclusions |
| supportTAK `/usr/local/bin/syft` | supportTAK | Installed 1.42.4 |
| supportTAK `/usr/local/bin/grype` | supportTAK | Installed 0.111.0 |
| supportTAK `/usr/local/bin/cosign` | supportTAK | Installed 3.0.6 |
| `releases/v2.0.0/` | Firewall repo | NEW — 6 release artifacts (SBOMs, grype, tarball, cosign bundle) |

## Concerns

1. **68 High CVEs** in the system SBOM need triage in v2.1. Most are
   in nodejs 12.22 (EOL) and libqt5webkit5 (upstream won't-fix). An
   OS upgrade to Ubuntu 24.04 would resolve many, but that's a v2.1+
   decision requiring its own planning (downtime, Malcolm recompat test,
   GPU driver check if applicable, LUKS reboot risk).
2. **Cosign keyless requires interactive OAuth device flow** for
   local runs. Works for this one-time v2.0 release (GitHub OAuth
   device flow completed 2026-04-10 with identity
   `ablanks10@gmail.com`), but future release automation should move
   to GitHub Actions with `id-token: write` permission so releases get
   signed by a stable workflow OIDC identity — no human in the loop.
   Tracked as v2.1 task.
3. **supportTAK RAM pressure** persisted throughout this session
   (12.2/15.7 GB used, swap 99% full). Narrow syft scope worked, but
   any v2.1 work that adds containers or increases JVM heap sizes must
   re-baseline with `docker stats` + `free -m` before deploy.
