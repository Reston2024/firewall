# ADR-0004: Telemetry Stack Runs Off-Box

- **Date:** 2026-03-21
- **Status:** Accepted

## Context

IPFire does not support Docker (rejected by IPFire developers). The telemetry stack (Grafana, Loki, Alloy, Prometheus) requires containerization for manageable deployment.

## Decision

Run the entire telemetry stack on a separate Ubuntu 22.04 host (supportTAK-server, 192.168.1.22) on the GREEN LAN, orchestrated via Docker Compose.

## Rationale

- IPFire explicitly rejects Docker — no workaround available
- Separation of concerns: firewall does firewalling, telemetry host does observability
- N100 is low-power; offloading telemetry preserves firewall performance
- Ubuntu + Docker is the standard deployment target for Grafana stack

## Consequences

- Two machines to maintain instead of one
- Log transport required (syslog UDP, rsync for EVE JSON)
- Telemetry host becomes a dependency for observability (not for security)
