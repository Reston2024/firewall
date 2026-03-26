# ADR-0009: Sysctl Hardening Append Strategy

- **Date:** 2026-03-25
- **Status:** Accepted

## Context

Phase 6 system hardening requires applying CIS Level 1 kernel parameters via sysctl. IPFire's `/etc/sysctl.conf` contains critical routing parameters, including `net.ipv4.ip_forward=1`, which is required for WAN routing to function. Two approaches exist: overwrite the entire file with a curated set of parameters, or append hardening parameters to the existing file. Overwriting risks removing IPFire's own routing settings. Bare appending (cat >>) is not idempotent — re-running the deploy script would duplicate parameters on every execution.

## Decision

Append hardening parameters to `/etc/sysctl.conf` (never overwrite). Use a grep-based idempotency check before appending: `grep -q "net.ipv4.conf.all.send_redirects" /etc/sysctl.conf || cat sysctl-hardening.conf >> /etc/sysctl.conf`.

## Rationale

- Preserves IPFire's own routing settings, particularly `ip_forward=1` which is critical for NAT/masquerade and WAN routing
- Appending with dedup check is safe to re-run — the grep test prevents duplicate entries on subsequent executions
- CIS Level 1 parameters (send_redirects=0, accept_source_route=0, accept_redirects=0, rp_filter=1, tcp_syncookies=1) are additive hardening — they do not conflict with IPFire's own params
- `sysctl -p` for loading parameters is already idempotent regardless of approach
- The pattern is consistent with how other deploy scripts handle idempotency (check-before-apply)

## Consequences

- The rebuild script must use the grep-before-append pattern, not a bare `cat >>` or file overwrite
- Drift detection checks the `/etc/sysctl.conf` SHA256 hash — any Core Update that modifies this file will trigger a drift alert requiring review
- The `configs/hardening/sysctl-hardening.conf` file in the repo is the authoritative source of truth for which parameters to add
- If IPFire changes its sysctl defaults in a Core Update, the drift check will catch it and the append list may need review
