# ADR-0001: SSH Management Port

- **Date:** 2026-03-25
- **Status:** Accepted

## Context

IPFire defaults SSH to port 22. Some hardening guides recommend non-standard ports (e.g., 222) to reduce scan noise. The repo had inconsistent references to both ports across configs and docs.

## Decision

Use port 22 (IPFire default). Standardize all configs, docs, and validation scripts to reference port 22 exclusively.

## Rationale

- Port obscurity is not a security control (CIS does not recommend it)
- Guardian provides brute-force protection regardless of port
- Non-standard ports add operational complexity without meaningful security gain
- Key-only auth + source IP restriction are the actual controls

## Consequences

- All docs updated to reference port 22
- No SSH port change needed in IPFire config
- Simpler operational procedures
