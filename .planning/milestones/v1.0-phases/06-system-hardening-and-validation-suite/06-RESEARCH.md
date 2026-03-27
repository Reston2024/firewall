# Phase 6: System Hardening and Validation Suite - Research

**Researched:** 2026-03-25
**Domain:** IPFire system hardening (SysVinit, sysctl, file integrity, certificate) + shell-based validation suite orchestration
**Confidence:** HIGH (all key findings verified against official IPFire docs and confirmed against existing codebase)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Service Audit (HARD-01)**
- D-01: Conservative audit approach: document all services, disable only clearly unnecessary ones (avahi, cups, etc. if present). Leave WUI services (httpd ports 81/444/1013), Guardian, NTP, DHCP, unbound, sshd, Suricata running.
- D-02: Port 81 (HTTP redirect to HTTPS WUI) stays enabled — standard IPFire behavior, disabling may break WUI bookmarks.
- D-03: Create a Pakfire manifest listing all expected installed packages. Flag unexpected installs. This feeds into Phase 7 reproducibility (REPO-03).
- D-04: Currently listening on IPFire (known good baseline): unbound:53, sshd:22, httpd:81/444/1013. Anything else is a finding.

**Hardening Baseline (HARD-02, HARD-04)**
- D-05: CIS-inspired for IPFire: apply CIS Linux benchmark principles where applicable, skip controls that conflict with IPFire's architecture (SysVinit, custom buildroot). Document all deviations with rationale.
- D-06: Kernel hardening via sysctl.conf: fix send_redirects=0 (currently 1) and any other missing CIS kernel params. Persist in /etc/sysctl.conf or drop-in file. Verify on reboot (VAL-08).
- D-07: Current kernel state (already hardened): accept_source_route=0, accept_redirects=0, rp_filter=1. Only send_redirects=1 needs fixing.

**Audit Logging (HARD-03)**
- D-08: File integrity monitoring approach: SHA256 hash key config files (firewall.local, syslog.conf, suricata.yaml, sshd_config, ethernet/settings, udev rules, backup include list). Store baseline hashes. Compare on demand to detect unauthorized changes.
- D-09: No auditd (likely not in Pakfire). No syscall-level auditing — too heavy for SOHO firewall. File hash comparison is sufficient.

**WUI Certificate (HARD-05)**
- D-10: Document the self-signed HTTPS certificate on port 444. Verify it exists and has reasonable validity. Add certificate fingerprint to the repo for reference.

**Validation Suite Architecture (VAL-01 through VAL-11)**
- D-11: Orchestrator pattern: a new validate-all.sh on IPFire calls each existing per-phase script (validate-phase1.sh through validate-phase5.sh) in order, collects results, produces unified pass/fail report.
- D-12: validate-all.sh runs on IPFire. For Phase 5 telemetry checks, it SSHes to supportTAK-server (192.168.1.101) to run validate-phase5.sh remotely.
- D-13: Per-phase scripts already exist for Phases 1-5. Phase 6 creates validate-phase6.sh (hardening checks) and validate-all.sh (orchestrator).
- D-14: No JSON output — console pass/fail is sufficient for v1. Structured output is v2.

**Reboot Verification (VAL-08, VAL-09)**
- D-15: Snapshot-and-compare approach: script captures pre-reboot state, user reboots manually, script runs again post-reboot and compares.
- D-16: Pre-reboot snapshot includes: running services (ss -tlnp output), config file SHA256 hashes, full iptables ruleset dump, sysctl hardened kernel parameter values.
- D-17: Manual reboot only — no automated reboot trigger. Script captures pre-state, prints instructions to reboot, user runs comparison mode after reboot.

### Claude's Discretion
- Exact CIS controls to apply (choose appropriate subset for IPFire)
- File integrity hash storage format and location
- validate-all.sh output formatting (colors, sections, summary table)
- Which config files to include in integrity baseline (beyond the obvious ones)
- How to handle validate-phase5.sh SSH key from IPFire to supportTAK-server (key already deployed)

