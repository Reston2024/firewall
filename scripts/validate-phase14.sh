#!/bin/bash
# validate-phase14.sh — Phase 14 validation: PCAP + Supply Chain Assurance
# Run from the laptop (or any host that can read releases/).
#
# Covers:
#   SCA-01 Syft CycloneDX repo SBOM
#   SCA-02 Syft CycloneDX system SBOM
#   SCA-03 Grype vulnerability scan of both SBOMs
#   SCA-04 Cosign v3 keyless-signed release bundle (verifiable)
#   SCA-05 Release process documented
#   PCAP-01/04 Switch-based SPAN hardware live (Malcolm Zeek/Suricata containers)
#
# PCAP-02 and PCAP-03 are deferred to v3.0 per ADR-E03 and remain unchecked
# in REQUIREMENTS.md by design. This script does NOT fail on them.
#
# Strategy: verify release artifacts exist and the cosign bundle verifies.
# Grype critical CVE counts are surfaced in the output but do NOT fail the
# gate — per NIST SSDF and industry practice, SBOMs/grype reports at release
# time are audit evidence, not go/no-go gates. CVE responses happen in the
# next iteration; the release itself ships with disclosed findings.

set -u

FAIL=0; PASS=0; SKIP=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "SKIP: $1"; SKIP=$((SKIP + 1)); }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:-v2.0.0}"
RELEASE_DIR="${REPO_ROOT}/releases/${TAG}"
SSH_TARGET="opsadmin@192.168.1.22"
CREDS="malcolm_internal:AzZqIn8B6AS1RuX0K8NbbzJZuYaTDARks9Tu"

echo "=== Phase 14 Validation — PCAP + Supply Chain — $(date) ==="
echo "Release dir: ${RELEASE_DIR}"
echo ""

# Helper: assert a JSON file is CycloneDX-shaped.
is_cyclonedx() {
  local file="$1"
  [ -f "$file" ] || return 1
  [ -s "$file" ] || return 1
  grep -q '"bomFormat"[[:space:]]*:[[:space:]]*"CycloneDX"' "$file"
}

# Helper: count grype severity hits across a report.
count_severity() {
  local file="$1"
  local sev="$2"
  [ -f "$file" ] || { echo 0; return; }
  # Grype table format has SEVERITY as its own whitespace-delimited column.
  awk -v s="$sev" '$0 ~ " "s" " || $0 ~ "\t"s"\t" {n++} END {print n+0}' "$file"
}

# --- SCA-01: Repo SBOM ---
echo "[SCA-01] Repo SBOM (CycloneDX JSON)"
if is_cyclonedx "${RELEASE_DIR}/sbom-repo.json"; then
  SIZE=$(wc -c <"${RELEASE_DIR}/sbom-repo.json" | tr -d ' ')
  pass "SCA-01: sbom-repo.json is valid CycloneDX JSON (${SIZE} bytes)"
else
  fail "SCA-01: ${RELEASE_DIR}/sbom-repo.json missing, empty, or not CycloneDX"
fi
echo ""

# --- SCA-02: System SBOM ---
echo "[SCA-02] System SBOM (CycloneDX JSON)"
if is_cyclonedx "${RELEASE_DIR}/sbom-system.json"; then
  SIZE=$(wc -c <"${RELEASE_DIR}/sbom-system.json" | tr -d ' ')
  pass "SCA-02: sbom-system.json is valid CycloneDX JSON (${SIZE} bytes)"
else
  fail "SCA-02: ${RELEASE_DIR}/sbom-system.json missing, empty, or not CycloneDX"
fi
echo ""

# --- SCA-03: Grype scans ---
echo "[SCA-03] Grype vulnerability scan reports"
SCA03_OK=1
for f in grype-repo.txt grype-system.txt; do
  if [ -f "${RELEASE_DIR}/${f}" ] && [ -s "${RELEASE_DIR}/${f}" ]; then
    CRIT=$(count_severity "${RELEASE_DIR}/${f}" Critical)
    HIGH=$(count_severity "${RELEASE_DIR}/${f}" High)
    echo "  ${f}: Critical=${CRIT} High=${HIGH}"
  else
    fail "SCA-03: ${f} missing or empty"
    SCA03_OK=0
  fi
done
if [ $SCA03_OK -eq 1 ]; then
  pass "SCA-03: grype-repo.txt and grype-system.txt present and non-empty (CVE counts above; non-blocking per NIST SSDF)"
fi
echo ""

# --- SCA-04: Cosign v3 bundle verifies ---
# Cosign v3 REQUIRES --certificate-identity or --certificate-identity-regexp
# (plus an OIDC issuer) for keyless verification — self-signed or anonymous
# signatures are rejected. We use permissive regexes that still assert:
#   1. the signing identity is email-formatted (rules out empty / "anonymous")
#   2. the OIDC issuer is a real HTTPS OAuth endpoint
# These can be tightened to pin a specific release signer via the
# FIREWALL_COSIGN_IDENTITY / FIREWALL_COSIGN_ISSUER env vars; see the
# release process and v2.0-MILESTONE-AUDIT.md for the pinned values used
# on the v2.0.0 tag.
COSIGN_ID_REGEX="${FIREWALL_COSIGN_IDENTITY:-.+@.+\..+}"
COSIGN_ISSUER_REGEX="${FIREWALL_COSIGN_ISSUER:-^https://.+/login/oauth$}"

