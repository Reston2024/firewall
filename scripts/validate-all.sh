#!/bin/bash
# validate-all.sh — Unified validation orchestrator for all phases
# Usage: bash /root/firewall-repo/scripts/validate-all.sh [--phase N|--phase tri06]
#
# Run context:
#   - Phases 1–6 require IPFire-local tools (iptables, sysctl, etc) and MUST
#     run on IPFire. Phase 5 is a special case that SSHes to supportTAK.
#   - Phases 9, 10, 13, 14, and TRI-06 SSH out to supportTAK from wherever
#     they run. They work from IPFire (if keys are set up) or from the laptop.
#   - Phase 11 is retracted per ADR-E04 (AI analyst removed from data layer).
#   - Phase 12 validator is deprecated per ADR-E04 but RAG infrastructure
#     stays verified via validate-phase13.sh TRI-04 (ChromaDB health check).
#
# Exits: 0 if no FAILs (SKIPs allowed), 1 if any phase FAILed.

REPO="/root/firewall-repo"
SCRIPTS="$REPO/scripts"
SUPPORTTAK_HOST="opsadmin@192.168.1.22"

# Resolve SCRIPTS directory from script location if /root/firewall-repo
# doesn't exist (i.e., running from the laptop or a different checkout).
if [ ! -d "$REPO" ]; then
  SCRIPT_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
  REPO="$(cd "${SCRIPT_SELF_DIR}/.." && pwd)"
  SCRIPTS="${REPO}/scripts"
fi

# --- Host detection ---
# Phases 1–6 only work on IPFire (iptables, sysctl, firewall.local, etc).
# Phases 9, 10, 13, 14, and TRI-06 only work from a host that can SSH to
# supportTAK. For v2.0, IPFire lacks the SSH key/host-verification to reach
# supportTAK, so the laptop drives those checks. Detect host and scope
# phases automatically. Override with --host {ipfire|laptop|all}.
detect_host() {
  local hn
  hn=$(uname -n 2>/dev/null | tr '[:upper:]' '[:lower:]')
  if [ -f /etc/ipfire-release ] || [ -f /var/ipfire/general-functions.pl ] \
     || [ "$hn" = "ipfire" ] || [ "$hn" = "ipfire.localdomain" ]; then
    echo "ipfire"
  elif [ -r /etc/os-release ] && grep -q 'ID=ubuntu' /etc/os-release \
       && echo " $(hostname -I 2>/dev/null) " | grep -q " 192.168.1.22 "; then
    echo "supporttak"
  else
    echo "laptop"
  fi
}

HOST_ROLE="$(detect_host)"

# --- Parse arguments ---
SINGLE_PHASE=""
HOST_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --phase)
      shift
      SINGLE_PHASE="$1"
      ;;
    --host)
      shift
      HOST_OVERRIDE="$1"
      ;;
    *)
      echo "Usage: $0 [--phase N|tri06] [--host ipfire|laptop|all]"
      exit 1
      ;;
  esac
  shift
done

if [ -n "$HOST_OVERRIDE" ]; then
  HOST_ROLE="$HOST_OVERRIDE"
fi

# --- Counters ---
PHASE_PASS=0
PHASE_FAIL=0
PHASE_SKIP=0
OVERALL_FAIL=0

# PHASE_RESULTS array: "N|PASS|Phase name", "N|FAIL|Phase name", "N|SKIP|reason"
PHASE_RESULTS=()

# --- run_phase(): execute a single local phase script ---
# Usage: run_phase <phase_num> <script_path> <phase_label>
run_phase() {
  local PHASE_NUM="$1"
  local SCRIPT="$2"
  local LABEL="$3"

  echo ""
  echo "========== PHASE ${PHASE_NUM} VALIDATION =========="
  echo "Script: $SCRIPT"
  echo ""

  if [ ! -f "$SCRIPT" ]; then
    echo "SKIP: $SCRIPT not found — phase not yet deployed"
    PHASE_RESULTS+=("${PHASE_NUM}|SKIP|script not found: $SCRIPT")
    PHASE_SKIP=$((PHASE_SKIP + 1))
    return
  fi

  bash "$SCRIPT"
  local EXIT_CODE=$?

  if [ "$EXIT_CODE" -eq 0 ]; then
    PHASE_RESULTS+=("${PHASE_NUM}|PASS|$LABEL")
    PHASE_PASS=$((PHASE_PASS + 1))
  else
    PHASE_RESULTS+=("${PHASE_NUM}|FAIL|$LABEL")
    PHASE_FAIL=$((PHASE_FAIL + 1))
    OVERALL_FAIL=$((OVERALL_FAIL + 1))
  fi
}