### Deferred Ideas (OUT OF SCOPE)
- Full auditd syscall-level auditing — too heavy for SOHO, revisit if compliance requirements change
- JSON/HTML structured validation output — v2 enhancement
- Automated reboot testing — risk of reboot loops, manual is safer for v1
- Scheduled integrity checks (cron) — consider for Phase 7 or v2
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| HARD-01 | Unused services identified and disabled | Service enumeration via `ss -tlnp` and `ls /opt/pakfire/db/installed/`; known-good baseline established |
| HARD-02 | File permissions locked down per IPFire hardening guide | IPFire hardening guide reviewed; specific permission targets documented |
| HARD-03 | Audit logging enabled for configuration changes | SHA256 baseline pattern from check-suricata-integrity.sh; file list and storage location documented |
| HARD-04 | Kernel parameters hardened (sysctl) | CIS-Linux sysctl params verified; IPFire router exceptions documented; only send_redirects needs fixing |
| HARD-05 | IPFire WUI HTTPS certificate verified and documented | Certificate location (/etc/httpd), openssl extraction command, fingerprint storage pattern |
| VAL-01 | Interface status validation (all 6 NICs up, correct zone assignment) | Covered by existing validate-phase1.sh; reuse pattern confirmed |
| VAL-02 | Routing validation | validate-phase1.sh manual skip pattern; integrate into validate-all.sh |
| VAL-03 | Firewall rule validation | validate-phase1.sh CUSTOMINPUT pattern; reuse |
| VAL-04 | NAT validation | validate-phase1.sh skip pattern; manual-only |
| VAL-05 | DHCP validation | Covered by validate-phase2.sh |
| VAL-06 | DNS validation | Covered by validate-phase2.sh |
| VAL-07 | IDS validation | Covered by validate-phase4.sh |
| VAL-08 | Reboot persistence | New snapshot-and-compare script; pre/post diff on sysctl, iptables, services |
| VAL-09 | Service health checks | validate-all.sh collects per-phase service status checks |
| VAL-10 | Telemetry validation | Covered by validate-phase5.sh (run via SSH to supportTAK-server) |
| VAL-11 | Full acceptance checklist script | validate-all.sh orchestrator — new artifact this phase |
</phase_requirements>

---

## Summary

IPFire 2.29 (Core Update 200) is a Linux From Scratch (LFS)-derived distribution running SysVinit (not systemd). This means standard `systemctl` commands do not exist; service management is via `/etc/rc.d/init.d/<service> {start|stop|status}` and boot-time symlinks in `/etc/rc.d/rc3.d/`. Hardening must account for this architecture throughout.

The hardening work for this phase is narrowly scoped by CONTEXT.md decisions: the only sysctl gap confirmed on this system is `net.ipv4.conf.all.send_redirects=1` (should be 0). All other CIS-relevant kernel parameters (accept_source_route=0, accept_redirects=0, rp_filter=1) are already correct. File permission hardening targets a small set of sensitive config paths. The file integrity monitoring pattern is already proven in `check-suricata-integrity.sh` and scales directly to a multi-file baseline.

The validation suite is the larger deliverable. Five per-phase scripts already exist with consistent `pass()`/`fail()`/`skip()` function patterns and exit code conventions. The new `validate-all.sh` orchestrator calls them in sequence, plus a new `validate-phase6.sh` for hardening checks, and produces a unified summary table. The Phase 5 telemetry checks run via SSH from IPFire to supportTAK-server (key already deployed at `/root/.ssh/`).

**Primary recommendation:** Implement in four sequential work units — (1) sysctl hardening + service audit + file permissions, (2) file integrity baseline script, (3) WUI certificate documentation, (4) validate-phase6.sh + validate-all.sh orchestrator.

---

## Standard Stack

### Core (All IPFire-native, no install required)

| Tool | Location | Purpose | Notes |
|------|----------|---------|-------|
| `sysctl` | `/sbin/sysctl` | Read/write kernel parameters | Persist via `/etc/sysctl.conf` |
| `sha256sum` | `/usr/bin/sha256sum` | File integrity hashing | Used in check-suricata-integrity.sh already |
| `openssl` | `/usr/bin/openssl` | Certificate inspection | Available in IPFire base |
| `ss` | `/sbin/ss` (or `netstat`) | Socket/listening port enumeration | Used in existing validate scripts |
| `iptables-save` | `/sbin/iptables-save` | Full ruleset capture for snapshot | Built-in |
| `pakfire` | `/usr/sbin/pakfire` | Package manifest generation | `ls /opt/pakfire/db/installed/` for installed list |
| `diff` / `md5sum` | standard | Snapshot comparison | Built into IPFire |

### Pakfire Add-ons (Already Installed)

| Package | Purpose | Status |
|---------|---------|--------|
| `guardian` | SSH/WUI brute-force protection | Installed (Phase 3) |
| `suricata` | IDS/IPS | Bundled in core since CU131 |

### No New Installs Required

Phase 6 uses only tools already present on IPFire. `lynis` is available via Pakfire for manual audits but is NOT required for this phase — the CIS-inspired manual checklist is sufficient and avoids pulling in a large audit tool for a narrow task.

---

## Architecture Patterns

### Recommended File Locations on IPFire