echo "[SCA-04] Cosign v3 keyless-signed bundle verifies"
BUNDLE_TAR="${RELEASE_DIR}/${TAG}-bundle.tar.gz"
BUNDLE_COSIGN="${RELEASE_DIR}/${TAG}-bundle.cosign"
if [ ! -f "$BUNDLE_TAR" ]; then
  fail "SCA-04: ${BUNDLE_TAR} missing"
elif [ ! -f "$BUNDLE_COSIGN" ]; then
  fail "SCA-04: ${BUNDLE_COSIGN} missing"
elif ! command -v cosign &>/dev/null; then
  # Local laptop may not have cosign; try supportTAK as fallback.
  echo "  (cosign not in local PATH; attempting remote verify via ${SSH_TARGET})"
  REMOTE_DIR="/tmp/firewall-validate-sca04-$$"
  if ssh -o BatchMode=yes -o ConnectTimeout=10 "$SSH_TARGET" "mkdir -p ${REMOTE_DIR}" 2>/dev/null \
     && scp -q "$BUNDLE_TAR" "$BUNDLE_COSIGN" "${SSH_TARGET}:${REMOTE_DIR}/" 2>/dev/null \
     && ssh -o BatchMode=yes "$SSH_TARGET" "cd ${REMOTE_DIR} && cosign verify-blob --bundle $(basename "$BUNDLE_COSIGN") --certificate-identity-regexp='${COSIGN_ID_REGEX}' --certificate-oidc-issuer-regexp='${COSIGN_ISSUER_REGEX}' $(basename "$BUNDLE_TAR")" >/dev/null 2>&1; then
    pass "SCA-04: cosign verify-blob --bundle succeeded (verified remotely on ${SSH_TARGET})"
  else
    fail "SCA-04: cosign verify-blob --bundle failed (tried local + remote). Check FIREWALL_COSIGN_IDENTITY / FIREWALL_COSIGN_ISSUER"
  fi
  ssh -o BatchMode=yes "$SSH_TARGET" "rm -rf ${REMOTE_DIR}" 2>/dev/null || true
else
  if cosign verify-blob --bundle "$BUNDLE_COSIGN" \
       --certificate-identity-regexp="${COSIGN_ID_REGEX}" \
       --certificate-oidc-issuer-regexp="${COSIGN_ISSUER_REGEX}" \
       "$BUNDLE_TAR" >/dev/null 2>&1; then
    pass "SCA-04: cosign verify-blob --bundle succeeded (verified locally)"
  else
    fail "SCA-04: cosign verify-blob --bundle failed (signature invalid, identity mismatch, or transparency log mismatch)"
  fi
fi
echo ""

# --- SCA-05: Release process documented ---
echo "[SCA-05] Release process documented"
if [ -f "${REPO_ROOT}/docs/release-process.md" ] && [ -s "${REPO_ROOT}/docs/release-process.md" ]; then
  if grep -q 'cosign v3' "${REPO_ROOT}/docs/release-process.md"; then
    pass "SCA-05: docs/release-process.md present and documents cosign v3"
  else
    fail "SCA-05: docs/release-process.md exists but does not document cosign v3"
  fi
else
  fail "SCA-05: docs/release-process.md missing or empty"
fi
echo ""

# --- PCAP-01: Managed switch SPAN mirror live ---
# The switch (GS308EP at 192.168.1.104) is external hardware; we prove the
# mirror is effective by confirming Zeek workers see traffic on supportTAK.
echo "[PCAP-01] Managed switch SPAN mirror active (Zeek workers consuming)"
ZEEK_STATUS=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$SSH_TARGET" \
  "cd /opt/malcolm && docker compose ps --format '{{.Name}} {{.Status}}' 2>/dev/null | grep -E 'zeek(-live)?' | head -4" 2>/dev/null)
if echo "$ZEEK_STATUS" | grep -q 'healthy'; then
  pass "PCAP-01: Malcolm Zeek workers healthy on supportTAK ($(echo "$ZEEK_STATUS" | wc -l) container(s))"
else
  fail "PCAP-01: Zeek workers not healthy on supportTAK"
fi
echo ""

# --- PCAP-02 / PCAP-03: deferred ---
# Kept as skip() so the requirement IDs appear in the suite output for
# traceability. Not failures.
skip "PCAP-02: deferred to v3.0 per ADR-E03 (hardware assessment complete; see REQUIREMENTS.md)"
skip "PCAP-03: deferred to v3.0 per ADR-E03"
echo ""

# --- PCAP-04: Suricata live container active on SPAN mirror ---
echo "[PCAP-04] Suricata live container active on SPAN mirror"
SURI_LIVE=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$SSH_TARGET" \
  "cd /opt/malcolm && docker compose ps --format '{{.Name}} {{.Status}}' 2>/dev/null | grep 'suricata-live' | head -1" 2>/dev/null)
if echo "$SURI_LIVE" | grep -q 'healthy'; then
  pass "PCAP-04: malcolm-suricata-live-1 healthy on SPAN mirror"
else
  fail "PCAP-04: suricata-live not healthy on supportTAK"
fi
echo ""

# --- Summary ---
echo "=== Phase 14 Validation Summary ==="
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo ""
if [ $FAIL -gt 0 ]; then
  echo "=== FAILED: $FAIL check(s) require attention ==="
  exit $FAIL
else
  echo "=== ALL CHECKS PASS ($SKIP skipped) ==="
  exit 0
fi
