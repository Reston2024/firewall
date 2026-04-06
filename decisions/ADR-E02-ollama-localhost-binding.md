# ADR-E02: Ollama Must Bind to Localhost Only

- **Date:** 2026-04-05
- **Status:** Accepted
- **Enforcement:** Phase 11 pre-deployment gate
- **References:** Security sweep finding E6-01 (CRITICAL)

## Context

Ollama's default configuration binds to `0.0.0.0:11434` with no authentication. On supportTAK-server (192.168.1.22), this would expose Foundation-Sec-8B to every device on the GREEN LAN. Any GREEN device could submit arbitrary prompts, extract model outputs, or inject adversarial instructions that contaminate the triage pipeline.

## Decision

Ollama MUST be configured to bind to `127.0.0.1` only. This is enforced via:

1. **Systemd environment:** Set `OLLAMA_HOST=127.0.0.1` in the Ollama systemd service unit file (`/etc/systemd/system/ollama.service.d/override.conf`)
2. **Firewall rule:** Add `ufw deny 11434` on supportTAK-server as defense-in-depth

## Verification Gate

Before Phase 11 is marked complete:

```bash
# Must show 127.0.0.1, NOT 0.0.0.0
ss -tlnp | grep 11434

# Must be refused from any LAN host
curl -s http://192.168.1.22:11434/api/tags
# Expected: Connection refused
```

Add to `scripts/validate-phase11.sh` as a blocking check.

## Rationale

- OWASP LLM Top 10 2025 LLM01 (Prompt Injection) — unauthenticated API exposure is the highest-risk vector
- MITRE ATLAS AML.T0054 — LLM prompt injection via network access
- No authentication mechanism exists for Ollama's API — binding restriction is the only viable control
- The management host (192.168.1.100) accesses Ollama indirectly through scripts that SSH to localhost, not via the network API

## Consequences

- All scripts that call Ollama must use `localhost:11434`, never `192.168.1.22:11434`
- Remote triage queries must SSH to supportTAK-server first, then curl localhost
- If Ollama is ever moved to a separate host, a TLS reverse proxy with auth must be added
