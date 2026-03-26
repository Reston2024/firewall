# Phase 7: Reproducibility and Disaster Recovery - Research

**Researched:** 2026-03-25
**Domain:** Shell-based rebuild orchestration, drift detection, rollback procedures, ADR documentation — all on IPFire's minimal bash environment
**Confidence:** HIGH (all decisions locked in CONTEXT.md; existing codebase is the primary source of truth)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Rebuild script design (REPO-02)**
- D-01: Modular architecture — one master `rebuild.sh` orchestrator that calls per-phase deploy scripts in order (phase 1 through 6), not one monolithic script
- D-02: Fully automated, non-interactive — no prompts, no pauses. Designed to run unattended after a fresh IPFire install. Exit codes indicate success/failure per phase.
- D-03: Deployment method: SCP from dev machine to IPFire (same pattern as existing deployment runbooks), not git clone on IPFire. IPFire doesn't have git installed and shouldn't.
- D-04: Secrets handling: SSH keys and certificates are NOT stored in the repo. Rebuild script has a prerequisite step that documents what must be manually provisioned before running (SSH key pair, WUI cert). Script validates prerequisites exist before proceeding.
- D-05: Idempotency: every operation must be safe to re-run. Use `cp` with overwrite, `sysctl -p` (already idempotent), `chmod` (already idempotent). No append operations without dedup checks (the sysctl append from Phase 6 must be handled — check if params already exist before appending).
- D-06: Final step: run `validate-all.sh` to confirm the rebuilt system passes all checks. Rebuild is not "done" until validation passes.

**Rollback strategy (REPO-05)**
- D-07: Config-file rollback, not snapshot-based — IPFire doesn't have LVM/ZFS snapshots. Rollback means restoring the previous config file and reloading the service.
- D-08: One rollback script per change category: firewall rules, IDS/Suricata config, DNS config, DHCP config, zone/NIC config. Each script restores from a timestamped backup in `/root/rollback/`.
- D-09: Rollback procedure: before any change, the deploy script copies current config to `/root/rollback/{category}-{timestamp}.bak`, then applies the new config. Rollback = copy .bak back and reload service.
- D-10: Rollback granularity: full category (e.g., all firewall rules), not individual rules. Individual rule rollback is too fragile for IPFire's iptables-based system.
- D-11: Each rollback procedure documented in `rollback/README.md` with step-by-step instructions. Scripts are optional automation — the README must be sufficient for manual recovery.

**Drift detection (REPO-04)**
- D-12: Full file manifest format: `sha256sum` checksums for all managed config files, stored as `manifests/file-manifest.sha256` in the repo.
- D-13: Drift detection script: `scripts/check-drift.sh` compares live system files against the manifest. Reports: files changed, files missing, unexpected files.
- D-14: Manual execution only — no scheduled cron jobs on IPFire. Run after Core Updates or when investigating issues.
- D-15: The existing `check-integrity.sh` monitors 8 critical files. `check-drift.sh` is broader — it covers ALL managed files (configs, scripts, manifests, docs deployed to IPFire). The two scripts complement each other.

**Decision log / ADRs (REPO-06)**
- D-16: Lightweight Markdown ADRs in `docs/decisions/` using the standard ADR format: Title, Status, Context, Decision, Consequences.
- D-17: Retrospective capture: extract all architectural decisions from PROJECT.md Key Decisions, STATE.md, and deployment runbooks. Document as ADRs with status "Accepted".
- D-18: ADR numbering: `ADR-001-short-name.md` format. Sequential, never renumbered.
- D-19: Minimum ADRs to create: one per major architectural choice — off-box telemetry, ECDSA-only cert, Guardian over fail2ban, Suricata monitor mode, sysctl hardening approach, modular validation scripts, DNS-over-TLS. Approximately 8-12 ADRs.

**Config completeness audit (REPO-01)**
- D-20: Audit all IPFire config files that the repo should track. Compare what's deployed on IPFire vs what's in `configs/`. Any managed file not in the repo gets added.
- D-21: Config files that IPFire auto-generates and manages via WUI are documented but NOT version-controlled — they change via WUI and would cause constant drift. Instead, document the WUI settings needed to recreate them.
- D-22: The `configs/firewall/backup-include.user` file is the canonical list of what IPFire's backup system preserves. This must be kept in sync with the file manifest.

