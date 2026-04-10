# TRI-06 Receipt Contract — Desktop SOC ↔ supportTAK

**Status:** Active  •  **Owner:** Firewall repo  •  **Consumers:** Desktop SOC (local-ai-soc)
**Governed by:** ADR-E01 (failure taxonomy), ADR-E04 (data-layer / analysis-layer split)
**Schema:** [`contracts/execution-receipt.schema.json`](../contracts/execution-receipt.schema.json)
**Gate:** [`scripts/validate-tri06.sh`](../scripts/validate-tri06.sh)

---

## Purpose

This is the "meet in the middle like the railroad" contract between the two repos.
The desktop SOC runs the AI analysis pipeline (alert → RAG → qwen3:14b → recommendation →
executor gate). When the executor gate finishes processing a recommendation, it emits
exactly one **execution receipt** into the supportTAK OpenSearch `triage-results-*`
index. `validate-tri06.sh` on the Firewall side detects that receipt and closes TRI-06.

Neither repo owns the schema unilaterally. The canonical schema lives here
(firewall repo) because the firewall/supportTAK side hosts the retention policy, index
template, and audit trail. The desktop SOC **reads** the schema and **emits** conforming
documents. The schema is versioned (`schema_version: "1.0.0"`) so either side can evolve
without breaking the other.

---

## What the Firewall side guarantees

| Guarantee | Where it lives |
|---|---|
| OpenSearch reachable over TLS at `https://192.168.1.22:9200` | supportTAK, Malcolm nginx-proxy |
| HTTP basic auth credentials `malcolm_internal:<token>` | supportTAK, Malcolm htadmin |
| Index template `triage-results-template` bound to `triage-results-*` | Malcolm OpenSearch |
| ISM retention policy `malcolm-retention` covering `triage-results-*` (30-day TTL) | Malcolm OpenSearch |
| Index auto-created on first write via the template | OpenSearch default behaviour |
| Receipts are immutable once written (no updates from our side) | ADR-E01 |
| TRI-06 closes as soon as one schema-valid receipt is indexed | `scripts/validate-tri06.sh` |

---

## What the Desktop SOC must do

| Requirement | Detail |
|---|---|
| Emit exactly one receipt per processed recommendation | ADR-E01: "Every artifact gets exactly one receipt. No auto-retry." |
| Receipt conforms to `contracts/execution-receipt.schema.json` v1.0.0 | Schema is the authoritative shape |
| Write target: `POST https://192.168.1.22:9200/triage-results-YYYY.MM.DD/_doc` | UTC date in the index suffix; auto-creates the daily index |
| Authentication: HTTP basic `malcolm_internal:<token>` | Same credentials as the read path |
| TLS: `-k` / `verify=False` acceptable for Malcolm nginx-proxy | Internal CA per ADR-E04 data-layer trust boundary |
| `Content-Type: application/json` | Required by OpenSearch |
| `schema_version` must be the string `"1.0.0"` | Discriminator used by `validate-tri06.sh` to find receipts vs. other docs |
| `failure_taxonomy` must be one of the 5 enum values below | ADR-E01 taxonomy is mutually exclusive |
| `receipt_id`, `recommendation_id`, `case_id` must be UUID v4 strings | Audit trail linkage |
| `received_at` and `processed_at` must be ISO-8601 UTC strings | Firewall-side clock, not dispatch clock |

---

## The 5 failure_taxonomy values (ADR-E01)

| Value | When | Required sibling fields |
|---|---|---|
| `applied` | Rule applied successfully; post-apply validation passed | `firewall_rule_id` (non-empty, new rule ID) |
| `noop_already_present` | Rule already exists; no change made | `firewall_rule_id` (non-empty, existing rule ID) |
| `validation_failed` | Pre-apply schema/param failure; never mutated state | `detail` (non-empty, describe which check failed) |
| `expired_rejected` | `expires_at` > 60 s past the firewall's clock | `detail` (non-empty, record clock delta) |
| `rolled_back` | Rule applied, post-apply validation failed, rule removed | `detail` (non-empty, record: which check failed, expected vs. observed, whether rollback itself succeeded) |

The schema's `allOf` clauses enforce these conditional requirements — if the desktop SOC
serializes a document that violates them, OpenSearch will accept the write but
`validate-tri06.sh` will flag it as a schema violation.

---

## Index mapping — important note on dynamic fields

