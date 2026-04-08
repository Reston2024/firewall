#!/bin/bash
# generate-sbom.sh — Generate SBOM and sign release artifacts
# Usage: bash scripts/generate-sbom.sh [tag]
# Prerequisites: syft, grype, cosign installed
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
    echo "  syft:   curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin"
    echo "  grype:  curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin"
    echo "  cosign: go install github.com/sigstore/cosign/v2/cmd/cosign@latest"
    exit 1
  fi
done

mkdir -p "${RELEASE_DIR}"

# SCA-01: Repo SBOM
echo "[SCA-01] Generating repo SBOM..."
syft dir:. -o cyclonedx-json="${RELEASE_DIR}/sbom-repo.json" 2>&1
echo "  -> ${RELEASE_DIR}/sbom-repo.json"

# SCA-02: Deployed system SBOM (remote)
echo "[SCA-02] Generating deployed system SBOM from supportTAK-server..."
ssh ${SSH_TARGET} "sudo syft packages / -o cyclonedx-json 2>/dev/null" > "${RELEASE_DIR}/sbom-system.json"
echo "  -> ${RELEASE_DIR}/sbom-system.json"

# SCA-03: Vulnerability scan
echo "[SCA-03] Running Grype vulnerability scan..."
grype "sbom:${RELEASE_DIR}/sbom-repo.json" -o table > "${RELEASE_DIR}/grype-repo.txt" 2>&1
grype "sbom:${RELEASE_DIR}/sbom-system.json" -o table > "${RELEASE_DIR}/grype-system.txt" 2>&1
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
echo "=== Verify signature ==="
echo "cosign verify-blob --bundle ${RELEASE_DIR}/${TAG}-bundle.cosign ${RELEASE_DIR}/${TAG}-bundle.tar.gz"
