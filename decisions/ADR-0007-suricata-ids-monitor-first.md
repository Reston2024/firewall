# ADR-0007: Suricata IDS Monitor-First Deployment

- **Date:** 2026-03-25
- **Status:** Accepted

## Context

Suricata IDS/IPS can operate in two modes: monitor-only mode (logs alerts, takes no action on traffic) or active IPS mode (drops packets matching rules). Active IPS mode provides real protection but risks blocking legitimate traffic if rules are not tuned for the environment. The ET Community ruleset includes rules calibrated for enterprise environments that may trigger on normal home/SOHO traffic patterns (e.g., DNS queries, streaming protocols, common applications).

## Decision

Deploy Suricata in monitor-only mode first. Switch to active IPS mode only after a tuning period where false positives have been identified and whitelisted.

## Rationale

- Monitor mode allows baselining legitimate traffic patterns without any risk of self-lockout or service disruption
- False positives from untuned ET Community rules can be identified, evaluated, and suppressed before enabling packet drops
- Prevents self-lockout during initial deployment — a misconfigured IPS rule could block SSH or WUI access
- Active IPS mode with untuned rules could disrupt DNS, streaming, VoIP, and other legitimate services
- Rule categories are enabled incrementally (per IDS-07 task) to prevent overwhelming the system and to isolate alert sources
- The ET Community ruleset needs calibration for home/SOHO traffic patterns — this takes observation time, not just configuration

## Consequences

- Initial deployment only logs alerts — no active blocking of malicious traffic during the tuning period
- Suricata mode must be manually switched to active IPS via WUI after tuning is complete and false positives are addressed
- The tuning period duration is not fixed — depends on traffic volume and number of false positives observed
- validate-phase4.sh marks IDS-04 (monitor mode check) as SKIP — monitor mode cannot be reliably read from CLI; WUI verification required