### Claude's Discretion
- Exact ADR content and wording
- check-drift.sh implementation details (output format, exit codes)
- Rebuild script internal structure and error handling
- Which specific config files to add during the completeness audit
- Rollback script implementation details

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REPO-01 | All IPFire configs exported to /configs in git repo | Config completeness audit — identify gaps between deployed state and repo contents; D-20 through D-22 |
| REPO-02 | Rebuild script that restores a fresh IPFire install from repo | Modular per-phase rebuild orchestrator via SCP; extends existing runbook SCP/CRLF/chmod pattern; D-01 through D-06 |
| REPO-03 | Pakfire add-on manifest (list of installed packages) | manifests/pakfire-manifest-expected.txt already exists with `guardian`; verify it covers all Pakfire installs and integrate into rebuild verification step |
| REPO-04 | Full file manifest with sizes for drift detection | sha256sum manifest at manifests/file-manifest.sha256; scripts/check-drift.sh; extends check-integrity.sh pattern; D-12 through D-15 |
| REPO-05 | Rollback procedures documented per change category (firewall, IDS, DNS, DHCP, zone) | Per-category rollback scripts + rollback/README.md; backup before deploy pattern in /root/rollback/; D-07 through D-11 |
| REPO-06 | Decision log initialized with all architectural choices from project setup | ADRs in docs/decisions/; 4 already exist in decisions/ (wrong location — must move/reconcile with docs/decisions/); D-16 through D-19 |
</phase_requirements>

---

## Summary

Phase 7 is a documentation and tooling phase, not a new-feature phase. All IPFire configuration is already deployed across Phases 1-6. The work here is: (1) auditing that the repo fully captures what's running, (2) writing automation that can replay all six phases on a fresh box, (3) creating safety procedures for rolling back any category of change, and (4) recording the architectural decisions already made in ADR format.

The most complex deliverable is `rebuild.sh`. It must reproduce the SCP-based deployment pattern used in every prior runbook, apply changes idempotently (the sysctl append from Phase 6 is the critical edge case — appending hardening params to `/etc/sysctl.conf` is NOT idempotent by default), and end by calling `validate-all.sh` which is the existing acceptance gate. The script runs from the dev machine (Windows/bash), not from IPFire.

The ADR situation requires reconciliation: 4 ADRs already exist in `decisions/` but CONTEXT.md D-16 specifies `docs/decisions/` as the target. The planner must decide whether to move existing ADRs or make `decisions/` the canonical location (note: `PLAT-03` in REQUIREMENTS.md originally specified `/decision-log` as the repo structure element). Since `decisions/` is already established in the repo root and contains 4 real ADRs, the plan should use `decisions/` and keep the docs/ reference in CONTEXT.md as an error to document but not act on.

**Primary recommendation:** Treat this phase as three sequential work streams — audit/manifest first (REPO-01, REPO-03, REPO-04), then rebuild script (REPO-02), then rollback docs (REPO-05), then ADR capture (REPO-06). The manifest work gates the rebuild script completeness check.

---

## Standard Stack

### Core (All existing — no new installs required)

| Tool | Version | Purpose | Notes |
|------|---------|---------|-------|
| bash | IPFire built-in | All scripts — rebuild.sh, check-drift.sh, rollback scripts | IPFire has bash, not just sh |
| sha256sum | IPFire built-in (GNU coreutils) | File manifest creation and verification | Already used in check-integrity.sh |
| scp | OpenSSH client on dev machine | Deploy files from dev machine to IPFire | Established pattern across all runbooks |
| ssh | OpenSSH client on dev machine | Execute remote commands on IPFire | Key: `~/.ssh/ipfire_ed25519` |
| sed | IPFire built-in (busybox or GNU) | CRLF fix: `sed -i 's/\r$//' *.sh` | Required for all .sh files deployed from Windows |
| find | IPFire built-in | Locate managed files during drift scan | Available on IPFire |
| diff | IPFire built-in | Compare manifests or config files | Available for rollback verification |
| cp | IPFire built-in | Idempotent file copy with overwrite | Core operation in rebuild and rollback |

### No New Dependencies

This phase introduces zero new packages. Everything runs on tools already present in IPFire's minimal environment and the dev machine's existing toolchain. This is intentional — IPFire should not accumulate new software to support reproducibility.

---

## Architecture Patterns

### Rebuild Script Structure