```
/etc/sysctl.conf                    # kernel hardening parameters (persistent)
/etc/sysconfig/firewall.local       # firewall anti-lockout rules (existing)
/etc/ssh/sshd_config                # SSH hardening (Phase 3, verified)
/etc/suricata/suricata.yaml         # IDS config (Phase 4, verified)
/etc/httpd/server.crt               # WUI HTTPS certificate (RSA)
/etc/httpd/server-ecdsa.crt         # WUI HTTPS certificate (ECDSA)
/etc/httpd/server.key               # WUI private key
/var/ipfire/backup/include.user     # IPFire backup include list
/var/ipfire/ethernet/settings       # Interface zone assignments
/etc/udev/rules.d/30-persistent-network.rules  # NIC persistence
/root/firewall-repo/                # Project git repo on IPFire
/root/firewall-repo/manifests/      # Pakfire manifest stored here
/root/integrity-baseline.sha256     # File integrity hashes (new)
/root/reboot-snapshot.txt           # Pre-reboot state snapshot (new)
```

### Pattern 1: Sysctl Hardening (Drop-in or Direct)

IPFire uses `/etc/sysctl.conf` directly (no `/etc/sysctl.d/` drop-in support confirmed on IPFire 2.x buildroot). Append to existing file. Do NOT overwrite — IPFire may have existing values.

```bash
# Source: CIS Linux Level 1, adapted for IPFire router role
# Router exception: ip_forward MUST remain 1 — do NOT set to 0
# These settings are safe for a firewall/router

# Fix: send_redirects currently 1 on this system — set to 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Already correct on this system (verify before adding):
# net.ipv4.conf.all.accept_source_route = 0    (already 0)
# net.ipv4.conf.default.accept_source_route = 0 (already 0)
# net.ipv4.conf.all.accept_redirects = 0        (already 0)
# net.ipv4.conf.all.rp_filter = 1               (already 1)

# Additional CIS params safe for router role:
net.ipv4.tcp_syncookies = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
```

Apply immediately without reboot:
```bash
sysctl -p /etc/sysctl.conf
```

Verify:
```bash
sysctl net.ipv4.conf.all.send_redirects  # must be 0
sysctl net.ipv4.conf.default.send_redirects  # must be 0
```

### Pattern 2: File Integrity Baseline (Extending check-suricata-integrity.sh)

The existing `check-suricata-integrity.sh` pattern is the exact model. Extend it to a multi-file baseline.

```bash
# Source: scripts/check-suricata-integrity.sh (existing project pattern)
# Extended for Phase 6 multi-file integrity baseline

BASELINE_FILE="/root/integrity-baseline.sha256"

# Files to hash — aligned with backup-include.user coverage
MONITORED_FILES=(
  "/etc/udev/rules.d/30-persistent-network.rules"
  "/etc/sysconfig/firewall.local"
  "/etc/ssh/sshd_config"
  "/etc/suricata/suricata.yaml"
  "/var/ipfire/ethernet/settings"
  "/var/ipfire/backup/include.user"
  "/etc/sysctl.conf"
)

create_baseline() {
  sha256sum "${MONITORED_FILES[@]}" > "$BASELINE_FILE"
  echo "Baseline created: $BASELINE_FILE ($(wc -l < "$BASELINE_FILE") files)"
}

verify_baseline() {
  if [ ! -f "$BASELINE_FILE" ]; then
    echo "FAIL: No baseline found at $BASELINE_FILE — run with --create-baseline first"
    return 1
  fi
  sha256sum -c "$BASELINE_FILE" --quiet 2>&1
  return $?
}
```

### Pattern 3: Reboot Snapshot-and-Compare

Two modes: `--snapshot` (pre-reboot) and `--compare` (post-reboot).

```bash
# Source: Project pattern from validate scripts + CONTEXT.md D-15/D-16/D-17

SNAPSHOT_FILE="/root/reboot-snapshot.txt"

snapshot_mode() {
  {
    echo "=== SNAPSHOT: $(date) ==="
    echo "--- sysctl hardened params ---"
    sysctl net.ipv4.conf.all.send_redirects
    sysctl net.ipv4.conf.default.send_redirects
    sysctl net.ipv4.tcp_syncookies
    sysctl net.ipv6.conf.all.accept_redirects
    echo "--- listening services (ss -tlnp) ---"
    ss -tlnp
    echo "--- iptables ruleset hash ---"
    iptables-save | sha256sum
    echo "--- config file hashes ---"
    sha256sum /etc/sysctl.conf /etc/sysconfig/firewall.local /etc/ssh/sshd_config
  } > "$SNAPSHOT_FILE"
  echo "Snapshot written to $SNAPSHOT_FILE"
  echo "Now reboot IPFire: reboot"
  echo "After reboot, run: bash validate-reboot.sh --compare"
}

compare_mode() {
  # Capture current state, diff against stored snapshot
  CURRENT=$(mktemp /tmp/reboot-current.XXXXXX)
  # ... same capture block ...
  diff "$SNAPSHOT_FILE" "$CURRENT"
  # Exit 0 if no diff, 1 if differences found
}
```

