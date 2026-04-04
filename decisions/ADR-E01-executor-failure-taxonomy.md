# ADR-E01: Executor Failure Taxonomy

- **Date:** 2026-04-03
- **Status:** Accepted
- **Canonical location:** firewall/decisions/ADR-E01-executor-failure-taxonomy.md

## Context

The firewall executor processes recommendation artifacts dispatched from the AI-SOC analyst pipeline. Each artifact represents a proposed network control change (block IP, isolate host, suppress alert, etc.) that has been analyst-approved and schema-validated before reaching the executor.

The executor must handle every artifact deterministically and emit a structured execution receipt for every artifact it processes — regardless of outcome. The receipt is the audit trail proving the firewall acted (or correctly refused to act) on each recommendation.

Without a defined taxonomy, failure modes are ambiguous: did the rule fail validation? Was it already present? Did it expire in transit? Was it applied then rolled back? Each mode has different operational implications and different required human responses.

## Decision

Define five mutually exclusive failure taxonomy values. Every execution receipt MUST contain exactly one of these values. No artifact may be processed without emitting a receipt.

### Failure Taxonomy

| Taxonomy Value | Meaning | Executor Action | Receipt Emitted? | Auto-Retry? |
|---|---|---|---|---|
| `applied` | Rule applied successfully | Rule added to firewall; state validated post-apply | Yes | N/A |
| `noop_already_present` | Rule already exists in firewall state; no change needed | No mutation; log that the rule was already present | Yes | N/A |
| `validation_failed` | Artifact or proposed rule failed pre-apply or post-apply validation | Reject; hold for human review | Yes | No |
| `expired_rejected` | Artifact `expires_at` is in the past (relative to firewall clock) | Reject; do not apply | Yes | No |
| `rolled_back` | Rule was applied, but post-apply state validation failed; rule was removed | Apply, detect failure, undo; hold for human review | Yes | No |

### Validation Failed — Two Sub-Cases

`validation_failed` covers both pre-apply and post-apply validation failures:

- **Pre-apply (schema invalid):** The artifact itself fails schema validation, or the proposed rule parameters are invalid for the target zone/protocol. The executor never mutates firewall state.
- **Post-apply (state validation fails):** The rule was syntactically valid and was applied, but post-apply firewall state validation (e.g., connectivity check, rule conflict detection) indicates the applied rule created an undesirable state. In this sub-case, the executor MUST roll back and report `rolled_back` instead of `validation_failed`. The `validation_failed` taxonomy is reserved for cases where the rule was never applied.

### Expired Rejected — Clock Skew Tolerance

The firewall executor independently checks `expires_at` against its own system clock. A 60-second skew tolerance applies: artifacts where `expires_at` is within 60 seconds of the current time are still accepted. Beyond 60 seconds past expiry, the executor emits `expired_rejected`.

This tolerance accounts for clock drift between the analyst workstation (where `expires_at` is set) and the firewall appliance. NTP synchronization between both systems is assumed (validated in Phase 2, SVC-03).

### Rolled Back — Documentation Requirement

When the executor emits `rolled_back`, the receipt `detail` field MUST document:
1. What post-apply validation check failed
2. What the expected state was vs. what was observed
3. Whether the rollback itself succeeded (if the rollback fails, this is an operational emergency requiring immediate human intervention)

## Rationale

- **No auto-retry for any failure mode:** Retrying a failed rule application without human review risks compounding the failure (e.g., applying a malformed rule repeatedly, or re-applying a rule that caused a routing loop).
- **Receipt for every artifact:** The audit trail must be complete. An artifact without a receipt is a gap in the chain of custody between the AI analyst and the firewall.
- **Mutual exclusivity:** Each artifact gets exactly one disposition. No artifact can be both `applied` and `validation_failed`. This simplifies audit queries and compliance reporting.
- **Firewall-side expiry check:** The executor does not trust the dispatch pipeline's clock. Defense in depth: even if the dispatch system has a clock skew bug, the firewall independently rejects stale artifacts.

## Architecture Constraint

The firewall executor is BOUNDED:
- Only processes recommendation artifacts that pass schema validation against `contracts/recommendation.schema.json`
- Only processes artifacts where `analyst_approved = true`
- Only processes artifacts where current UTC < `expires_at` (with 60s tolerance)
- Never takes action based on raw LLM output — only on structured, schema-validated, analyst-approved artifacts

## Consequences

- All executor code paths must emit a receipt with one of the five taxonomy values
- The `detail` field is required (non-empty) for all taxonomy values except `applied` and `noop_already_present`
- The `firewall_rule_id` field is populated only for `applied` and `noop_already_present`
- Human review workflows must handle `validation_failed`, `expired_rejected`, and `rolled_back` as distinct alert types
- The 60-second skew tolerance must be configurable but defaults to 60s
- Receipt schema is defined in `contracts/execution-receipt.schema.json`
