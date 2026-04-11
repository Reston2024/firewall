---
phase: 13-alert-triage-soc-integration
plan: 02
status: complete
started: 2026-04-10
completed: 2026-04-10
duration_minutes: 95
---

# Phase 13 Plan 02 Summary: TRI-06 E2E Rails + Handoff Contract

## What Was Built

Completes the Firewall-side half of the TRI-06 "meet in the middle" contract
between this repo and the desktop SOC (local-ai-soc). Verifies that the rails
are live — any schema-conformant execution receipt written by the desktop SOC
into the supportTAK `triage-results-*` index will be detected, validated, and
cause TRI-06.4 to PASS.

### New files

- `scripts/validate-tri06.sh` — dedicated E2E gate with 5 checks:
  - `[TRI-06.0]` execution-receipt schema present and parseable
  - `[TRI-06.1]` triage-results-template bound to `triage-results-*` pattern
  - `[TRI-06.2]` `malcolm-retention` ISM policy covers `triage-results-*`
  - `[TRI-06.3]` at least one `triage-results-YYYY.MM.DD` index exists (SKIP-acceptable)
  - `[TRI-06.4]` at least one document with `schema_version="1.0.0"` and a
    valid `failure_taxonomy` enum value exists, excluding smoketest indices
- `scripts/emit-receipt.sh` — reference emitter for desktop SOC forwarder
  authors. Reads a receipt JSON document, validates required fields, rejects
  the `REPLACE_WITH_FRESH_UUID` placeholder, checks UUID v4 format on the
  three UUID fields, verifies `failure_taxonomy` enum, then POSTs to
  `triage-results-$(date -u +%Y.%m.%d)/_doc` with `malcolm_internal` auth.
  Env overrides: `FIREWALL_RECEIPT_CREDS`, `FIREWALL_OPENSEARCH`.
- `docs/tri06-receipt-contract.md` — single-page "railroad meeting point"
  contract document spelling out: Firewall guarantees, Desktop requirements,
  the 5 failure_taxonomy values with required sibling fields, reference
  receipt JSON, write command, E2E procedure, security notes.
- `examples/receipts/README.md` + 5 JSON examples
  (`applied`, `noop_already_present`, `validation_failed`,
  `expired_rejected`, `rolled_back`) — each a complete schema-conformant
  document with realistic `detail` content.

### Fixed files

- `scripts/validate-phase13.sh`:
  - Removed stale TRI-05 check (SSHed to IPFire for the :8300 executor
    scaffold that ADR-E04 retracted); replaced with documented SKIP.
  - Moved TRI-06 infrastructure ISM check to TRI-03b; the real TRI-06 E2E
    gate now lives in `validate-tri06.sh`.
  - Now reports 5 PASS, 0 FAIL, 2 SKIP with both SKIPs carrying explicit
    ADR-E04 rationale.

## Key Outcomes

**Rails proven end-to-end via live test on 2026-04-10:**

1. Smoke test wrote a `validation_failed` receipt into a dedicated
   `triage-results-smoketest-20260410` index. HTTP 201 created. Read-back
   via `match` query succeeded. OpenSearch dynamic mapping correctly
   absorbed all 9 receipt fields (strings became text+keyword multi-fields,
   ISO-8601 timestamps were auto-typed as `date`). Smoke test index was
   immediately DELETEd; `validate-tri06.sh` explicitly excludes
   `triage-results-smoketest-*` as defense-in-depth.

2. Reference-emitter end-to-end test generated a fresh UUID v4, substituted
   it into `examples/receipts/applied.json`, piped through
   `scripts/emit-receipt.sh`, wrote successfully to `triage-results-2026.04.11`
   (UTC), and validate-tri06.sh reported `TRI-06.4 PASS` with the real
   `receipt_id`, `taxonomy=applied`, and `recommendation_id` echoed in the
   PASS line. The test index was then deleted so the audit gate returned to
   its natural SKIP state (no actual AI-generated receipts yet).

3. Validate-tri06.sh final state at phase close: **3 PASS / 0 FAIL / 2 SKIP**.
   The 2 SKIPs are `TRI-06.3` (no daily index yet) and `TRI-06.4` (no real
   AI-generated receipt yet) — expected and acceptable per the contract.

## Decisions

- **TRI-06 closure is split into "rails complete" and "E2E verified".**
  The Firewall side (rails) is complete and live-tested. The desktop side
  (AI-pipeline-to-receipt-forwarder) is tracked as v2.1 work. This is
  reflected in REQUIREMENTS.md as `[~] TRI-06` with a pointer to this
  summary.
- **Index template is NOT extended with explicit receipt field mappings.**
  OpenSearch dynamic mapping handles receipt fields correctly (strings
  → text+keyword, ISO-8601 → date). Explicit template extension is a v2.1
  tech-debt item — clean engineering refinement, not a correctness issue.
- **Smoke-test indices use a dedicated prefix** (`triage-results-smoketest-*`)
  and `validate-tri06.sh` explicitly excludes them. Defense-in-depth
  against operator-left-over debris polluting the audit gate.
- **validate-tri06.sh uses `match` not `term` for `schema_version`.** `match`
  works across both text and keyword mappings and survives any future
  template tightening.
- **emit-receipt.sh rejects placeholder UUIDs.** Catching
  `REPLACE_WITH_FRESH_UUID` at emit time prevents accidental pollution of
  `triage-results-*` with documents that reference literal placeholder
  strings as keys.

## Files Modified

| File | Location | Change |
|---|---|---|
| `scripts/validate-phase13.sh` | Firewall repo | Fixed stale TRI-05 and TRI-06 checks |
| `scripts/validate-tri06.sh` | Firewall repo | NEW — 5-check E2E gate |
| `scripts/emit-receipt.sh` | Firewall repo | NEW — reference emitter |
| `docs/tri06-receipt-contract.md` | Firewall repo | NEW — contract document |
| `examples/receipts/README.md` | Firewall repo | NEW — usage guide |
| `examples/receipts/applied.json` | Firewall repo | NEW — reference receipt |
| `examples/receipts/noop_already_present.json` | Firewall repo | NEW — reference receipt |
| `examples/receipts/validation_failed.json` | Firewall repo | NEW — reference receipt |
| `examples/receipts/expired_rejected.json` | Firewall repo | NEW — reference receipt |
| `examples/receipts/rolled_back.json` | Firewall repo | NEW — reference receipt |

## Concerns

1. **TRI-06 is closed as partial**. Per the requirement wording ("IPFire
   alert → Malcolm → SOC pull → detect → investigate → recommend →
   receipt"), full closure requires a real AI-generated receipt from the
   desktop SOC. That was not produced during this session because the
   desktop-side forwarder (from the local-ai-soc internal store to
   `triage-results-*`) has not yet been built. The rails are fully proven
   and the emitter is live-tested; the remaining work is desktop-repo
   scope. **Tracked as v2.1 task** in milestone audit.

2. **Tech debt**: `triage-results-template` uses dynamic mapping for the
   9 execution-receipt fields. Works correctly today but explicit typed
   mappings would be cleaner and protect against future schema drift.
   **Tracked as v2.1 task**.

3. **Integration test coverage**: the desktop-side forwarder should have
   its own unit/integration tests in the local-ai-soc repo. The Firewall
   side cannot enforce that from here; the receipt contract document
   explicitly calls it out.