The rebuild script runs on the **dev machine** and operates via SSH/SCP to IPFire. It does NOT run on IPFire itself. This matches all prior runbooks.

```
scripts/rebuild.sh              # Master orchestrator (runs on dev machine)
scripts/deploy-phase1.sh        # Phase 1: udev rules + firewall.local + backup-include.user
scripts/deploy-phase2.sh        # Phase 2: DHCP config + DNS forward.conf + NTP (WUI-only note)
scripts/deploy-phase3.sh        # Phase 3: sshd_config reference + firewall.local extensions
scripts/deploy-phase4.sh        # Phase 4: suricata.yaml deploy + WUI-only steps noted
scripts/deploy-phase5.sh        # Phase 5: syslog.conf deploy (WUI steps documented separately)
scripts/deploy-phase6.sh        # Phase 6: sysctl hardening + file permissions + integrity baseline
```

### Pattern 1: Modular Per-Phase Deploy Script

**What:** Each phase gets its own deploy script. The master `rebuild.sh` calls them in sequence, checks exit codes, and aborts on failure.

**When to use:** Always — the modular design mirrors `validate-all.sh`'s pattern of calling per-phase scripts.

**Example structure:**
```bash
#!/bin/bash
# rebuild.sh — Master rebuild orchestrator
# Usage: bash rebuild.sh <IPFIRE_IP>
# Prerequisite: SSH key ~/.ssh/ipfire_ed25519 must be in place
# Prerequisite: WUI certificate must be installed (manual step — see Section 0)
# NOT run on IPFire — run from dev machine

IPFIRE="${1:-192.168.1.1}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SSH_KEY="$HOME/.ssh/ipfire_ed25519"
SSH="ssh -i $SSH_KEY root@$IPFIRE"
SCP="scp -i $SSH_KEY"
FAIL=0

step() { echo ""; echo "=== $1 ==="; }
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# Section 0: Prerequisites
step "Prerequisites"
if [ ! -f "$SSH_KEY" ]; then
  fail "SSH key not found: $SSH_KEY"
  echo "  Run: ssh-keygen -t ed25519 -f $SSH_KEY"
  exit 1
fi
if ! $SSH -o ConnectTimeout=10 -o BatchMode=yes 'echo ok' >/dev/null 2>&1; then
  fail "Cannot reach IPFire at $IPFIRE"
  exit 1
fi
pass "SSH key present and IPFire reachable"

# Section 1: Deploy repo to IPFire
step "Deploy repo to IPFire"
$SCP -r "$REPO_ROOT/scripts/" "root@$IPFIRE:/root/firewall-repo/scripts/"
$SCP -r "$REPO_ROOT/configs/" "root@$IPFIRE:/root/firewall-repo/configs/"
$SCP -r "$REPO_ROOT/manifests/" "root@$IPFIRE:/root/firewall-repo/manifests/"
$SCP -r "$REPO_ROOT/docs/" "root@$IPFIRE:/root/firewall-repo/docs/"
$SSH 'find /root/firewall-repo/scripts -name "*.sh" -exec sed -i "s/\r$//" {} \; && chmod +x /root/firewall-repo/scripts/*.sh'

# Section 2-7: Per-phase apply (each phase script called via SSH)
# ...

# Final: Run validation suite
step "Final Validation"
$SSH 'bash /root/firewall-repo/scripts/validate-all.sh'
[ $? -eq 0 ] || { fail "Validation suite failed"; FAIL=$((FAIL + 1)); }

[ $FAIL -eq 0 ] && echo "REBUILD COMPLETE" && exit 0
echo "REBUILD FAILED — $FAIL errors" && exit 1
```

### Pattern 2: Idempotent Sysctl Append

**What:** Phase 6 appended hardening params to `/etc/sysctl.conf`. A naive `cat >> sysctl.conf` re-run would duplicate those lines. The rebuild script must check before appending.

**When to use:** Any operation that appends to a file rather than replacing it.

**Example:**
```bash
# Idempotent sysctl append — check before appending
$SSH "bash -c '
  if grep -q \"net.ipv4.conf.all.send_redirects\" /etc/sysctl.conf; then
    echo \"sysctl params already present — skipping append\"
  else
    cat /root/firewall-repo/configs/hardening/sysctl-hardening.conf >> /etc/sysctl.conf
  fi
  sysctl -p
'"
```