# --- run_phase5_remote(): execute Phase 5 via SSH to supportTAK-server ---
run_phase5_remote() {
  echo ""
  echo "========== PHASE 5 VALIDATION =========="
  echo "Remote: $SUPPORTTAK_HOST"
  echo ""

  # Pre-check SSH reachability (10s timeout, no interactive prompts)
  if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$SUPPORTTAK_HOST" 'echo ok' >/dev/null 2>&1; then
    echo "SKIP: Cannot reach $SUPPORTTAK_HOST — supportTAK-server may be offline"
    PHASE_RESULTS+=("5|SKIP|supportTAK-server unreachable")
    PHASE_SKIP=$((PHASE_SKIP + 1))
    return
  fi

  # SSH reachable — run validate-phase5.sh remotely
  # Phase 5 requires sourcing .env for Grafana credentials then sudo -E bash
  ssh -o ConnectTimeout=15 -o BatchMode=yes \
    "$SUPPORTTAK_HOST" \
    "source /opt/telemetry/.env && sudo -E bash /opt/telemetry/scripts/validate-phase5.sh"
  local EXIT_CODE=$?

  if [ "$EXIT_CODE" -eq 0 ]; then
    PHASE_RESULTS+=("5|PASS|Telemetry Pipeline and Dashboards")
    PHASE_PASS=$((PHASE_PASS + 1))
  else
    PHASE_RESULTS+=("5|FAIL|Telemetry Pipeline and Dashboards")
    PHASE_FAIL=$((PHASE_FAIL + 1))
    OVERALL_FAIL=$((OVERALL_FAIL + 1))
  fi
}

# --- Main execution ---
echo "=== Validation Suite — All Phases — $(date) ==="

# --- run_phase_skip(): record a deliberate SKIP for a retracted phase ---
run_phase_skip() {
  local PHASE_NUM="$1"
  local REASON="$2"
  echo ""
  echo "========== PHASE ${PHASE_NUM} VALIDATION =========="
  echo "SKIP: phase ${PHASE_NUM} — ${REASON}"
  PHASE_RESULTS+=("${PHASE_NUM}|SKIP|${REASON}")
  PHASE_SKIP=$((PHASE_SKIP + 1))
}

# --- run_tri06(): standalone E2E gate (not a phase) ---
run_tri06() {
  echo ""
  echo "========== TRI-06 VALIDATION =========="
  echo "Script: $SCRIPTS/validate-tri06.sh"
  echo ""
  if [ ! -f "$SCRIPTS/validate-tri06.sh" ]; then
    echo "SKIP: validate-tri06.sh not found"
    PHASE_RESULTS+=("tri06|SKIP|script not found")
    PHASE_SKIP=$((PHASE_SKIP + 1))
    return
  fi
  bash "$SCRIPTS/validate-tri06.sh"
  local EXIT_CODE=$?
  if [ "$EXIT_CODE" -eq 0 ]; then
    PHASE_RESULTS+=("tri06|PASS|E2E Triage Receipt (TRI-06)")
    PHASE_PASS=$((PHASE_PASS + 1))
  else
    PHASE_RESULTS+=("tri06|FAIL|E2E Triage Receipt (TRI-06)")
    PHASE_FAIL=$((PHASE_FAIL + 1))
    OVERALL_FAIL=$((OVERALL_FAIL + 1))
  fi
}

# --- run_sync_eve(): v2.0.1 sync-eve pipeline watchdog ---
run_sync_eve() {
  echo ""
  echo "========== SYNC-EVE VALIDATION =========="
  echo "Script: $SCRIPTS/validate-sync-eve.sh"
  echo ""
  if [ ! -f "$SCRIPTS/validate-sync-eve.sh" ]; then
    echo "SKIP: validate-sync-eve.sh not found"
    PHASE_RESULTS+=("sync-eve|SKIP|script not found")
    PHASE_SKIP=$((PHASE_SKIP + 1))
    return
  fi
  bash "$SCRIPTS/validate-sync-eve.sh"
  local EXIT_CODE=$?
  if [ "$EXIT_CODE" -eq 0 ]; then
    PHASE_RESULTS+=("sync-eve|PASS|IPFire→Malcolm sync-eve pipeline")
    PHASE_PASS=$((PHASE_PASS + 1))
  else
    PHASE_RESULTS+=("sync-eve|FAIL|IPFire→Malcolm sync-eve pipeline")
    PHASE_FAIL=$((PHASE_FAIL + 1))
    OVERALL_FAIL=$((OVERALL_FAIL + 1))
  fi
}

