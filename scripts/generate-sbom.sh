#!/bin/bash
# generate-sbom.sh — Generate SBOM and sign release artifacts (SCA-01..04)
# Usage: bash scripts/generate-sbom.sh [tag]
# Prerequisites: syft, grype, cosign v3.x installed
# See: decisions/ADR-E03-pcap-capture-assessment.md for PCAP status
# See: docs/release-process.md for full procedure

set -e

TAG="${1:-$(git describe --tags --abbrev=0 2>/dev/null || echo 'v2.0.0-dev')}"
RELEASE_DIR="releases/${TAG}"
SSH_TARGET="opsadmin@192.168.1.22"

echo "=== SBOM Generation for ${TAG} ==="
echo ""

# Check prerequisites
for cmd in syft grype cosign; do
  if ! command -v $cmd &>/dev/null; then
    echo "ERROR: $cmd is not installed. Install with:"
    echo "  syft:   curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sudo sh -s -- -b /usr/local/bin"
    echo "  grype:  curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sudo sh -s -- -b /usr/local/bin"
    echo "  cosign: download v3.x binary from https://github.com/sigstore/cosign/releases/latest"
    echo "          (required — the --bundle flag this script uses is mandatory in cosign v3)"
    exit 1
  fi
done

# Cosign version assertion — --bundle flag is mandatory in v3.x and the
# keyless Sigstore signing flow we rely on requires v3.x behavior. Guard
# against silent v2.x drift.
COSIGN_VER_RAW=$(cosign version 2>/dev/null | grep -i -E '^GitVersion|^\s*v[0-9]' | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
COSIGN_MAJOR=$(echo "${COSIGN_VER_RAW}" | cut -d. -f1)
if [ -z "${COSIGN_VER_RAW}" ] || [ -z "${COSIGN_MAJOR}" ]; then
  echo "ERROR: unable to parse cosign version from 'cosign version' output."
  echo "       (raw: $(cosign version 2>&1 | head -3))"
  exit 1
fi
if [ "${COSIGN_MAJOR}" -lt 3 ]; then
  echo "ERROR: cosign ${COSIGN_VER_RAW} found; cosign v3.x required."
  echo "       --bundle is mandatory in v3 and this script uses it."
  echo "       Download: https://github.com/sigstore/cosign/releases/latest"
  exit 1
fi
echo "[prereq] cosign ${COSIGN_VER_RAW} (v${COSIGN_MAJOR}.x) OK"
echo ""

mkdir -p "${RELEASE_DIR}"

# SCA-01: Repo SBOM
echo "[SCA-01] Generating repo SBOM..."
syft dir:. -o cyclonedx-json="${RELEASE_DIR}/sbom-repo.json" 2>&1
echo "  -> ${RELEASE_DIR}/sbom-repo.json"

# SCA-02: Deployed system SBOM
# Scope: /var/lib/dpkg (the Debian package database) rather than a full
# rootfs scan. Rationale:
#   1. The dpkg DB contains every OS-level package with CPE strings, which
#      is what grype needs for OS CVE matching (the actionable CVE signal).
#   2. Scanning "/" pulls in Docker image layers, transient files, and
#      Malcolm's 27-container cache — observed OOM at ~3.1 GB RSS on top
#      of Malcolm's ~11 GB baseline (N150 16 GB RAM, Logstash 2 GB heap,
#      OpenSearch 6 GB heap). ADR-E04 data-layer budget forbids this.
#   3. Python venvs on supportTAK are managed via system packages and are
#      captured by the dpkg scan via python3-* packages.
#   4. Per docs/release-process.md "SBOM Scope Limitations", the dual-SBOM
#      approach (repo + dpkg) provides documented coverage.
# Detect whether we're already running on supportTAK-server. If yes, scan
# the local dpkg DB directly (avoids self-loopback SSH which would need
# separate key setup). If no, SSH to the target.
echo "[SCA-02] Generating deployed system SBOM from supportTAK-server (scope: /var/lib/dpkg)..."
LOCAL_HOSTNAME=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)
LOCAL_IPS=$(hostname -I 2>/dev/null || echo "")
if [ "${LOCAL_HOSTNAME}" = "supportTAK-server" ] \
   || [ "${LOCAL_HOSTNAME}" = "supporttak-server" ] \
   || echo " ${LOCAL_IPS} " | grep -q " 192.168.1.22 "; then
  echo "  (running on supportTAK locally — skipping SSH wrapper)"
  sudo syft scan dir:/var/lib/dpkg -o cyclonedx-json > "${RELEASE_DIR}/sbom-system.json" 2>/dev/null