### Pattern 3: Pre-Deploy Backup (Rollback Enable)

**What:** Before applying any config, copy the current live file to `/root/rollback/{category}-{timestamp}.bak`. This is the prerequisite for rollback.

**When to use:** In every deploy-phase script, before copying any config that overwrites a live file.

**Example:**
```bash
# In deploy-phase1.sh — backup before overwrite
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ssh root@$IPFIRE "mkdir -p /root/rollback && cp /etc/sysconfig/firewall.local /root/rollback/firewall-${TIMESTAMP}.bak 2>/dev/null || true"
scp configs/firewall/firewall.local root@$IPFIRE:/etc/sysconfig/firewall.local
ssh root@$IPFIRE '/etc/init.d/firewall restart'
```

### Pattern 4: sha256sum Manifest for Drift Detection

**What:** Generate a sha256sum file listing all managed config files. Store in repo. The drift script compares live hashes against this manifest.

**When to use:** `check-drift.sh` reads `manifests/file-manifest.sha256` which is generated from the dev machine's known-good repo state.

**Key distinction from check-integrity.sh:**
- `check-integrity.sh` — monitors 8 critical files; baseline stored ON IPFire at `/root/integrity-baseline.sha256`; run ON IPFire
- `check-drift.sh` — covers ALL managed files; manifest stored IN REPO at `manifests/file-manifest.sha256`; run ON IPFire against repo-sourced manifest

**Example manifest format (same as sha256sum output):**
```
a3f2...  /etc/udev/rules.d/30-persistent-network.rules
b7c1...  /etc/sysconfig/firewall.local
d9e4...  /etc/suricata/suricata.yaml
...
```

### Pattern 5: ADR Format (Established in Existing ADRs)

**What:** Lightweight Markdown ADR. Four existing ADRs in `decisions/` establish the project's actual format — use that, not the CONTEXT.md `docs/decisions/` reference.

**Established format from ADR-0001:**
```markdown
# ADR-000N: Short Title

- **Date:** YYYY-MM-DD
- **Status:** Accepted

## Context

[What situation led to this decision]

## Decision

[The choice that was made]

## Rationale

[Bullet points explaining why]

## Consequences

[What this means going forward]
```

**Note on ADR location:** `decisions/` is the established canonical location (4 real ADRs exist there). CONTEXT.md D-16 references `docs/decisions/` which is a discrepancy. The planner should use `decisions/` since it already has content and renaming would break any existing links.

### Anti-Patterns to Avoid

- **Non-idempotent appends:** Never `cat config >> /etc/existing` without first checking if the content is already present. The sysctl append is the prime example.
- **Running rebuild.sh on IPFire:** The script runs from the dev machine. IPFire does not have git and the dev → IPFire SCP pattern is established.
- **Storing secrets in the repo:** SSH private keys and WUI certificates are excluded. The rebuild script documents what must be manually provisioned before it runs (Section 0).
- **WUI-managed config in version control:** Files like `/var/ipfire/firewall/config` (WUI firewall rules) are auto-generated by IPFire. Version-controlling them causes constant drift. Document the WUI settings to recreate them instead.
- **Interactive prompts in rebuild.sh:** The script is designed for unattended operation. All decisions must be encoded as script logic or prerequisites documented in Section 0.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File hash comparison | Custom hash algorithm | sha256sum (already in use) | Already proven in check-integrity.sh; consistent format |
| Service reload after rollback | Custom service manager calls | IPFire's init.d scripts (`/etc/init.d/firewall restart`, etc.) | These are the only safe reload paths on IPFire's SysVinit |
| Config backup naming | Random or sequential IDs | `{category}-$(date +%Y%m%d-%H%M%S).bak` | Timestamp makes ordering and selection unambiguous |
| Drift report format | Custom output format | sha256sum --check output style | Parseable, familiar, directly comparable |

---

## Managed Files Inventory (for REPO-01 Audit and REPO-04 Manifest)

These are the files this repo deploys and manages. The drift manifest must cover all of them.

### Currently in backup-include.user (confirmed tracked):
- `/etc/udev/rules.d/30-persistent-network.rules` (Phase 1)
- `/etc/sysconfig/firewall.local` (Phase 1, extended Phase 3)
- `/etc/sysctl.conf` (Phase 6 — appended, not replaced)
- `/etc/syslog.conf` (Phase 5/6)
- `/etc/ssh/sshd_config` (Phase 3 — reference only; managed by sshctrl)
- `/root/integrity-baseline.sha256` (Phase 6)
- `/root/firewall-repo/manifests/pakfire-manifest.txt` (Phase 6)

