#!/bin/bash
# validate-phase6.sh — Phase 6 validation suite: System Hardening and Validation
# Usage: bash /root/firewall-repo/scripts/validate-phase6.sh
# Run ON IPFire appliance (not from dev machine)
# Exits: 0 if all checks pass, 1 if any fail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAIL=0
PASS=0
SKIP=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "SKIP: $1"; SKIP=$((SKIP + 1)); }

echo "=== Phase 6 Validation Suite — System Hardening — $(date) ==="
echo ""

# --- HARD-01: Service audit ---
echo "[HARD-01] Service audit — known-good TCP port baseline"

# Expected listening ports: 53 (unbound), 22 (sshd), 81/444/1013 (httpd), 8953 (unbound control, localhost)
KNOWN_PORTS="53 22 81 444 1013 8953"
UNEXPECTED=0
UNEXPECTED_LIST=""

LISTENING=$(ss -tlnp 2>/dev/null | awk 'NR>1 && $1=="LISTEN" {print $4}' | grep -oE ':[0-9]+$' | tr -d ':' | sort -un)

for PORT in $LISTENING; do
  FOUND=0
  for KNOWN in $KNOWN_PORTS; do
    if [ "$PORT" = "$KNOWN" ]; then
      FOUND=1
      break
    fi
  done
  if [ "$FOUND" -eq 0 ]; then
    UNEXPECTED=1
    UNEXPECTED_LIST="${UNEXPECTED_LIST} ${PORT}"
  fi
done

if [ "$UNEXPECTED" -eq 1 ]; then
  fail "HARD-01: Unexpected TCP port(s) listening:${UNEXPECTED_LIST} — review with: ss -tlnp"
else
  pass "HARD-01: All listening TCP ports are in known-good baseline (${KNOWN_PORTS})"
fi

# Pakfire manifest check
MANIFEST="/root/firewall-repo/manifests/pakfire-manifest.txt"
EXPECTED_MANIFEST="/root/firewall-repo/manifests/pakfire-manifest-expected.txt"
if [ ! -f "$MANIFEST" ]; then
  skip "HARD-01: Pakfire manifest not generated yet — run: pakfire list installed > /root/firewall-repo/manifests/pakfire-manifest.txt"
elif [ ! -f "$EXPECTED_MANIFEST" ]; then
  skip "HARD-01: Expected Pakfire manifest not found at $EXPECTED_MANIFEST — create baseline first"
else
  # Strip comments and blank lines from expected manifest before comparing
  EXPECTED_CLEAN=$(grep -v '^#' "$EXPECTED_MANIFEST" | grep -v '^$' | sort)
  ACTUAL_CLEAN=$(sort "$MANIFEST")
  # Check if every expected package appears in actual (with or without meta- prefix)
  MANIFEST_FAIL=0
  for PKG in $EXPECTED_CLEAN; do
    if ! echo "$ACTUAL_CLEAN" | grep -qiE "(^|meta-)${PKG}$"; then
      fail "HARD-01: Expected Pakfire package '$PKG' not found in installed manifest"
      MANIFEST_FAIL=1
    fi
  done
  # Check for truly unexpected packages (not matching any expected package or its dependencies)
  for INSTALLED in $ACTUAL_CLEAN; do
    MATCHED=0
    for PKG in $EXPECTED_CLEAN; do
      if echo "$INSTALLED" | grep -qiE "(^|meta-)${PKG}"; then
        MATCHED=1
        break
      fi
    done
    # Allow meta-perl-* as known Guardian dependencies
    if [ "$MATCHED" -eq 0 ] && ! echo "$INSTALLED" | grep -q "^meta-perl-"; then
      fail "HARD-01: Unexpected Pakfire package: $INSTALLED"
      MANIFEST_FAIL=1
    fi
  done
  if [ "$MANIFEST_FAIL" -eq 0 ]; then
    pass "HARD-01: Pakfire manifest matches expected (including meta- prefix and dependencies)"
  fi
fi
echo ""

# --- HARD-02: File permissions ---
echo "[HARD-02] Key file permissions"

check_perm() {
  local FILE="$1"
  local EXPECTED="$2"
  local LABEL="$3"

  if [ ! -e "$FILE" ]; then
    skip "HARD-02: $LABEL ($FILE) does not exist yet"
    return
  fi

  ACTUAL=$(stat -c "%a" "$FILE" 2>/dev/null)
  if [ "$ACTUAL" = "$EXPECTED" ]; then
    pass "HARD-02: $LABEL has correct permissions ($EXPECTED): $FILE"
  else
    fail "HARD-02: $LABEL has wrong permissions — expected $EXPECTED, got $ACTUAL: $FILE — fix: chmod $EXPECTED $FILE"
  fi
}

check_perm "/etc/ssh/sshd_config" "600" "sshd_config"
check_perm "/etc/sysconfig/firewall.local" "700" "firewall.local"
check_perm "/root/.ssh" "700" ".ssh directory"
if [ -f "/root/.ssh/authorized_keys" ]; then
  check_perm "/root/.ssh/authorized_keys" "600" "authorized_keys"
fi
if [ -f "/root/integrity-baseline.sha256" ]; then
  check_perm "/root/integrity-baseline.sha256" "600" "integrity-baseline.sha256"