### Pattern 4: Pakfire Manifest Generation

```bash
# Source: IPFire Pakfire docs — /opt/pakfire/db/installed/ contains one file per installed add-on
ls /opt/pakfire/db/installed/ > /root/firewall-repo/manifests/pakfire-manifest.txt
echo "Generated: $(wc -l < /root/firewall-repo/manifests/pakfire-manifest.txt) packages"
```

### Pattern 5: WUI Certificate Extraction

```bash
# Source: IPFire wiki — certificates at /etc/httpd/
# Extract fingerprint from both RSA and ECDSA certs

# RSA certificate
openssl x509 -in /etc/httpd/server.crt -noout \
  -fingerprint -sha256 -subject -dates

# ECDSA certificate
openssl x509 -in /etc/httpd/server-ecdsa.crt -noout \
  -fingerprint -sha256 -subject -dates

# Verify port 444 is serving the expected cert
openssl s_client -connect 127.0.0.1:444 </dev/null 2>/dev/null | \
  openssl x509 -noout -fingerprint -sha256
```

### Pattern 6: validate-all.sh Orchestrator Architecture

```bash
#!/bin/bash
# validate-all.sh — Unified acceptance test suite for all phases
# Run on IPFire. SSHes to supportTAK-server for Phase 5.
# Usage: bash /root/firewall-repo/scripts/validate-all.sh

REPO="/root/firewall-repo"
SCRIPTS="$REPO/scripts"
PHASE_RESULTS=()
OVERALL_FAIL=0

run_phase() {
  local phase_num="$1"
  local script="$2"
  local run_location="$3"  # "local" or "remote"

  echo ""
  echo "=========================================="
  echo "  PHASE $phase_num VALIDATION"
  echo "=========================================="

  if [ "$run_location" = "remote" ]; then
    # Phase 5: run on supportTAK-server via SSH
    ssh -i /root/.ssh/ipfire_supporttak_ed25519 \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=15 \
        -o BatchMode=yes \
        opsadmin@192.168.1.101 \
        "source /opt/telemetry/telemetry/.env && sudo -E bash /opt/telemetry/scripts/$script"
  else
    bash "$SCRIPTS/$script"
  fi

  local exit_code=$?
  PHASE_RESULTS+=("Phase $phase_num: $([ $exit_code -eq 0 ] && echo PASS || echo FAIL)")
  [ $exit_code -ne 0 ] && OVERALL_FAIL=1
}

run_phase 1 "validate-phase1.sh" "local"
run_phase 2 "validate-phase2.sh" "local"
run_phase 3 "validate-phase3.sh" "local"
run_phase 4 "validate-phase4.sh" "local"
run_phase 5 "validate-phase5.sh" "remote"
run_phase 6 "validate-phase6.sh" "local"

# Summary table
echo ""
echo "=========================================="
echo "  VALIDATION SUITE SUMMARY"
echo "=========================================="
for result in "${PHASE_RESULTS[@]}"; do
  echo "  $result"
done
echo ""
[ $OVERALL_FAIL -eq 0 ] && echo "ALL PHASES PASS" || echo "VALIDATION FAILED — see above"
exit $OVERALL_FAIL
```

### Pattern 7: validate-phase6.sh Structure

```bash
#!/bin/bash
# validate-phase6.sh — Phase 6 System Hardening validation
# Run ON IPFire
# Exits: 0 if all automated checks pass, 1 if any fail

FAIL=0; PASS=0; SKIP=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "SKIP: $1 (manual verification required)"; SKIP=$((SKIP + 1)); }

# --- HARD-01: Service audit ---
# --- HARD-02: File permissions ---
# --- HARD-03: File integrity baseline exists and passes ---
# --- HARD-04: sysctl hardened values ---
# --- HARD-05: WUI certificate exists and is documented ---
```

### Anti-Patterns to Avoid

- **Never `chmod -x /etc/init.d/service`** to disable a service — causes boot-time errors on IPFire. Use symlink manipulation (`mv /etc/rc.d/rc3.d/S*service /root/`) or simply leave enabled if needed.
- **Never set `net.ipv4.ip_forward = 0`** — this would break all routing and NAT. This CIS control is explicitly excepted for router/firewall systems.
- **Never overwrite `/etc/sysctl.conf`** — append only, or check existing values first. IPFire may have baseline values set.
- **Never store certificate private keys** (`server.key`) in the git repo — document fingerprints only, not keys.
- **Do not use `systemctl`** — command does not exist on IPFire 2.x. Use `/etc/rc.d/init.d/<service> status`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File integrity hashing | Custom recursive hash tree | `sha256sum` + stored baseline file | Pattern already proven in check-suricata-integrity.sh |
| Certificate inspection | Custom TLS handshake parser | `openssl x509 -noout` | Standard tool available on IPFire |
| Package inventory | Custom file scanner | `ls /opt/pakfire/db/installed/` | Pakfire tracks installs here per official docs |
| Service enumeration | Custom port scanner | `ss -tlnp` | Already used in validate-phase2.sh |
| Snapshot diff | Custom state serializer | `iptables-save` + `sysctl` + `sha256sum` piped to file, then `diff` | Shell builtins; no dependencies |
| Sysctl persistence | Startup script that sets values | `/etc/sysctl.conf` | IPFire reads this on boot; supported path |

