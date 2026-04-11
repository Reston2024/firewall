# Execution Receipt Examples

Reference JSON documents for the TRI-06 contract between the desktop SOC
(local-ai-soc) and the Firewall side (supportTAK OpenSearch).

- Schema: [`../../contracts/execution-receipt.schema.json`](../../contracts/execution-receipt.schema.json)
- Contract: [`../../docs/tri06-receipt-contract.md`](../../docs/tri06-receipt-contract.md)
- Emitter: [`../../scripts/emit-receipt.sh`](../../scripts/emit-receipt.sh)
- Validator: [`../../scripts/validate-tri06.sh`](../../scripts/validate-tri06.sh)

Each file is a complete, schema-conformant example of one `failure_taxonomy`
value from ADR-E01. To use one as a quick TRI-06 smoke test:

```bash
# Generate a fresh receipt_id so the example is unique per run.
# Linux / macOS:  uuidgen
# Git-bash Windows: powershell.exe -Command [guid]::NewGuid().ToString()
NEW_ID=$(uuidgen 2>/dev/null || powershell.exe -Command "[guid]::NewGuid().ToString()" | tr -d '\r')

# Replace the placeholder receipt_id and emit.
sed "s/REPLACE_WITH_FRESH_UUID/${NEW_ID}/" examples/receipts/applied.json \
  | bash scripts/emit-receipt.sh

# Verify TRI-06.4 now PASSes:
bash scripts/validate-tri06.sh
```

The examples intentionally use placeholder UUIDs (`REPLACE_WITH_FRESH_UUID`,
`11111111-...`, etc) so nobody accidentally pastes the same receipt twice;
any real-world emitter must generate fresh UUIDs per recommendation.

## Files

| File | Taxonomy | Purpose |
|---|---|---|
| `applied.json` | `applied` | Rule was applied; `firewall_rule_id` is required and populated. |
| `noop_already_present.json` | `noop_already_present` | Rule already existed; `firewall_rule_id` echoes the existing rule. |
| `validation_failed.json` | `validation_failed` | Pre-apply check failed; `detail` explains which check and why. |
| `expired_rejected.json` | `expired_rejected` | `expires_at` was >60 s in the past at receipt time. |
| `rolled_back.json` | `rolled_back` | Rule was applied, post-apply validation failed, rule removed. `detail` records the failure mode. |

## Field notes

- `schema_version` MUST be the string `"1.0.0"`. It's a const per the schema
  and the discriminator `validate-tri06.sh` uses to find receipts.
- `receipt_id`, `recommendation_id`, `case_id` MUST be valid UUID v4 strings.
- `received_at` and `processed_at` MUST be ISO-8601 UTC (e.g., `2026-04-10T22:15:00.000Z`).
  Use the firewall's own system clock when emitting from the executor.
- `detail` is REQUIRED and MUST be non-empty for any taxonomy other than
  `applied`. For `applied` an empty string is allowed.
- `firewall_rule_id` is REQUIRED for `applied` and `noop_already_present`;
  must be omitted or empty for the other three.
