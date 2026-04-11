#!/bin/bash
# emit-receipt.sh — Reference execution-receipt emitter for TRI-06.
#
# Usage:
#   bash scripts/emit-receipt.sh path/to/receipt.json
#   cat receipt.json | bash scripts/emit-receipt.sh
#
# Reads a JSON document conforming to contracts/execution-receipt.schema.json,
# performs lightweight local validation of the required fields + taxonomy
# enum, then POSTs to https://192.168.1.22:9200/triage-results-YYYY.MM.DD/_doc
# using the malcolm_internal credentials.
#
# This script is the single reference emitter for the Firewall side of the
# TRI-06 "meet in the middle" contract. The desktop SOC can either:
#   (a) hand-craft one real receipt for a real alert and run this script to
#       satisfy TRI-06.4 immediately (unblock v2.0.0 release);
#   (b) build a forwarder that reads from its own store (DuckDB, SQLite,
#       local index, etc), transforms each decision into this schema, and
#       pipes the result through this script.
#
# See: docs/tri06-receipt-contract.md for the full contract.
# See: contracts/execution-receipt.schema.json for the authoritative schema.
# See: examples/receipts/*.json for reference receipt documents.

set -u

CREDS="${FIREWALL_RECEIPT_CREDS:-malcolm_internal:AzZqIn8B6AS1RuX0K8NbbzJZuYaTDARks9Tu}"
OPENSEARCH="${FIREWALL_OPENSEARCH:-https://192.168.1.22:9200}"

# Valid failure_taxonomy enum values per contracts/execution-receipt.schema.json.
VALID_TAXONOMY=(
  "applied"
  "noop_already_present"
  "validation_failed"
  "expired_rejected"
  "rolled_back"
)

# Required fields per the schema's "required" array.
REQUIRED_FIELDS=(
  "schema_version"
  "receipt_id"
  "recommendation_id"
  "case_id"
  "failure_taxonomy"
  "received_at"
  "processed_at"
  "detail"
)

usage() {
  cat >&2 <<EOF
Usage: $0 <receipt.json>
       $0            (reads from stdin)

Environment overrides:
  FIREWALL_RECEIPT_CREDS   basic-auth creds (default: malcolm_internal:...)
  FIREWALL_OPENSEARCH      OpenSearch base URL (default: https://192.168.1.22:9200)

Emits the receipt to triage-results-\$(date -u +%Y.%m.%d)/_doc and echoes the
OpenSearch response. Exits 0 on HTTP 201/200, non-zero otherwise.
EOF
  exit 2
}

# --- Parse input ---
if [ $# -eq 0 ]; then
  RECEIPT=$(cat)
elif [ $# -eq 1 ] && [ "$1" = "-h" -o "$1" = "--help" ]; then
  usage
elif [ $# -eq 1 ] && [ -f "$1" ]; then
  RECEIPT=$(cat "$1")
else
  usage
fi

if [ -z "${RECEIPT}" ]; then
  echo "ERROR: empty receipt input" >&2
  exit 1
fi

# --- Minimal local validation (not a full JSON-Schema validator) ---
# Verifies: parseable JSON (at least one '{'), required fields present,
# schema_version == "1.0.0", failure_taxonomy is an allowed enum value.
# A full schema validation lives client-side in the desktop SOC's code
# path; this script is a friendly safety belt, not a replacement.
if ! echo "${RECEIPT}" | head -c 1 | grep -q '{'; then
  echo "ERROR: input does not look like JSON (must start with '{')" >&2
  exit 1
fi

for field in "${REQUIRED_FIELDS[@]}"; do
  if ! echo "${RECEIPT}" | grep -q "\"${field}\""; then
    echo "ERROR: required field missing: ${field}" >&2
    echo "       see contracts/execution-receipt.schema.json" >&2
    exit 1
  fi
done

# Reject the placeholder strings used in examples/receipts/*.json. Catching
# this at emit time prevents accidental pollution of triage-results-* with
# documents that reference REPLACE_WITH_FRESH_UUID as a key.
if echo "${RECEIPT}" | grep -q 'REPLACE_WITH_FRESH_UUID'; then
  echo "ERROR: receipt contains 'REPLACE_WITH_FRESH_UUID' placeholder." >&2
  echo "       Generate a real UUID v4 and substitute. See examples/receipts/README.md." >&2
  exit 1
fi

SCHEMA_VER=$(echo "${RECEIPT}" | grep -oE '"schema_version"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"[[:space:]]*$/\1/')
if [ "${SCHEMA_VER}" != "1.0.0" ]; then
  echo "ERROR: schema_version must be \"1.0.0\" (got \"${SCHEMA_VER}\")" >&2
  exit 1
fi

# Minimal UUID v4 sanity check for the three required UUID fields.
UUID_RE='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
for uuid_field in receipt_id recommendation_id case_id; do
  VAL=$(echo "${RECEIPT}" | grep -oE "\"${uuid_field}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed -E 's/.*"([^"]*)"[[:space:]]*$/\1/')
  if [ -z "${VAL}" ] || ! echo "${VAL}" | grep -qE "${UUID_RE}"; then
    echo "ERROR: ${uuid_field}='${VAL}' is not a valid UUID v4" >&2
    echo "       schema requires RFC 4122 UUID v4 strings" >&2
    exit 1
  fi
done

TAXONOMY=$(echo "${RECEIPT}" | grep -oE '"failure_taxonomy"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"[[:space:]]*$/\1/')
TAXONOMY_OK=0
for valid in "${VALID_TAXONOMY[@]}"; do
  if [ "${TAXONOMY}" = "${valid}" ]; then
    TAXONOMY_OK=1
    break
  fi
done
if [ "${TAXONOMY_OK}" -ne 1 ]; then
  echo "ERROR: failure_taxonomy '${TAXONOMY}' is not one of: ${VALID_TAXONOMY[*]}" >&2
  exit 1
fi

# --- POST to OpenSearch ---
DATE=$(date -u +%Y.%m.%d)
INDEX="triage-results-${DATE}"
URL="${OPENSEARCH}/${INDEX}/_doc"

echo "[emit-receipt] target: ${URL}" >&2
echo "[emit-receipt] schema_version=${SCHEMA_VER} failure_taxonomy=${TAXONOMY}" >&2

TMPFILE=$(mktemp "${TMPDIR:-/tmp}/receipt.XXXXXX.json")
trap 'rm -f "${TMPFILE}"' EXIT
printf '%s' "${RECEIPT}" > "${TMPFILE}"

HTTP_CODE=$(curl -sk -o /tmp/receipt-emit-response.json -w '%{http_code}' \
  --max-time 15 \
  -u "${CREDS}" \
  -H "Content-Type: application/json" \
  -X POST "${URL}" \
  --data-binary "@${TMPFILE}")

RESP=$(cat /tmp/receipt-emit-response.json 2>/dev/null)
rm -f /tmp/receipt-emit-response.json

echo "[emit-receipt] HTTP ${HTTP_CODE}" >&2
echo "${RESP}"

case "${HTTP_CODE}" in
  200|201)
    echo "[emit-receipt] OK" >&2
    exit 0
    ;;
  *)
    echo "[emit-receipt] write failed (HTTP ${HTTP_CODE})" >&2
    exit 1
    ;;
esac