**Key insight:** IPFire's custom buildroot means standard Linux hardening tools (auditd, SELinux, apparmor, fail2ban, lynis auto-scan) are either unavailable or inappropriate. The correct pattern is to use the primitives that ARE available (sha256sum, sysctl, ss, iptables-save, openssl) and compose them into targeted scripts.

---

## Common Pitfalls

### Pitfall 1: sysctl Changes That Break Routing

**What goes wrong:** Setting `net.ipv4.ip_forward = 0` per CIS Level 1 disables all packet forwarding. IPFire stops routing between zones. All clients lose internet access.
**Why it happens:** CIS benchmarks target general-purpose servers, not routers. The firewall exception is documented but easy to miss.
**How to avoid:** Only apply the specific params identified as needed (send_redirects). Explicitly document deviations. Verify `ip_forward` remains 1 after applying sysctl.conf changes.
**Warning signs:** GREEN zone loses internet immediately after `sysctl -p`. Check `sysctl net.ipv4.ip_forward` — must be 1.

### Pitfall 2: SysVinit vs. systemd Commands

**What goes wrong:** Using `systemctl status <service>` returns "command not found" on IPFire 2.x.
**Why it happens:** IPFire 2.x uses SysVinit, not systemd. systemd is planned for IPFire 3.x only.
**How to avoid:** Use `/etc/rc.d/init.d/<service> status` in all scripts. The existing validate scripts correctly use this pattern.
**Warning signs:** `systemctl` not found in PATH. Check with `which systemctl` — should return nothing.

### Pitfall 3: Boot Symlink Persistence After Core Updates

**What goes wrong:** Disabling a service by moving its rc3.d symlink may be reverted by a Core Update if the update reinstalls the package.
**Why it happens:** Pakfire package upgrades can regenerate `/etc/rc.d/rc3.d/` symlinks.
**How to avoid:** For Phase 6 conservative audit, only disable services that are clearly unnecessary add-ons (avahi, cups). Document which services were disabled and why. Validate-phase6.sh should check for unexpected services, not just disabled ones.
**Warning signs:** After Core Update, disabled service reappears in `ss -tlnp`.

### Pitfall 4: validate-all.sh Phase 5 SSH Failure Causes False Full-Fail

**What goes wrong:** If supportTAK-server is unreachable (off, rebooting, network issue), validate-all.sh marks Phase 5 as FAIL and exits 1, making the entire suite appear failed.
**Why it happens:** SSH failure returns non-zero exit code; orchestrator treats as phase failure.
**How to avoid:** Add SSH reachability pre-check before attempting remote execution. If unreachable, mark Phase 5 as SKIP rather than FAIL. The existing validate-phase5.sh TEL-01 check already handles SSH failure with skip() — mirror that pattern in validate-all.sh.
**Warning signs:** validate-all.sh exits 1 when IPFire itself is healthy but supportTAK-server is down.

### Pitfall 5: File Integrity Baseline Not Rebuilt After Intentional Changes

**What goes wrong:** After deploying sysctl hardening (modifying /etc/sysctl.conf), the integrity check reports WARN/FAIL because the file hash changed.
**Why it happens:** Baseline was created before the hardening changes.
**How to avoid:** The workflow must be: (1) deploy hardening, (2) verify hardening, (3) update baseline. Document this order explicitly. Include a `--update-baseline` flag in the integrity script.
**Warning signs:** Integrity check reports WARN immediately after deploying Phase 6 hardening.

### Pitfall 6: openssl Certificate Commands Vary by Version

**What goes wrong:** `openssl x509 -fingerprint` output format changed between OpenSSL 1.x and 3.x. On IPFire's custom buildroot, the version may differ from a dev machine.
**Why it happens:** IPFire ships its own OpenSSL version in the buildroot.
**How to avoid:** Check `openssl version` on IPFire before using output in scripts. Use `-fingerprint -sha256` explicitly (not deprecated SHA1). The cert files themselves (`server.crt`) are stable — parse them on IPFire, not cross-platform.
**Warning signs:** `openssl x509` command format errors or empty output.

