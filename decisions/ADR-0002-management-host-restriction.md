# ADR-0002: Management Access — Single Host Only

- **Date:** 2026-03-25
- **Status:** Accepted

## Context

firewall.local originally had two layers: host-specific ACCEPT rules for 192.168.1.100, followed by broad GREEN-zone ACCEPT rules as an anti-lockout fallback. The broad rules negated the host restriction.

## Decision

Remove the broad GREEN ACCEPT fallback. Management access (SSH port 22, WUI port 444) is restricted to 192.168.1.100 only via CUSTOMINPUT rules.

## Rationale

- CIS v8 Control 4.7: restrict management interfaces to authorized hosts
- NIST 800-53 AC-17: limit remote access to specific managed access control points
- Physical console access remains available for IP change recovery
- ORANGE and BLUE zones explicitly DROP SSH/WUI traffic

## Consequences

- If management host IP changes, recovery requires physical console
- No LAN device other than 192.168.1.100 can reach SSH or WUI
- Stronger security posture aligns with defense-in-depth