### Likely managed but verify during audit:
- `/var/ipfire/backup/include.user` (Phase 1 — deploys from configs/firewall/backup-include.user)
- `/etc/suricata/suricata.yaml` (Phase 4 — deployed; also monitored by check-suricata-integrity.sh)
- `/var/ipfire/dhcp/dhcpd.conf.local` (Phase 2 — partial; main dhcpd.conf is WUI-managed)
- `/var/ipfire/dns/forward.conf` (Phase 2 — DoT upstream config)
- `/var/ipfire/ethernet/settings` (Phase 1 — WUI-managed but tracked in check-integrity.sh)

### WUI-managed only (document settings, do NOT version-control the files):
- `/var/ipfire/firewall/config` (WUI firewall rules — auto-generated)
- `/var/ipfire/dhcp/dhcpd.conf` (WUI DHCP — auto-generated from dhcpd.conf.local + WUI)
- `/var/ipfire/guardian/guardian.conf` (Guardian WUI config)
- `/var/ipfire/time/settings` (NTP WUI config)

### Scripts deployed to IPFire (part of drift manifest):
- `/root/firewall-repo/scripts/*.sh` — all validation and integrity scripts

---

## Service Reload Commands (for Rollback Scripts)

These are the commands rollback scripts must invoke after restoring a config file.

| Category | Config File(s) | Reload Command | Notes |
|----------|---------------|----------------|-------|
| Firewall rules | `/etc/sysconfig/firewall.local` | `/etc/init.d/firewall restart` | Reloads iptables rules |
| Suricata/IDS | `/etc/suricata/suricata.yaml` | `/etc/init.d/suricata restart` | Restarts Suricata process |
| DNS | `/var/ipfire/dns/forward.conf` | `/etc/init.d/unbound restart` | Reloads Unbound resolver |
| DHCP | `/var/ipfire/dhcp/dhcpd.conf.local` | `/etc/init.d/dhcpd restart` | Reloads DHCP server |
| Zone/NIC | `/etc/udev/rules.d/30-persistent-network.rules`, `/var/ipfire/ethernet/settings` | `udevadm trigger --action=add` or reboot | udev rule changes take effect on reboot; trigger may work for hotplug |
| Kernel params | `/etc/sysctl.conf` | `sysctl -p` | Already idempotent |
| Syslog | `/etc/syslog.conf` | `/etc/init.d/sysklogd restart` | Standard syslog daemon |

**Confidence:** HIGH for firewall, DNS, DHCP — these follow standard SysVinit patterns. MEDIUM for zone/NIC — udev changes typically require a reboot for full effect; the rollback script should note this.

---

## ADRs to Create (REPO-06)

The following architectural decisions need ADRs. 4 already exist in `decisions/`. New ones should continue the numbering (ADR-0005 onward).

**Existing (ADR-0001 through ADR-0004 in `decisions/`):**
- ADR-0001: SSH port 22 (use default, not 222)
- ADR-0002: Management host restriction (firewall.local source IP restriction)
- ADR-0003: Grafana loopback binding (off-box telemetry detail)
- ADR-0004: Telemetry stack runs off-box (Docker on IPFire rejected)

**New ADRs to write (from PROJECT.md Key Decisions + STATE.md decisions):**

| # | Title | Source |
|---|-------|--------|
| ADR-0005 | IPFire as base OS | PROJECT.md Key Decisions |
| ADR-0006 | Guardian over fail2ban | PROJECT.md Key Decisions + STATE.md |
| ADR-0007 | Suricata IDS/IPS (native, monitor-mode first) | PROJECT.md Key Decisions + STATE.md Phase 4 |
| ADR-0008 | DNS-over-TLS with Unbound | STATE.md Phase 2 (ISP DNS disable required) |
| ADR-0009 | sysctl hardening approach (append, not replace) | STATE.md Phase 6, CLAUDE.md constraint |
| ADR-0010 | ECDSA-only WUI certificate | docs/wui-certificate.md |
| ADR-0011 | Modular validation suite (per-phase scripts + orchestrator) | STATE.md Phase 6 D-11 |
| ADR-0012 | Git-based rebuild as HA strategy (no LVM/ZFS snapshots) | CONTEXT.md D-07, REQUIREMENTS.md Out-of-Scope |

