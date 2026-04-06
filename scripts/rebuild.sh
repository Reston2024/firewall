#!/bin/bash
# rebuild.sh — Master rebuild orchestrator
# Restores full IPFire configuration from git repo to a fresh install
# Run FROM DEV MACHINE (not on IPFire)
# Usage: bash rebuild.sh [IPFIRE_IP]
# Default IP: 192.168.1.1
#
# Prerequisites (Section 0):
#   1. Fresh IPFire 2.29 CU200 installed on target hardware
#   2. SSH key at ~/.ssh/ipfire_ed25519 with public key in IPFire authorized_keys
#   3. WUI certificate installed (auto-generated on first IPFire boot)
#   4. IPFire reachable at IPFIRE_IP from this machine
#
# Per D-02: Fully automated, non-interactive — no prompts, no pauses
# Per D-03: SCP from dev machine to IPFire (not git clone on IPFire)
# Per D-05: Every operation is idempotent (safe to re-run)
# Per D-06: Final step runs validate-all.sh as acceptance gate

set -euo pipefail

# --- Variables ---
IPFIRE="${1:-192.168.1.1}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SSH_KEY="$HOME/.ssh/ipfire_ed25519"
SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${REPO_ROOT}/configs/ssh/known_hosts"
SSH="ssh -i $SSH_KEY $SSH_OPTS root@$IPFIRE"
SCP="scp -i $SSH_KEY -o BatchMode=yes"
REMOTE_REPO="/root/firewall-repo"

# --- Counters and helpers ---
PHASE_PASS=0
PHASE_FAIL=0
FAIL_TOTAL=0
WUI_STEPS=()

step()  { echo ""; echo "=== $1 ==="; }
pass()  { echo "PASS: $1"; }
fail()  { echo "FAIL: $1"; FAIL_TOTAL=$((FAIL_TOTAL + 1)); }
note()  { echo "NOTE: $1"; }
wui()   { WUI_STEPS+=("$1"); }

echo "=== IPFire Rebuild Orchestrator — $(date) ==="
echo "Target: $IPFIRE"
echo "Repo:   $REPO_ROOT"
echo ""

# -----------------------------------------------------------------------
# Section 0: Prerequisites (per D-04)
# -----------------------------------------------------------------------
step "Section 0: Prerequisites"

if [ ! -f "$SSH_KEY" ]; then
  echo "FAIL: SSH key not found at $SSH_KEY"
  echo "      Run: ssh-keygen -t ed25519 -f $SSH_KEY"
  echo "      Then copy public key to IPFire: ssh-copy-id -i $SSH_KEY root@$IPFIRE"
  exit 1
fi
pass "SSH key found: $SSH_KEY"

if ! $SSH 'echo ok' >/dev/null 2>&1; then
  echo "FAIL: Cannot reach IPFire at $IPFIRE"
  echo "      Verify:"
  echo "        1. IPFire is booted and reachable"
  echo "        2. SSH is enabled in WUI > System > SSH Access"
  echo "        3. Public key is in /root/.ssh/authorized_keys on IPFire"
  exit 1
fi
pass "SSH connectivity: root@$IPFIRE"

echo ""
echo "Prerequisites OK — target: $IPFIRE"

# -----------------------------------------------------------------------
# Section 1: Deploy repo to IPFire via SCP
# -----------------------------------------------------------------------
step "Section 1: Deploy repo to IPFire"

note "Deploying scripts, configs, manifests, rollback, docs, decisions..."
$SCP -r "$REPO_ROOT/scripts/" "root@$IPFIRE:$REMOTE_REPO/scripts/"
$SCP -r "$REPO_ROOT/configs/" "root@$IPFIRE:$REMOTE_REPO/configs/"
$SCP -r "$REPO_ROOT/manifests/" "root@$IPFIRE:$REMOTE_REPO/manifests/"
$SCP -r "$REPO_ROOT/rollback/" "root@$IPFIRE:$REMOTE_REPO/rollback/"
$SCP -r "$REPO_ROOT/docs/" "root@$IPFIRE:$REMOTE_REPO/docs/"
$SCP -r "$REPO_ROOT/decisions/" "root@$IPFIRE:$REMOTE_REPO/decisions/"
pass "Repo directories deployed to $REMOTE_REPO"

note "Fixing CRLF line endings and setting permissions (Windows dev machine)..."
$SSH "find $REMOTE_REPO -name \"*.sh\" -exec sed -i \"s/\r\$//\" {} \\; && chmod +x $REMOTE_REPO/scripts/*.sh && chmod +x $REMOTE_REPO/rollback/*.sh"
pass "CRLF fix applied, scripts marked executable"

# -----------------------------------------------------------------------
# Section 2: Create /root/rollback/ on IPFire
# -----------------------------------------------------------------------
step "Section 2: Create rollback directory"

$SSH 'mkdir -p /root/rollback'
pass "Rollback directory: /root/rollback"

# WUI steps — collected throughout; printed at the end
wui "Firewall > NAT: Enable IP masquerade on RED interface"
wui "DHCP Server: Configure GREEN zone DHCP (range, gateway, DNS, NTP options)"
wui "IDS/IPS > Intrusion Detection: Enable IPS on RED+GREEN, select ET Community rules, set monitor mode"
wui "SSH Settings: Verify key-only auth enabled, root login allowed"
wui "Guardian: Install via Pakfire if missing, enable SSH + WUI protection"
wui "Install missing Pakfire packages via Pakfire > Available (expected: guardian)"