if [ -n "$SINGLE_PHASE" ]; then
  # Single-phase mode: run only the requested phase
  echo "Mode: single phase ($SINGLE_PHASE)"
  case "$SINGLE_PHASE" in
    1) run_phase 1 "$SCRIPTS/validate-phase1.sh" "Platform Foundation and Firewall" ;;
    2) run_phase 2 "$SCRIPTS/validate-phase2.sh" "Core Network Services" ;;
    3) run_phase 3 "$SCRIPTS/validate-phase3.sh" "SSH Hardening and Management Security" ;;
    4) run_phase 4 "$SCRIPTS/validate-phase4.sh" "Suricata IDS/IPS" ;;
    5) run_phase5_remote ;;
    6) run_phase 6 "$SCRIPTS/validate-phase6.sh" "System Hardening and Validation" ;;
    9) run_phase 9 "$SCRIPTS/validate-phase9.sh" "Malcolm NSM Deployment" ;;
    10) run_phase 10 "$SCRIPTS/validate-phase10.sh" "Telemetry Migration to Malcolm" ;;
    11) run_phase_skip 11 "AI Analyst retracted per ADR-E04 (data-layer / analysis-layer split)" ;;
    12) run_phase_skip 12 "validator deprecated per ADR-E04; RAG verified via validate-phase13.sh TRI-04" ;;
    13) run_phase 13 "$SCRIPTS/validate-phase13.sh" "Alert Triage & SOC Integration" ;;
    14) run_phase 14 "$SCRIPTS/validate-phase14.sh" "PCAP + Supply Chain Assurance" ;;
    tri06|TRI06|tri-06) run_tri06 ;;
    sync-eve|sync_eve|synceve) run_sync_eve ;;
    *) echo "ERROR: Unknown phase '$SINGLE_PHASE'. Valid: 1-6, 9-14, tri06, sync-eve"; exit 1 ;;
  esac