### Pitfall 7: syslog.conf Not in Default Backup Scope

**What goes wrong:** `/etc/syslog.conf` is not in `backup-include.user` by default. After a Core Update restore, syslog forwarding to 192.168.1.101 is lost.
**Why it happens:** Default IPFire backup only covers `/var/ipfire/`. Custom `/etc/` files need explicit inclusion.
**How to avoid:** Add `/etc/syslog.conf` to `backup-include.user` in this phase. Also add `/etc/sysctl.conf` and the integrity baseline file.
**Warning signs:** After backup-restore cycle, `grep 192.168.1.101 /etc/syslog.conf` returns empty.

---

## IPFire Service Audit Reference

### Services in Known-Good Baseline (DO NOT DISABLE)

Based on D-04 from CONTEXT.md and IPFire architecture:

| Service | Port(s) | Init Script | Justification |
|---------|---------|-------------|---------------|
| unbound | 53/udp | `/etc/rc.d/init.d/unbound` | DNS resolver — core service |
| sshd | 22/tcp | `/etc/rc.d/init.d/sshd` | Management access |
| httpd | 81/tcp, 444/tcp, 1013/tcp | `/etc/rc.d/init.d/apache` | WUI + redirect |
| ntpd | 123/udp | `/etc/rc.d/init.d/ntp` | Time sync |
| dhcpd | (no listen port shown externally) | `/etc/rc.d/init.d/dhcp` | DHCP server on GREEN |
| guardian | (no TCP listen) | `/etc/rc.d/init.d/guardian` | SSH/WUI brute-force protection |
| suricata | (no TCP listen) | WUI-managed via fcron | IDS/IPS |
| fcron | (no TCP listen) | `/etc/rc.d/init.d/fcron` | Cron daemon — runs rule updates |
| syslog | (no TCP listen) | `/etc/rc.d/init.d/sysklogd` | Local + remote syslog |
| collectd | (no external listen) | `/etc/rc.d/init.d/collectd` | WUI metrics graphs |

### Services That May Be Present and Are Safe to Disable (if found)

| Service | Why Safe to Disable |
|---------|---------------------|
| avahi-daemon | mDNS/Bonjour — not needed on a firewall |
| cups | Printing — not needed on a firewall |
| bluetooth | No BT on N100 mini-PC |
| rpcbind / portmapper | NFS services — not needed |
| isdn / ppp services | Not applicable to this hardware |

### How to Disable on SysVinit (IPFire method)

```bash
# Soft disable: move startup symlink (recoverable, preferred)
# This prevents auto-start without removing the init script
mv /etc/rc.d/rc3.d/S*avahi* /root/  # example

# Verify service no longer starts at boot
ls /etc/rc.d/rc3.d/ | grep -i avahi  # should be empty
```

---

## File Permissions Targets (HARD-02)

Based on IPFire hardening guide and CIS Linux principles adapted for IPFire paths:

| File/Directory | Target Perms | Owner | Rationale |
|----------------|-------------|-------|-----------|
| `/etc/ssh/sshd_config` | 600 | root:root | SSH config must not be world-readable |
| `/root/.ssh/` | 700 | root:root | SSH dir permissions (already checked in validate-phase3.sh) |
| `/root/.ssh/authorized_keys` | 600 | root:root | Key file (already checked in validate-phase3.sh) |
| `/etc/sysconfig/firewall.local` | 700 (executable) | root:root | Firewall script — executable, root-only |
| `/root/integrity-baseline.sha256` | 600 | root:root | Integrity baseline — root-only read |
| `/etc/sysctl.conf` | 644 | root:root | Standard: root writes, world reads |
| `/var/ipfire/backup/include.user` | 600 | root:root | Backup config — restrict write |

Note: IPFire's `/var/ipfire/` directory has its own permission conventions enforced by the IPFire install process. Avoid recursively `chmod`-ing `/var/ipfire/` — the IPFire WUI and CGI scripts depend on specific permissions set during installation. Verify individual files, do not mass-change.

---

## WUI Certificate Documentation Pattern

### Certificate Files

```
/etc/httpd/server.crt         — RSA certificate
/etc/httpd/server-ecdsa.crt   — ECDSA certificate
/etc/httpd/server.key         — RSA private key (DO NOT export to git)
/etc/httpd/server-ecdsa.key   — ECDSA private key (DO NOT export to git)
```

### Extraction and Documentation Commands

```bash
# Extract RSA cert details (run on IPFire)
openssl x509 -in /etc/httpd/server.crt -noout \
  -subject -issuer -dates -fingerprint -sha256

# Example output shape:
# subject=CN=ipfire.localdomain
# issuer=CN=ipfire.localdomain
# notBefore=Mar  1 12:00:00 2024 GMT
# notAfter=Jan  1 00:00:00 9999 GMT  (IPFire uses near-infinite validity)
# SHA256 Fingerprint=AA:BB:CC:...

# Verify live server cert on port 444
openssl s_client -connect 127.0.0.1:444 -servername ipfire.localdomain \
  </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256 -dates
```