# -----------------------------------------------------------------------
# Section 3: Phase 1 — Platform Foundation
# -----------------------------------------------------------------------
step "Phase 1: Platform Foundation"
$SSH "bash $REMOTE_REPO/scripts/deploy-phase1.sh"
if [ $? -eq 0 ]; then
  pass "Phase 1 complete"
  PHASE_PASS=$((PHASE_PASS + 1))
else
  fail "Phase 1 failed"
  PHASE_FAIL=$((PHASE_FAIL + 1))
fi

# -----------------------------------------------------------------------
# Section 4: Phase 2 — Core Network Services
# -----------------------------------------------------------------------
step "Phase 2: Core Network Services"
$SSH "bash $REMOTE_REPO/scripts/deploy-phase2.sh"
if [ $? -eq 0 ]; then
  pass "Phase 2 complete"
  PHASE_PASS=$((PHASE_PASS + 1))
else
  fail "Phase 2 failed"
  PHASE_FAIL=$((PHASE_FAIL + 1))
fi

# -----------------------------------------------------------------------
# Section 5: Phase 3 — SSH Hardening
# -----------------------------------------------------------------------
step "Phase 3: SSH Hardening"
$SSH "bash $REMOTE_REPO/scripts/deploy-phase3.sh"
if [ $? -eq 0 ]; then
  pass "Phase 3 complete"
  PHASE_PASS=$((PHASE_PASS + 1))
else
  fail "Phase 3 failed"
  PHASE_FAIL=$((PHASE_FAIL + 1))
fi

# -----------------------------------------------------------------------
# Section 6: Phase 4 — Suricata IDS/IPS
# -----------------------------------------------------------------------
step "Phase 4: Suricata IDS/IPS"
$SSH "bash $REMOTE_REPO/scripts/deploy-phase4.sh"
if [ $? -eq 0 ]; then
  pass "Phase 4 complete"
  PHASE_PASS=$((PHASE_PASS + 1))
else
  fail "Phase 4 failed"
  PHASE_FAIL=$((PHASE_FAIL + 1))
fi

# -----------------------------------------------------------------------
# Section 7: Phase 5 — Telemetry Syslog
# -----------------------------------------------------------------------
step "Phase 5: Telemetry Syslog"
$SSH "bash $REMOTE_REPO/scripts/deploy-phase5.sh"
if [ $? -eq 0 ]; then
  pass "Phase 5 complete"
  PHASE_PASS=$((PHASE_PASS + 1))
else
  fail "Phase 5 failed"
  PHASE_FAIL=$((PHASE_FAIL + 1))
fi

# -----------------------------------------------------------------------
# Section 8: Phase 6 — System Hardening
# -----------------------------------------------------------------------
step "Phase 6: System Hardening"
$SSH "bash $REMOTE_REPO/scripts/deploy-phase6.sh"
if [ $? -eq 0 ]; then
  pass "Phase 6 complete"
  PHASE_PASS=$((PHASE_PASS + 1))
else
  fail "Phase 6 failed"
  PHASE_FAIL=$((PHASE_FAIL + 1))
fi

# -----------------------------------------------------------------------
# Section 9: Pakfire Manifest Verification (REPO-03)
# -----------------------------------------------------------------------
step "Pakfire Manifest Verification"
$SSH "bash -c '
  for pkg in \$(cat $REMOTE_REPO/manifests/pakfire-manifest-expected.txt); do
    if [ -d /opt/pakfire/db/installed/meta-\$pkg ]; then
      echo \"OK: \$pkg installed\"
    else
      echo \"MISSING: \$pkg — install via: pakfire install \$pkg\"
    fi
  done
'"
note "Pakfire installs cannot be fully automated — review MISSING entries above"
wui "Install missing Pakfire packages via Pakfire > Available (expected: guardian)"

# -----------------------------------------------------------------------
# Section 10: Generate File Manifest (REPO-04 drift baseline)
# -----------------------------------------------------------------------
step "Generate File Manifest"
$SSH "bash $REMOTE_REPO/scripts/check-drift.sh --generate" || true
$SCP "root@$IPFIRE:$REMOTE_REPO/manifests/file-manifest.sha256" "$REPO_ROOT/manifests/file-manifest.sha256" || true
note "file-manifest.sha256 pulled back to repo — commit to preserve baseline"

# -----------------------------------------------------------------------
# Section 11: Final Validation (per D-06)
# -----------------------------------------------------------------------
step "Final Validation"
$SSH "bash $REMOTE_REPO/scripts/validate-all.sh"
if [ $? -eq 0 ]; then
  pass "Validation suite passed"
else
  fail "Validation suite FAILED — review output above"
fi

# -----------------------------------------------------------------------
# Section 12: WUI Manual Steps Summary
# -----------------------------------------------------------------------
step "MANUAL STEPS REQUIRED (WUI-only)"
echo "The following settings must be configured via IPFire WUI at https://$IPFIRE:444"
echo ""
for i in "${!WUI_STEPS[@]}"; do
  echo "  $((i+1)). ${WUI_STEPS[$i]}"
done

# -----------------------------------------------------------------------
# Final summary and exit
# -----------------------------------------------------------------------
echo ""
echo "=========================================="
echo "  REBUILD SUMMARY"
echo "=========================================="
echo "  Phases passed: $PHASE_PASS"
echo "  Phases failed: $PHASE_FAIL"
echo "  Total errors:  $FAIL_TOTAL"
echo "  WUI steps remaining: ${#WUI_STEPS[@]}"
echo "=========================================="

if [ "$FAIL_TOTAL" -eq 0 ]; then
  echo "REBUILD COMPLETE — all automated steps passed"
  echo "Complete the WUI manual steps above, then re-run validate-all.sh"
  exit 0
else
  echo "REBUILD FAILED — $FAIL_TOTAL error(s). Review output above."
  exit 1
fi