The `triage-results-template` was originally authored for *triage recommendation*
documents (20 typed fields: `severity`, `attack_technique`, `rule_name`, `analyst_approved`,
`recommendation_id`, `case_id`, `ai_summary`, `src_ip`, `dst_ip`, `triaged_at`, etc.). It
does **not** currently contain explicit mappings for the 9 *execution receipt* fields
(`schema_version`, `receipt_id`, `failure_taxonomy`, `received_at`, `processed_at`,
`detail`, `firewall_rule_id`).

**This is intentional and correct** for v2.0:

- OpenSearch dynamic mapping (the default) will auto-map receipt fields on first write.
- ISO-8601 strings in `received_at` / `processed_at` will be detected as `date`.
- String fields will auto-map as `text` with a `.keyword` subfield.
- `validate-tri06.sh` queries by `term: schema_version "1.0.0"`, which works on the
  auto-created `schema_version.keyword` field.

**Future work (v2.1 or later):** Extend the template to declare receipt fields
explicitly, matching the typing conventions of the existing 20 fields. This is
tracked as tech debt, not a v2.0 blocker. See `.planning/milestones/v2.0-MILESTONE-AUDIT.md`.

---

## Reference receipt (passes schema + is detected by `validate-tri06.sh`)

```json
{
  "schema_version": "1.0.0",
  "receipt_id": "a1b2c3d4-e5f6-4789-8abc-def012345678",
  "recommendation_id": "11111111-2222-4333-8444-555555555555",
  "case_id": "66666666-7777-4888-8999-aaaaaaaaaaaa",
  "failure_taxonomy": "applied",
  "received_at": "2026-04-10T22:15:00.000Z",
  "processed_at": "2026-04-10T22:15:03.412Z",
  "detail": "",
  "firewall_rule_id": "FW-2026-04-10-00042"
}
```

**Write command (reference):**

```bash
DATE=$(date -u +%Y.%m.%d)
curl -sk -u "malcolm_internal:<TOKEN>" \
  -H "Content-Type: application/json" \
  -X POST "https://192.168.1.22:9200/triage-results-${DATE}/_doc" \
  -d @receipt.json
```

Expected response: HTTP 201 with a body containing `"result": "created"`.

---

## E2E test procedure (the railroad meeting point)

The procedure for closing TRI-06 is fixed. Both sides must follow it:

1. **Firewall side (out of your scope, already done):**
   - `validate-tri06.sh` shows `TRI-06.1 PASS`, `TRI-06.2 PASS`,
     `TRI-06.3 SKIP` or `PASS`, `TRI-06.4 SKIP` (waiting).
2. **Desktop SOC side (your work):**
   - Trigger a Suricata alert: `ssh root@192.168.1.1 "curl -A 'BlackSun' http://testmev.com/"`.
   - Wait ≤ 90 s for the alert to land in `arkime_sessions3-*` (Malcolm SCP cron).
   - Pull the alert, build a recommendation artifact (validated against
     your `contracts/recommendation.schema.json`).
   - Run the recommendation through the 6-gate executor (ADR-E01 G1–G6).
   - Emit a receipt conforming to *this* schema to `triage-results-YYYY.MM.DD`.
3. **Firewall side confirmation:**
   - Rerun `bash scripts/validate-tri06.sh`.
   - Expected: `TRI-06.4 PASS` with your `receipt_id`, `failure_taxonomy`, and
     `recommendation_id` echoed in the PASS line.

If step 3 does not PASS the first time, `validate-tri06.sh` will report either
(a) a malformed receipt with the specific field that violated the contract, or
(b) `SKIP` meaning no matching document was found (wrong index prefix, wrong
`schema_version` value, or the receipt was written to a non-`triage-results-*`
index). Iterate on your side; the Firewall side does not move the goal posts.

---

## Security notes

- **TLS skip is acceptable** on this link because Malcolm's nginx-proxy uses an
  internal CA managed by the supportTAK deployment, and both endpoints live inside
  the GREEN zone per ADR-E04 data-layer trust boundary. Do **not** use `-k` or
  `verify=False` for any endpoint outside 192.168.1.0/24.
- **Credentials are shared** `malcolm_internal` are write-scoped by design. Rotate
  via the Malcolm htadmin container if compromise is suspected; the receipt
  contract does not assume a specific credential value, only the presence of
  basic auth.
- **No secrets in receipts.** The `detail` field is free text. Do not include
  credentials, tokens, or PII. For `rolled_back`, describe *what* failed in
  abstract terms (e.g., "post-apply ping-test timeout after 3 retries"), not
  with raw session data.
- **No retries from either side.** ADR-E01 forbids auto-retry. If a receipt
  write fails transiently, the desktop SOC should log locally and surface to
  the analyst. Do not replay; the recommendation stays in whatever state it
  was in, and the analyst can re-issue a new recommendation if needed.
