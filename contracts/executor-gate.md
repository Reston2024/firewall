# Executor Gate Contract

- **Version:** 1.0.0
- **Date:** 2026-04-03
- **Governed by:** ADR-E01 (Executor Failure Taxonomy)
- **Canonical location:** firewall/contracts/executor-gate.md

## Purpose

This document defines the pre-conditions that the firewall executor evaluates before processing any recommendation artifact. These gates are non-negotiable: if any gate fails, the artifact is rejected and a receipt is emitted with the appropriate failure taxonomy.

The executor is the final trust boundary between the AI-SOC analyst pipeline and the live firewall. It exists to ensure that no raw LLM output, no unapproved recommendation, and no expired artifact can mutate firewall state.

## Gate Sequence

Gates are evaluated in order. The first failing gate determines the receipt taxonomy. Evaluation stops at the first failure.

```
Artifact arrives
    |
    v
[Gate 1] Schema validation
    | pass -> continue
    | fail -> emit receipt: validation_failed
    v
[Gate 2] Analyst approval check
    | analyst_approved == true -> continue
    | analyst_approved != true -> emit receipt: validation_failed
    v
[Gate 3] Expiry check
    | current_utc < expires_at + 60s -> continue
    | current_utc >= expires_at + 60s -> emit receipt: expired_rejected
    v
[Gate 4] Duplicate check
    | rule not present in firewall -> continue to apply
    | rule already present -> emit receipt: noop_already_present
    v
[Gate 5] Apply rule
    | apply succeeds -> continue to post-validation
    | apply fails -> emit receipt: validation_failed
    v
[Gate 6] Post-apply state validation
    | state valid -> emit receipt: applied
    | state invalid -> rollback, emit receipt: rolled_back
```

## Gate Definitions

### Gate 1: Schema Validation

**Input:** Raw artifact JSON
**Validates against:** `contracts/recommendation.schema.json` v1.0.0
**On failure:** `validation_failed`
**Detail:** Schema validation error message (e.g., "missing required field: case_id")

The executor MUST validate the artifact against the recommendation schema before reading any field values. This prevents type confusion, injection via malformed fields, and processing of artifacts from incompatible schema versions.

### Gate 2: Analyst Approval

**Input:** `analyst_approved` field from validated artifact
**Condition:** `analyst_approved === true`
**On failure:** `validation_failed`
**Detail:** "analyst_approved is not true; artifact has not been human-approved"

This gate exists because the AI analyst generates recommendation artifacts that are initially unapproved. The approval gate (in the AI-SOC pipeline) sets `analyst_approved = true` and populates `approved_by`. The executor independently re-checks this field as defense in depth.

### Gate 3: Expiry Check

**Input:** `expires_at` field from validated artifact, firewall system clock (UTC)
**Condition:** `current_utc < expires_at + 60_seconds`
**On failure:** `expired_rejected`
**Detail:** "artifact expired at {expires_at}; firewall clock is {current_utc}; skew tolerance 60s exceeded"

The 60-second tolerance accounts for clock drift between the analyst workstation and the firewall. Both systems SHOULD be NTP-synchronized (validated in Phase 2, SVC-03). The tolerance is configurable but defaults to 60 seconds.

The firewall uses its OWN clock, not the dispatch system's clock. This is intentional: if the dispatch system's clock is compromised or drifted, the firewall independently rejects stale artifacts.

### Gate 4: Duplicate Check

**Input:** Proposed rule parameters (target, scope, action) from validated artifact
**Condition:** No existing firewall rule matches the proposed rule's effective parameters
**On match:** `noop_already_present`
**Detail:** "equivalent rule already present: {firewall_rule_id}"

This prevents duplicate rules from accumulating. The match is semantic, not string-identical: a rule blocking 203.0.113.42 on RED->GREEN is considered equivalent regardless of whether the existing rule was created manually or by a previous artifact.

### Gate 5: Rule Application

**Input:** Validated, approved, non-expired, non-duplicate artifact
**Action:** Add the proposed rule to the firewall (e.g., `iptables -A` or IPFire WUI API equivalent)
**On failure:** `validation_failed`
**Detail:** Firewall error message (e.g., "iptables: No chain/target/match by that name")

If the firewall command itself fails (syntax error, invalid target, etc.), the rule was never applied and the executor emits `validation_failed`.

### Gate 6: Post-Apply State Validation

**Input:** Firewall state after rule application
**Validates:** Connectivity checks, rule conflict detection, expected state assertions
**On success:** `applied`
**On failure:** Rollback the applied rule, then emit `rolled_back`

Post-apply validation checks that the firewall is still in a healthy state after the rule was added. This catches cases where a syntactically valid rule creates an operationally harmful state (e.g., a rule that inadvertently blocks management access, or creates a routing loop).

When rollback is triggered, the `detail` field MUST document:
1. Which validation check failed
2. Expected state vs. observed state
3. Whether the rollback itself succeeded

If the rollback fails, this is an operational emergency. The receipt is still emitted (with `rolled_back` taxonomy and detail noting rollback failure), and the executor MUST alert the operator through all available channels.

## Receipt Contract

Every artifact that enters the gate sequence produces exactly one execution receipt, validated against `contracts/execution-receipt.schema.json` v1.0.0.

No artifact may be silently dropped. No artifact may produce more than one receipt. The receipt is the proof of processing.

## Operational Boundaries

The executor:
- **DOES** process structured, schema-validated recommendation artifacts
- **DOES** emit a receipt for every artifact
- **DOES NOT** accept raw LLM output, natural language instructions, or unstructured data
- **DOES NOT** auto-retry any failure
- **DOES NOT** escalate decisions — it accepts or rejects, never "maybe"
- **DOES NOT** modify the artifact — it processes the artifact as received

## Related Documents

- `decisions/ADR-E01-executor-failure-taxonomy.md` — Taxonomy definitions and rationale
- `contracts/execution-receipt.schema.json` — Receipt schema
- `contracts/recommendation.schema.json` (in local-ai-soc repo) — Artifact schema