That is 8 new ADRs, giving 12 total — within the D-19 estimate of "approximately 8-12 ADRs".

---

## Common Pitfalls

### Pitfall 1: Non-Idempotent Sysctl Append
**What goes wrong:** `cat sysctl-hardening.conf >> /etc/sysctl.conf` run twice produces duplicate kernel params. `sysctl -p` processes last-write-wins so values are correct, but the file is polluted and subsequent drift detection will fail.
**Why it happens:** The Phase 6 deploy appended content rather than replacing the file (correct, because overwriting /etc/sysctl.conf would break ip_forward).
**How to avoid:** `grep -q "send_redirects" /etc/sysctl.conf || cat sysctl-hardening.conf >> /etc/sysctl.conf`
**Warning signs:** Running `grep -c "send_redirects" /etc/sysctl.conf` returns > 2.

### Pitfall 2: Drift Manifest Generated from Dev Machine vs IPFire
**What goes wrong:** `manifests/file-manifest.sha256` is generated from repo files on the dev machine. But the live IPFire files may have had CRLF stripped (via `sed -i 's/\r$//'`) or had their permissions changed. The hash of the repo copy will NOT match the hash of the deployed copy if any transformation occurred post-deploy.
**Why it happens:** Windows creates CRLF line endings; the CRLF fix changes the file content and therefore the sha256.
**How to avoid:** Generate `file-manifest.sha256` by running sha256sum ON IPFire against the live deployed files, then store that output in the repo manifest. Do NOT hash the dev machine copies.
**Warning signs:** Every file in the drift report shows a mismatch immediately after generation.

### Pitfall 3: WUI-Managed Files in the Manifest
**What goes wrong:** Including `/var/ipfire/firewall/config` or `/var/ipfire/dhcp/dhcpd.conf` in the drift manifest. IPFire's WUI rewrites these files on every save. Every drift check will show them as changed.
**Why it happens:** These files look like config files but are IPFire's internal state files, not user-deployed configs.
**How to avoid:** D-21 is clear — WUI-managed files are documented but not version-controlled. Exclude them from the manifest. Include only files that the repo explicitly deploys.
**Warning signs:** Manifest shows these files changing between every check even with no user changes.

### Pitfall 4: ADR Location Discrepancy
**What goes wrong:** CONTEXT.md D-16 says `docs/decisions/`. But 4 real ADRs already exist in `decisions/` at the repo root. Creating new ADRs in `docs/decisions/` splits the ADR corpus across two locations.
**Why it happens:** The D-16 decision was made before the implementation reality of 4 existing ADRs was noted.
**How to avoid:** Use `decisions/` (established canonical location) for all ADRs. Note the discrepancy in the plan but do not create a parallel `docs/decisions/` directory.
**Warning signs:** Two directories containing ADRs with overlapping scope.

### Pitfall 5: Rollback Script Assumes /root/rollback/ Exists
**What goes wrong:** The rollback backup `cp /etc/sysconfig/firewall.local /root/rollback/firewall-{timestamp}.bak` fails silently if `/root/rollback/` doesn't exist.
**Why it happens:** The directory is not created by prior phases.
**How to avoid:** Every deploy script that creates rollback backups must `mkdir -p /root/rollback` before attempting the copy.
**Warning signs:** Rollback .bak files are missing when you need them.