else
  ssh ${SSH_TARGET} "sudo syft scan dir:/var/lib/dpkg -o cyclonedx-json 2>/dev/null" > "${RELEASE_DIR}/sbom-system.json"
fi
echo "  -> ${RELEASE_DIR}/sbom-system.json"

# SCA-03: Vulnerability scan
#
# The system SBOM was generated from dir:/var/lib/dpkg (not a full rootfs
# scan) so syft could not auto-detect the distro from /etc/os-release and
# embed it in the SBOM metadata. Without an explicit distro, grype silently
# matches against a distro-agnostic feed and reports ZERO Ubuntu CVEs — a
# dangerous false negative. Detect the distro from /etc/os-release (locally
# or via SSH depending on the run location) and pass --distro explicitly.
echo "[SCA-03] Running Grype vulnerability scan..."

# Detect distro for the system scan. Prefer local /etc/os-release when
# running on supportTAK; otherwise read it over SSH.
if [ -r /etc/os-release ] && grep -q '^ID=' /etc/os-release; then
  SYS_DISTRO_ID=$(. /etc/os-release && echo "${ID}")
  SYS_DISTRO_VER=$(. /etc/os-release && echo "${VERSION_ID}")
else
  SYS_DISTRO_LINE=$(ssh ${SSH_TARGET} '. /etc/os-release && echo "${ID}:${VERSION_ID}"' 2>/dev/null)
  SYS_DISTRO_ID="${SYS_DISTRO_LINE%%:*}"
  SYS_DISTRO_VER="${SYS_DISTRO_LINE#*:}"
fi
if [ -z "${SYS_DISTRO_ID}" ] || [ -z "${SYS_DISTRO_VER}" ]; then
  echo "ERROR: could not determine system distro/version for grype --distro flag"
  echo "       grype without --distro silently misses all OS CVEs (false negative)"
  exit 1
fi
SYS_DISTRO="${SYS_DISTRO_ID}:${SYS_DISTRO_VER}"
echo "  (system scan distro: ${SYS_DISTRO})"

grype "sbom:${RELEASE_DIR}/sbom-repo.json" -o table > "${RELEASE_DIR}/grype-repo.txt" 2>&1
grype "sbom:${RELEASE_DIR}/sbom-system.json" --distro "${SYS_DISTRO}" -o table > "${RELEASE_DIR}/grype-system.txt" 2>&1
echo "  -> ${RELEASE_DIR}/grype-repo.txt"
echo "  -> ${RELEASE_DIR}/grype-system.txt"

# SCA-04: Sign with cosign
echo "[SCA-04] Signing release bundle with cosign..."
tar czf "${RELEASE_DIR}/${TAG}-bundle.tar.gz" \
  "${RELEASE_DIR}/sbom-repo.json" \
  "${RELEASE_DIR}/sbom-system.json" \
  "${RELEASE_DIR}/grype-repo.txt" \
  "${RELEASE_DIR}/grype-system.txt"

cosign sign-blob --bundle "${RELEASE_DIR}/${TAG}-bundle.cosign" \
  "${RELEASE_DIR}/${TAG}-bundle.tar.gz"

echo ""
echo "=== Release artifacts for ${TAG} ==="
ls -la "${RELEASE_DIR}/"
echo ""
echo "=== Verify signature (cosign v3 requires identity assertion) ==="
echo "cosign verify-blob --bundle ${RELEASE_DIR}/${TAG}-bundle.cosign \\"
echo "  --certificate-identity-regexp='.+@.+\\..+' \\"
echo "  --certificate-oidc-issuer-regexp='^https://.+/login/oauth\$' \\"
echo "  ${RELEASE_DIR}/${TAG}-bundle.tar.gz"
echo ""
echo "To pin to a specific signer, replace --certificate-identity-regexp with"
echo "--certificate-identity='<email>' and --certificate-oidc-issuer='<url>'"
echo "(see .planning/milestones/v2.0-MILESTONE-AUDIT.md for the pinned v2.0.0 identity)."
