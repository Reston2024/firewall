# ADR-0007: Suricata Monitor Mode with IPS Transition Gate

- **Date:** 2026-03-25 (original), 2026-04-05 (amended)
- **Status:** Accepted (amended with transition gate)

## Context

Suricata was deployed in monitor-only (IDS) mode during Phase 4 to allow rule tuning and false-positive baselining before enabling inline prevention. The original ADR documented no completion criteria or deadline for the tuning period.

Security sweep finding E1-01 (HIGH) identified this as an open-ended design state with no closure gate.

## Decision

Suricata remains in monitor-only mode until the following transition gate is met:

### IPS Transition Gate

**Deadline:** 2026-05-05 (30 days from this amendment)

**Criteria — ALL must be true before enabling IPS (NFQ drop mode):**

1. **False-positive baseline documented:** A 30-day continuous observation log showing false-positive rate by rule category (ET Community rules), with suppression list for confirmed false positives
2. **No suppressions needed for critical services:** Management SSH (port 22), WUI (:444), DNS (53/853), DHCP (67/68), NTP (123), and SCP EVE pull must not trigger false positives after tuning
3. **Rollback procedure tested:** Documented and tested procedure to revert from IPS to IDS mode within 60 seconds if IPS causes connectivity loss
4. **Anti-lockout verification:** Confirm CUSTOMINPUT rules survive NFQ mode transition — management access must not be interrupted

### Post-Transition Monitoring

After IPS is enabled:
- 72-hour intensive monitoring period with operator on-call
- `validate-phase4.sh` updated to check for NFQ/drop mode
- Rollback if any management access disruption detected

## Rationale

- Detection without prevention leaves the perimeter open to all attacks Suricata can identify but cannot stop
- An open-ended "tuning period" with no deadline becomes permanent monitor-only by default
- The 30-day gate provides a concrete milestone while allowing adequate tuning time
- The gate criteria ensure IPS won't break critical services

## Consequences

- Phase 15 (Suricata IPS Transition) added to v2.0 roadmap
- If gate criteria are not met by 2026-05-05, the deadline extends by 14 days with a documented reason
- suricata.yaml changes for NFQ mode are documented in the IPS transition runbook (Phase 15 deliverable)
- E1-01 finding closes when NFQ drop mode is active and validate-phase4.sh confirms it