### What to Store in Repo

Store in `docs/wui-certificate.md`:
- SHA256 fingerprint of server.crt
- Certificate validity dates
- Subject/Issuer fields
- Documented procedure to regenerate if hostname changes
- Browser warning context (self-signed is expected — this is by design)

DO NOT store: private keys, full certificate PEM, key material of any kind.

---

## Backup Include List Extensions (HARD-02/HARD-03)

The current `backup-include.user` covers only udev rules and firewall.local. Phase 6 must extend it:

```
# Current (Phase 1)
/etc/udev/rules.d/30-persistent-network.rules
/etc/sysconfig/firewall.local

# Add in Phase 6
/etc/sysctl.conf
/etc/syslog.conf
/etc/ssh/sshd_config
/root/integrity-baseline.sha256
/root/firewall-repo/manifests/pakfire-manifest.txt
```

This aligns backup coverage with integrity monitoring coverage.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Bash test scripts (existing project pattern) |
| Config file | None — self-contained scripts |
| Quick run command | `bash /root/firewall-repo/scripts/validate-phase6.sh` |
| Full suite command | `bash /root/firewall-repo/scripts/validate-all.sh` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | Script Exists? |
|--------|----------|-----------|-------------------|----------------|
| HARD-01 | No unexpected services listening | Automated | `ss -tlnp` diff against known baseline | Wave 0 (new) |
| HARD-01 | Pakfire manifest generated | Automated | `ls /opt/pakfire/db/installed/` → file exists | Wave 0 (new) |
| HARD-02 | Key file permissions correct | Automated | `stat -c "%a" <file>` checks | Wave 0 (new) |
| HARD-03 | Integrity baseline exists and passes | Automated | `sha256sum -c /root/integrity-baseline.sha256` | Wave 0 (new) |
| HARD-04 | sysctl hardened values confirmed | Automated | `sysctl net.ipv4.conf.all.send_redirects` == 0 | Wave 0 (new) |
| HARD-05 | WUI cert exists, documented | Automated + Manual | `openssl x509 -in /etc/httpd/server.crt -noout` | Wave 0 (new) |
| VAL-01 | All NICs up, correct zones | Automated | `validate-phase1.sh` (exists) | Exists |
| VAL-02 | Routing validation | Manual-SKIP | External host required | Exists (skip) |
| VAL-03 | Firewall default-deny confirmed | Automated | `validate-phase1.sh` CUSTOMINPUT checks | Exists |
| VAL-04 | NAT validation | Manual-SKIP | External host required | Exists (skip) |
| VAL-05 | DHCP correct options | Automated | `validate-phase2.sh` | Exists |
| VAL-06 | DNS DNSSEC + DoT active | Automated | `validate-phase2.sh` | Exists |
| VAL-07 | IDS alert on test signature | Automated | `validate-phase4.sh` | Exists |
| VAL-08 | Sysctl/iptables survive reboot | Manual (snapshot) | `validate-reboot.sh --compare` diff | Wave 0 (new) |
| VAL-09 | All services running post-boot | Automated | `validate-all.sh` (calls all per-phase) | Wave 0 (new) |
| VAL-10 | Telemetry logs in Grafana | Automated | `validate-phase5.sh` via SSH | Exists |
| VAL-11 | Unified pass/fail acceptance script | Automated | `validate-all.sh` | Wave 0 (new) |

### Sampling Rate
- **Per task commit:** `bash /root/firewall-repo/scripts/validate-phase6.sh`
- **Per wave merge:** `bash /root/firewall-repo/scripts/validate-all.sh`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps (New Scripts to Create)

- [ ] `scripts/validate-phase6.sh` — HARD-01 through HARD-05
- [ ] `scripts/validate-all.sh` — VAL-11 orchestrator
- [ ] `scripts/validate-reboot.sh` — VAL-08 snapshot-and-compare
- [ ] `scripts/check-integrity.sh` — HARD-03 multi-file baseline (extends check-suricata-integrity.sh pattern)
- [ ] `docs/wui-certificate.md` — HARD-05 certificate documentation
- [ ] `manifests/pakfire-manifest.txt` — HARD-01/D-03 installed package list
- [ ] Update `configs/firewall/backup-include.user` — extend with Phase 6 files

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| auditd syscall auditing | SHA256 file hash monitoring | Project decision (CONTEXT.md D-09) | Lower overhead, adequate for SOHO |
| Promtail log agent | Grafana Alloy 1.14.1 | Feb 2026 | Already handled in Phase 5 |
| Snort IDS | Suricata 8.0.3 (native) | IPFire CU131 | Already handled in Phase 4 |
| Manual service inventory | `pakfire` manifest from `/opt/pakfire/db/installed/` | IPFire 2.x | Direct CLI path for reproducibility |