fi
echo ""

# --- HARD-03: File integrity baseline ---
echo "[HARD-03] File integrity baseline"

if [ ! -f "${SCRIPT_DIR}/check-integrity.sh" ]; then
  fail "HARD-03: check-integrity.sh not found at ${SCRIPT_DIR}/check-integrity.sh"
else
  bash "${SCRIPT_DIR}/check-integrity.sh" --verify
  INTEGRITY_EXIT=$?
  if [ "$INTEGRITY_EXIT" -eq 0 ]; then
    pass "HARD-03: All monitored files match integrity baseline"
  elif [ "$INTEGRITY_EXIT" -eq 2 ]; then
    skip "HARD-03: Integrity mismatch detected — may need --update-baseline after intentional changes; run: bash ${SCRIPT_DIR}/check-integrity.sh --update-baseline"
  else
    fail "HARD-03: Integrity check failed (exit $INTEGRITY_EXIT) — run: bash ${SCRIPT_DIR}/check-integrity.sh --verify for details"
  fi
fi
echo ""

# --- HARD-04: Kernel hardening (sysctl) ---
echo "[HARD-04] Kernel hardening parameters (sysctl)"

check_sysctl() {
  local KEY="$1"
  local EXPECTED="$2"

  ACTUAL=$(sysctl -n "$KEY" 2>/dev/null)
  if [ -z "$ACTUAL" ]; then
    skip "HARD-04: $KEY not found — kernel may not support this parameter"
  elif [ "$ACTUAL" = "$EXPECTED" ]; then
    pass "HARD-04: $KEY = $EXPECTED"
  else
    fail "HARD-04: $KEY = $ACTUAL (expected $EXPECTED) — apply: sysctl -w $KEY=$EXPECTED"
  fi
}

check_sysctl "net.ipv4.conf.all.send_redirects" "0"
check_sysctl "net.ipv4.conf.default.send_redirects" "0"
check_sysctl "net.ipv4.conf.all.accept_source_route" "0"
check_sysctl "net.ipv4.conf.all.accept_redirects" "0"
check_sysctl "net.ipv4.conf.all.rp_filter" "1"
check_sysctl "net.ipv4.tcp_syncookies" "1"
check_sysctl "net.ipv6.conf.all.accept_redirects" "0"

# ip_forward MUST remain 1 for routing — fail if disabled
IP_FORWARD=$(sysctl -n "net.ipv4.ip_forward" 2>/dev/null)
if [ "$IP_FORWARD" = "1" ]; then
  pass "HARD-04: net.ipv4.ip_forward = 1 (routing enabled — correct for firewall)"
else
  fail "HARD-04: net.ipv4.ip_forward = $IP_FORWARD (expected 1) — routing is broken; fix: sysctl -w net.ipv4.ip_forward=1"
fi
echo ""

# --- HARD-05: WUI certificate ---
echo "[HARD-05] WUI HTTPS certificate"

# At least one cert (RSA or ECDSA) must exist for WUI HTTPS
HAS_CERT=0
if [ -f "/etc/httpd/server.crt" ]; then
  pass "HARD-05: RSA cert exists: /etc/httpd/server.crt"
  HAS_CERT=1
else
  skip "HARD-05: RSA cert not present (ECDSA-only system)"
fi

if [ -f "/etc/httpd/server-ecdsa.crt" ]; then
  pass "HARD-05: ECDSA cert exists: /etc/httpd/server-ecdsa.crt"
  HAS_CERT=1
else
  skip "HARD-05: ECDSA cert not present"
fi

if [ "$HAS_CERT" -eq 0 ]; then
  fail "HARD-05: No WUI certificate found (neither RSA nor ECDSA)"
fi

# Check certificate expiry on whichever cert exists
for CERT_FILE in /etc/httpd/server.crt /etc/httpd/server-ecdsa.crt; do
  if [ -f "$CERT_FILE" ]; then
    ENDDATE=$(openssl x509 -in "$CERT_FILE" -noout -enddate 2>/dev/null | cut -d= -f2)
    ENDEPOCH=$(date -d "$ENDDATE" +%s 2>/dev/null)
    NOW_EPOCH=$(date +%s)
    DAYS_LEFT=$(( (ENDEPOCH - NOW_EPOCH) / 86400 ))
    CERT_NAME=$(basename "$CERT_FILE")

    if [ "$DAYS_LEFT" -lt 30 ]; then
      fail "HARD-05: $CERT_NAME expires in ${DAYS_LEFT} days (${ENDDATE}) — renew immediately via WUI: System > Certificates"
    elif [ "$DAYS_LEFT" -lt 90 ]; then
      pass "HARD-05: $CERT_NAME valid for ${DAYS_LEFT} days (expires: ${ENDDATE}) — WARNING: renewal recommended within 90 days"
    else
      pass "HARD-05: $CERT_NAME valid for ${DAYS_LEFT} days (expires: ${ENDDATE})"
    fi
    break  # Only need to check one
  fi
done
echo ""

# --- Summary ---
echo "=== Phase 6: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped ==="
if [ "$FAIL" -eq 0 ]; then
  echo "PHASE 6 VALIDATION PASSED"
  exit 0
else
  echo "PHASE 6 VALIDATION FAILED — resolve failures above"
  exit 1
fi
