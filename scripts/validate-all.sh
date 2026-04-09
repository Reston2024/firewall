#!/bin/bash
# validate-all.sh — Unified validation orchestrator for all phases
# Usage: bash /root/firewall-repo/scripts/validate-all.sh [--phase N]
# Run ON IPFire appliance (not from dev machine)
# Calls all per-phase validation scripts; SSHes to supportTAK-server for Phase 5
# Exits: 0 if no FAILs (SKIPs allowed), 1 if any phase FAILed

REPO="/root/firewall-repo"
SCRIPTS="$REPO/scripts"
SUPPORTTAK_HOST="opsadmin@192.168.1.22"

# --- Parse arguments ---
SINGLE_PHASE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --phase)
      shift
      SINGLE_PHASE="$1"
      ;;
    *)
      echo "Usage: $0 [--phase N]"
      exit 1
      ;;
  esac
  shift
done

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
    *) echo "ERROR: Unknown phase '$SINGLE_PHASE'. Valid range: 1-6"; exit 1 ;;
  esac
else
  # Full run: all 6 phases in order
  echo "Mode: full suite (all 6 phases)"
  run_phase 1 "$SCRIPTS/validate-phase1.sh" "Platform Foundation and Firewall"
  run_phase 2 "$SCRIPTS/validate-phase2.sh" "Core Network Services"
  run_phase 3 "$SCRIPTS/validate-phase3.sh" "SSH Hardening and Management Security"
  run_phase 4 "$SCRIPTS/validate-phase4.sh" "Suricata IDS/IPS"
  run_phase5_remote
  run_phase 6 "$SCRIPTS/validate-phase6.sh" "System Hardening and Validation"
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