else
  # Full run: scope by host role.
  echo "Mode: full suite (host role: ${HOST_ROLE})"
  case "$HOST_ROLE" in
    ipfire)
      # v1.0 phases only — IPFire cannot currently SSH to supportTAK.
      # For v2.0 coverage, run this script again from the laptop with
      # --host laptop (or --host all if keys are later provisioned).
      run_phase 1 "$SCRIPTS/validate-phase1.sh" "Platform Foundation and Firewall"
      run_phase 2 "$SCRIPTS/validate-phase2.sh" "Core Network Services"
      run_phase 3 "$SCRIPTS/validate-phase3.sh" "SSH Hardening and Management Security"
      run_phase 4 "$SCRIPTS/validate-phase4.sh" "Suricata IDS/IPS"
      run_phase5_remote
      run_phase 6 "$SCRIPTS/validate-phase6.sh" "System Hardening and Validation"
      run_phase_skip 9 "skipped on ipfire host — run from laptop (SSH required to supportTAK)"
      run_phase_skip 10 "skipped on ipfire host — run from laptop"
      run_phase_skip 11 "AI Analyst retracted per ADR-E04"
      run_phase_skip 12 "validator deprecated per ADR-E04"
      run_phase_skip 13 "skipped on ipfire host — run from laptop"
      run_phase_skip 14 "skipped on ipfire host — run from laptop"
      PHASE_RESULTS+=("tri06|SKIP|skipped on ipfire host — run from laptop")
      PHASE_SKIP=$((PHASE_SKIP + 1))
      PHASE_RESULTS+=("sync-eve|SKIP|skipped on ipfire host — run from laptop")
      PHASE_SKIP=$((PHASE_SKIP + 1))
      ;;
    laptop)
      # v2.0 phases only — laptop cannot run IPFire-local tools.
      run_phase_skip 1 "skipped on laptop host — run on IPFire"
      run_phase_skip 2 "skipped on laptop host — run on IPFire"
      run_phase_skip 3 "skipped on laptop host — run on IPFire"
      run_phase_skip 4 "skipped on laptop host — run on IPFire"
      run_phase_skip 5 "skipped on laptop host — run on IPFire"
      run_phase_skip 6 "skipped on laptop host — run on IPFire"
      run_phase 9 "$SCRIPTS/validate-phase9.sh" "Malcolm NSM Deployment"
      run_phase 10 "$SCRIPTS/validate-phase10.sh" "Telemetry Migration to Malcolm"
      run_phase_skip 11 "AI Analyst retracted per ADR-E04"
      run_phase_skip 12 "validator deprecated per ADR-E04; RAG verified via validate-phase13.sh TRI-04"
      run_phase 13 "$SCRIPTS/validate-phase13.sh" "Alert Triage & SOC Integration"
      run_phase 14 "$SCRIPTS/validate-phase14.sh" "PCAP + Supply Chain Assurance"
      run_sync_eve
      run_tri06
      ;;
    all)
      # Full orchestration — assumes the caller has SSH to both IPFire and
      # supportTAK AND IPFire-local tool access (only possible on IPFire if
      # IPFire→supportTAK keys are provisioned). Reserved for v2.1+.
      run_phase 1 "$SCRIPTS/validate-phase1.sh" "Platform Foundation and Firewall"
      run_phase 2 "$SCRIPTS/validate-phase2.sh" "Core Network Services"
      run_phase 3 "$SCRIPTS/validate-phase3.sh" "SSH Hardening and Management Security"
      run_phase 4 "$SCRIPTS/validate-phase4.sh" "Suricata IDS/IPS"
      run_phase5_remote
      run_phase 6 "$SCRIPTS/validate-phase6.sh" "System Hardening and Validation"
      run_phase 9 "$SCRIPTS/validate-phase9.sh" "Malcolm NSM Deployment"
      run_phase 10 "$SCRIPTS/validate-phase10.sh" "Telemetry Migration to Malcolm"
      run_phase_skip 11 "AI Analyst retracted per ADR-E04"
      run_phase_skip 12 "validator deprecated per ADR-E04; RAG verified via validate-phase13.sh TRI-04"
      run_phase 13 "$SCRIPTS/validate-phase13.sh" "Alert Triage & SOC Integration"
      run_phase 14 "$SCRIPTS/validate-phase14.sh" "PCAP + Supply Chain Assurance"
      run_sync_eve
      run_tri06
      ;;
    *)
      echo "ERROR: unknown HOST_ROLE '${HOST_ROLE}'. Use --host ipfire|laptop|all"
      exit 1
      ;;
  esac
fi

# --- Summary table ---
echo ""
echo "=========================================="
echo "  VALIDATION SUITE SUMMARY"
echo "=========================================="

FAILED_PHASES=""
for RESULT in "${PHASE_RESULTS[@]}"; do
  NUM=$(echo "$RESULT" | cut -d'|' -f1)
  STATUS=$(echo "$RESULT" | cut -d'|' -f2)
  DETAIL=$(echo "$RESULT" | cut -d'|' -f3)

  # Pad phase number display
  case "$STATUS" in
    PASS) printf "  Phase %s: PASS\n" "$NUM" ;;
    FAIL) printf "  Phase %s: FAIL\n" "$NUM"
          FAILED_PHASES="${FAILED_PHASES} Phase ${NUM}" ;;
    SKIP) printf "  Phase %s: SKIP (%s)\n" "$NUM" "$DETAIL" ;;
  esac
done

echo "  ------------------------------------------"
printf "  Result: %d PASS, %d FAIL, %d SKIP\n" "$PHASE_PASS" "$PHASE_FAIL" "$PHASE_SKIP"
echo ""

if [ "$OVERALL_FAIL" -eq 0 ]; then
  if [ "$PHASE_SKIP" -gt 0 ]; then
    echo "  ALL PHASES PASS (${PHASE_SKIP} skipped)"
  else
    echo "  ALL PHASES PASS"
  fi
  echo "=========================================="
  exit 0
else
  echo "  VALIDATION FAILED — see${FAILED_PHASES} above"
  echo "=========================================="
  exit 1
fi
