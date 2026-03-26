# ADR-0011: Modular Per-Phase Validation Suite

- **Date:** 2026-03-25
- **Status:** Accepted

## Context

The project spans 6 phases of IPFire configuration, each adding distinct capabilities (platform, network services, SSH hardening, IDS/IPS, telemetry, system hardening). A comprehensive validation suite is needed to verify that all phases are correctly configured after deployment and after each rebuild. A single monolithic validation script would be difficult to maintain, impossible to run selectively, and would grow unwieldy as phases are added.

## Decision

Implement per-phase validation scripts (`validate-phase1.sh` through `validate-phase6.sh`) orchestrated by a single `validate-all.sh` runner. Each script exits 0 (pass) or 1 (fail). `validate-all.sh` calls each in sequence and aggregates results.

## Rationale

- Modular design allows running individual phase validation in isolation — useful for targeted troubleshooting and partial rebuilds
- Each script is independently testable and maintainable
- Adding a new phase means adding one new script, not modifying a growing monolith
- The pass/fail/skip pattern is consistent and simple across all scripts — SKIP indicates a valid non-failure state (e.g., no static DHCP leases, optional infrastructure offline)
- Phase 5 (telemetry) validation runs remotely via SSH to the monitoring host (192.168.1.101) — this different execution model is cleanly encapsulated in `validate-phase5.sh` without affecting other scripts
- `--phase N` flag in `validate-all.sh` enables single-phase execution for rapid iteration

## Consequences

- `validate-all.sh` is the single acceptance gate for rebuild completion — the rebuild procedure is not complete until `validate-all.sh` passes (D-06)
- Phase 5 validation requires SSH access from IPFire to the supportTAK-server (192.168.1.101) — if the monitoring host is offline, Phase 5 validation returns SKIP (not FAIL), reflecting that it is optional off-box infrastructure
- SKIP status is a valid terminal state for certain checks — documented per-check in each script
- validate-phase4.sh IDS-04 (Suricata monitor mode) is permanently SKIP — monitor mode cannot be verified from CLI reliably, WUI verification required
