# ADR-0003: Grafana Bound to Loopback Only

- **Date:** 2026-03-25
- **Status:** Accepted

## Context

Grafana was published as `0.0.0.0:3000`, exposing the dashboard to all interfaces on supportTAK-server. Other telemetry services (Loki, Prometheus, Alloy) were already bound to 127.0.0.1.

## Decision

Bind Grafana to `127.0.0.1:3000`. Access via SSH tunnel from the management host:

```bash
ssh -L 3000:127.0.0.1:3000 opsadmin@192.168.1.101
```

## Rationale

- Consistent with Loki/Prometheus/Alloy loopback binding
- No reason to expose dashboards to the full LAN
- SSH tunnel provides authentication and encryption
- Eliminates need for Grafana-level auth hardening as primary control

## Alternatives Considered

- **Reverse proxy (nginx):** adds complexity for a single-user deployment
- **LAN exposure with strong auth:** acceptable but unnecessary given SSH tunnel simplicity
