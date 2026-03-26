# ADR-0006: Guardian Over fail2ban

- **Date:** 2026-03-25
- **Status:** Accepted

## Context

SSH and WUI brute-force protection is a baseline security requirement for any internet-facing management interface. fail2ban is the standard Linux choice for this purpose and is widely documented. However, fail2ban is not available in IPFire's Pakfire package manager. Installing software outside Pakfire on IPFire violates the project constraint of IPFire-native tools only, and risks being overwritten or broken by Core Updates.

## Decision

Use Guardian (Pakfire add-on) for SSH and WUI brute-force protection instead of fail2ban.

## Rationale

- Guardian is IPFire's native brute-force protection tool, available and maintained via Pakfire
- Managed through IPFire WUI — consistent with the project's IPFire-native management approach
- Actively maintained: updated February 2025 by the IPFire project team
- fail2ban is not in Pakfire and has no supported path to installation on IPFire without deviating from the native tools constraint
- Installing packages outside Pakfire creates upgrade fragility — Core Updates can overwrite or break them
- Guardian protects both SSH (port 22) and WUI (port 444) — covers the two management interfaces that need protection

## Consequences

- Brute-force protection is configured via WUI (not CLI config files) — Guardian configuration is not version-controlled in the repo
- Guardian configuration is documented in the rollback README as a manual provisioning step during rebuild
- Configuration changes to Guardian thresholds or blocked IP lists must be made through WUI and noted in operational documentation
- Guardian's WUI-managed approach is consistent with other IPFire add-ons and reduces config drift risk