**Deprecated/outdated on IPFire:**
- `systemctl` — does not exist on IPFire 2.x. Will exist in IPFire 3.x (future).
- `update-rc.d` — Debian-specific; IPFire uses direct symlink manipulation in `/etc/rc.d/rc3.d/`.
- `chkconfig` — not available in IPFire buildroot.

---

## Open Questions

1. **Which specific services are present on this IPFire installation**
   - What we know: Known-good baseline from D-04 lists unbound:53, sshd:22, httpd:81/444/1013
   - What's unclear: Whether fcron, collectd, guardian, or any Pakfire add-ons create additional listeners
   - Recommendation: Run `ss -tlnp` on live system in the deployment checkpoint task; compare against expected baseline

2. **Does `/etc/sysctl.conf` already have content on this IPFire install**
   - What we know: IPFire ships some sysctl defaults, but send_redirects=1 was observed
   - What's unclear: Whether appending to sysctl.conf will conflict with existing values
   - Recommendation: Deployment task reads existing file before appending; checks for duplicate keys

3. **SSH key for IPFire to supportTAK-server**
   - What we know: CONTEXT.md D-12 states the key "already deployed"; CONTEXT.md code_context says `/root/.ssh/` or needs to be deployed
   - What's unclear: Exact key filename (`ipfire_supporttak_ed25519` or different name)
   - Recommendation: Deployment runbook step to verify `ssh -i /root/.ssh/<keyname> opsadmin@192.168.1.101 'echo ok'` before validate-all.sh assumes it works

4. **WUI certificate validity period**
   - What we know: IPFire generates self-signed cert at install time; some installs use near-infinite validity (year 9999)
   - What's unclear: Actual validity on this specific install
   - Recommendation: HARD-05 check reads cert validity; if validity < 365 days remaining, flag as finding

---

## Sources

### Primary (HIGH confidence)
- [IPFire Good Security Practice](https://www.ipfire.org/docs/optimization/start/security_hardening/good_security_practice) — official IPFire hardening guide
- [IPFire Additional Security Configuration](https://www.ipfire.org/docs/optimization/start/security_hardening/additional_security_configuration) — official IPFire hardening guide
- [IPFire Generate SSL Certificate](https://wiki.ipfire.org/optimization/ssl_cert) — certificate location and management
- [IPFire Pakfire Console](https://www.ipfire.org/docs/configuration/ipfire/pakfire/pakfireconsole) — pakfire CLI commands
- `scripts/check-suricata-integrity.sh` — project codebase (sha256sum baseline pattern)
- `scripts/validate-phase1.sh` through `validate-phase5.sh` — project codebase (pass/fail/skip pattern)
- `configs/firewall/firewall.local` — project codebase (SysVinit, interface sourcing patterns)

### Secondary (MEDIUM confidence)
- [IPFire Community: Disabling Services](https://community.ipfire.org/t/anyone-know-a-clean-way-to-disable-a-etc-init-d-service/4620) — SysVinit symlink method confirmed by community
- [IPFire WebGUI SSL Certificate Files](https://community.ipfire.org/t/ipfire-webgui-ssl-certificate-files/2974) — certificate location confirmed
- [CIS Linux Level 1 sysctl guidance (Red Hat)](https://access.redhat.com/solutions/7085277) — sysctl parameter values; firewall/router exception documented
- [IPFire Community: Start/Stop Services](https://community.ipfire.org/t/start-or-stop-an-ipfire-service/6505) — SysVinit init script paths confirmed

### Tertiary (LOW confidence)
- WebSearch for default IPFire service ports — collectd port 25826 returned but not verified against live install

---

## Metadata

**Confidence breakdown:**
- Sysctl hardening params: HIGH — confirmed against CIS Linux docs; IPFire-specific exceptions explicitly verified
- File integrity pattern: HIGH — directly derived from existing project code (check-suricata-integrity.sh)
- Service audit: MEDIUM — D-04 baseline defined in CONTEXT.md; specific services on live system need `ss -tlnp` to verify
- Certificate location: HIGH — confirmed by official IPFire wiki (/etc/httpd/)
- validate-all.sh architecture: HIGH — directly extends existing per-phase script patterns in codebase
- File permissions targets: MEDIUM — based on CIS Linux principles adapted for IPFire paths; no IPFire-specific permission guide found

**Research date:** 2026-03-25
**Valid until:** 2026-06-25 (stable — IPFire 2.x architecture; sysctl semantics don't change rapidly)