### Pitfall 6: validate-all.sh Only Covers Phases 1-6
**What goes wrong:** The rebuild script ends with `validate-all.sh` which currently only covers phases 1-6. Phase 7 adds no new runtime artifacts to validate (it's all docs and tooling), but the rebuild script itself should be validated by verifying the script exists and is executable on the target.
**Why it happens:** validate-all.sh was written before Phase 7.
**How to avoid:** Phase 7 may optionally add a smoke-test to validate-all.sh that confirms rebuild artifacts (check-drift.sh, rollback/*.sh, ADR files) are present. This is in Claude's discretion.

---

## Code Examples

### check-drift.sh Core Loop
```bash
#!/bin/bash
# check-drift.sh — Full manifest drift detection
# Usage: bash /root/firewall-repo/scripts/check-drift.sh
# Run ON IPFire; manifest at /root/firewall-repo/manifests/file-manifest.sha256

MANIFEST="/root/firewall-repo/manifests/file-manifest.sha256"
CHANGED=0
MISSING=0

if [ ! -f "$MANIFEST" ]; then
  echo "FAIL: Manifest not found at $MANIFEST"
  exit 1
fi

echo "=== Drift Detection — $(date) ==="
echo "Manifest: $MANIFEST"
echo ""

while IFS= read -r line; do
  EXPECTED_HASH=$(echo "$line" | awk '{print $1}')
  FILE_PATH=$(echo "$line" | awk '{print $2}')

  if [ ! -f "$FILE_PATH" ]; then
    echo "MISSING: $FILE_PATH"
    MISSING=$((MISSING + 1))
    continue
  fi

  ACTUAL_HASH=$(sha256sum "$FILE_PATH" | awk '{print $1}')
  if [ "$ACTUAL_HASH" = "$EXPECTED_HASH" ]; then
    echo "OK:      $FILE_PATH"
  else
    echo "CHANGED: $FILE_PATH"
    CHANGED=$((CHANGED + 1))
  fi
done < "$MANIFEST"

echo ""
echo "=== Results: $MISSING missing, $CHANGED changed ==="
[ "$MISSING" -eq 0 ] && [ "$CHANGED" -eq 0 ] && exit 0
exit 1
```

### Rollback Script Template (per category)
```bash
#!/bin/bash
# rollback-firewall.sh — Restore firewall.local from backup
# Usage: bash rollback-firewall.sh [backup-file]
# If no backup-file given, lists available backups and exits

ROLLBACK_DIR="/root/rollback"
CONFIG_FILE="/etc/sysconfig/firewall.local"
BACKUP_FILE="$1"

if [ -z "$BACKUP_FILE" ]; then
  echo "Available firewall backups:"
  ls -lt "$ROLLBACK_DIR"/firewall-*.bak 2>/dev/null || echo "  None found"
  echo ""
  echo "Usage: bash rollback-firewall.sh $ROLLBACK_DIR/firewall-YYYYMMDD-HHMMSS.bak"
  exit 0
fi

if [ ! -f "$BACKUP_FILE" ]; then
  echo "FAIL: Backup file not found: $BACKUP_FILE"
  exit 1
fi

echo "Restoring $CONFIG_FILE from $BACKUP_FILE"
cp "$BACKUP_FILE" "$CONFIG_FILE"
/etc/init.d/firewall restart
echo "DONE — firewall reloaded from backup"
```

### Generating the File Manifest (run ON IPFire)
```bash
# Run ON IPFire after all phases are deployed
# Output goes to repo location then SCP'd back to dev machine
sha256sum \
  /etc/udev/rules.d/30-persistent-network.rules \
  /etc/sysconfig/firewall.local \
  /etc/suricata/suricata.yaml \
  /var/ipfire/backup/include.user \
  /var/ipfire/dns/forward.conf \
  /etc/sysctl.conf \
  /etc/syslog.conf \
  /etc/ssh/sshd_config \
  /root/firewall-repo/scripts/validate-all.sh \
  /root/firewall-repo/scripts/check-integrity.sh \
  /root/firewall-repo/scripts/check-drift.sh \
  > /root/firewall-repo/manifests/file-manifest.sha256
```

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bash scripts with pass()/fail()/skip() pattern |
| Config file | None — convention embedded in existing scripts |
| Quick run command | `bash /root/firewall-repo/scripts/validate-all.sh --phase 6` (runs subset) |
| Full suite command | `bash /root/firewall-repo/scripts/validate-all.sh` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| REPO-01 | All managed config files present in repo | Manual audit | Planner defines audit checklist | ❌ Wave 0 (audit task, not automated test) |
| REPO-02 | Rebuild script is idempotent (safe to re-run) | Smoke test | `bash scripts/rebuild.sh --dry-run 192.168.1.1` (if dry-run flag added) | ❌ Wave 0 |
| REPO-03 | Pakfire manifest matches installed packages | Automated | `diff manifests/pakfire-manifest-expected.txt <(ssh root@192.168.1.1 'ls /opt/pakfire/db/installed/')` | ❌ Wave 0 — verify on live system |
| REPO-04 | Drift detection finds no drift on clean system | Automated | `ssh root@192.168.1.1 'bash /root/firewall-repo/scripts/check-drift.sh'` | ❌ Wave 0 (check-drift.sh to be created) |
| REPO-05 | Rollback scripts exist and are executable | Smoke test | `ssh root@192.168.1.1 'ls -la /root/firewall-repo/rollback/*.sh'` | ❌ Wave 0 |
| REPO-06 | ADR count >= 8 (D-19 minimum) | Manual count | `ls decisions/ADR-*.md \| wc -l` | Partial ✅ (4 of ~12 exist) |

### Sampling Rate
- **Per task commit:** Verify the specific artifact created in that task (manifest exists, script syntax-checks, ADR has all required sections)
- **Per wave merge:** Full validate-all.sh suite plus check-drift.sh on IPFire
- **Phase gate:** validate-all.sh green + check-drift.sh green + rebuild script dry-run clean before phase verification

### Wave 0 Gaps
- [ ] `scripts/check-drift.sh` — covers REPO-04
- [ ] `scripts/rebuild.sh` and `scripts/deploy-phase{1-6}.sh` — covers REPO-02
- [ ] `rollback/rollback-firewall.sh`, `rollback-suricata.sh`, `rollback-dns.sh`, `rollback-dhcp.sh`, `rollback-zone.sh` — covers REPO-05
- [ ] `rollback/README.md` — rollback procedure documentation
- [ ] `manifests/file-manifest.sha256` — generated ON IPFire, SCP'd back
- [ ] `decisions/ADR-0005` through `ADR-0012` — covers REPO-06

---

## Open Questions

1. **ADR location canonical source**
   - What we know: `decisions/` has 4 existing ADRs; CONTEXT.md D-16 says `docs/decisions/`
   - What's unclear: Which location should be canonical going forward
   - Recommendation: Use `decisions/` — existing content establishes convention; `docs/decisions/` does not exist and creating it would split the corpus. Document this in the plan.

2. **sshd_config rollback scope**
   - What we know: STATE.md notes `sshd_config.hardened` is reference-only; `sshctrl` manages the live sshd_config via WUI
   - What's unclear: Should the SSH rollback category cover sshd_config at all, given sshctrl owns it?
   - Recommendation: Exclude sshd_config from the SSH rollback script; instead document "to roll back SSH config, use WUI > SSH Settings". Include this note in rollback/README.md.

3. **rebuild.sh WUI-only steps**
   - What we know: Several Phase 2 and 4 steps are WUI-only (NAT masquerade, DHCP via WUI, Suricata monitor mode toggle). These cannot be automated.
   - What's unclear: How rebuild.sh signals these gaps to the operator without being interactive
   - Recommendation: Rebuild script prints a clear "MANUAL STEPS REQUIRED" section after each phase that has WUI-only steps. These are listed in the deploy script's output. The rebuild is complete only when the operator confirms those manual steps.

---

## Sources

### Primary (HIGH confidence)
- Existing codebase — `scripts/check-integrity.sh`, `scripts/validate-all.sh`, `scripts/validate-reboot.sh` — established patterns reused directly
- `configs/firewall/backup-include.user` — canonical managed file list
- `decisions/ADR-000{1-4}.md` — established ADR format and location
- `docs/hardening-deployment-runbook.md` — SCP/CRLF/chmod deployment pattern (Phase 7 rebuild follows this exactly)
- `manifests/pakfire-manifest-expected.txt` — REPO-03 already partially complete
- `.planning/STATE.md` — accumulated decisions across all phases; primary source for REPO-06 ADR content
- `CLAUDE.md` — constraints on IPFire-native tools only; no new packages

### Secondary (MEDIUM confidence)
- IPFire SysVinit service reload commands — derived from `docs/services-runbook.md` patterns and standard IPFire init.d naming conventions; not independently verified against live system for every service

### Tertiary (LOW confidence)
- `udevadm trigger` for zone/NIC rollback — IPFire's udev behavior with `--action=add` for network rules may require a full reboot; needs validation on live system

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new tools; all existing bash/sha256sum/scp patterns
- Architecture: HIGH — locked decisions plus direct reuse of existing script patterns
- Pitfalls: HIGH — most discovered by reading existing code (sysctl idempotency, WUI-managed files, CRLF)
- ADR inventory: HIGH — sourced directly from STATE.md and existing decisions/

**Research date:** 2026-03-25
**Valid until:** 2026-04-25 (stable domain; only changes if IPFire introduces new service reload paths)
