# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| master (current) | Yes |

## Reporting a Vulnerability

If you discover a security issue in this repository:

1. **Do not** open a public issue
2. Email the maintainer directly
3. Include: description, reproduction steps, and potential impact
4. Allow 72 hours for initial response

## Security Controls

### Secrets

- No credentials, keys, or tokens are committed to this repository
- All secrets are managed via `.env` files (excluded by `.gitignore`)
- Template: `telemetry/.env.example`
- Pre-commit hooks scan for accidental secret commits

### Management Access

- SSH and WUI access restricted to a single management host (192.168.1.100)
- No broad LAN fallback rules (CIS v8 Control 4.7 / NIST AC-17)
- Recovery requires physical console access

### Service Exposure

- Grafana bound to 127.0.0.1 — access via SSH tunnel only
- Loki, Prometheus, Alloy bound to loopback
- No services exposed to WAN

### Out of Scope

- IPFire upstream vulnerabilities (report to ipfire.org)
- Grafana/Loki/Prometheus upstream CVEs (report to respective projects)
- Hardware-level attacks requiring physical access
