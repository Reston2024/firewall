# Meta-Prompt v1.1.0 → v1.2.0 Update Notes

**Date:** 2026-04-06
**Context:** Phase 10 completed; Loki decommissioned; Malcolm sole telemetry backend

## Required Changes

### 1. Architecture Reference — Update Layer 1 and Layer 3

Layer 1 (Malcolm) — add:
- EVE JSON path: `/opt/malcolm/suricata-logs/suricata-ipfire/eve.json` (NOT via external Filebeat)
- Malcolm internal Filebeat handles EVE with tag `_filebeat_suricata_malcolm_upload`
- External system Filebeat was tested and ABANDONED (Malcolm Logstash routes on internal tags only)
- Logstash heap: 2GB (was 1GB, caused OOM — FP-014 confirmed)

Layer 3 (Observability) — replace entirely:
- Phase 10 COMPLETE: Loki/Alloy/Grafana/Prometheus decommissioned 2026-04-06
- Malcolm is SOLE observability layer
- No parallel validation window — migration complete

### 2. Remove or Archive Domain-4 (Observability/Loki)

All VERIFY-O commands are now invalid (Loki is gone). Archive to a "historical reference" section or remove entirely. Replace with Malcolm-specific observability checks:
- VERIFY-O1: `docker compose -f /opt/malcolm/docker-compose.yml ps | grep -c healthy` (expect 27)
- VERIFY-O2: `curl -sk https://localhost:443/` (expect 401 — auth required)

### 3. Update Domain-6 to Post-Migration State

Domain-6 (Migration) scope should shift from "confirm migration" to "confirm stability":
- Remove parallel window verification (no longer applicable)
- Add post-decommission RAM monitoring: `free -m` should show < 12GB used (vs 12.5GB during parallel)
- Add rsyslog relay health: `pgrep -c rsyslogd` (systemd reports inactive due to PID mismatch, but process runs)

### 4. Update Failure Pattern Library

**FP-009 (Logstash :5044 not exposed):** CLOSED — ports added to docker-compose.yml
**FP-010 (Filebeat :5514 not exposed):** CLOSED — port added with `/udp` suffix
**FP-012 (Filebeat routing to wrong index):** SUPERSEDED — external Filebeat abandoned; Malcolm internal Filebeat handles routing via `suricata-*/eve*.json` glob + `_filebeat_suricata_malcolm_upload` tag
**FP-014 (OOM):** PARTIALLY CLOSED — OpenSearch heap at 6GB, Logstash at 2GB, Arkime disabled. Still a risk when AI model loads.

**Add new patterns:**
- FP-017: Malcolm internal Filebeat requires files in `suricata-*/` subdirectory — files directly in `suricata-logs/` are ignored
- FP-018: IPFire authorized_keys lost on crash/reboot — both management and eve_rsync keys must be re-injected (stored in `configs/ssh/authorized_keys`)
- FP-019: rsyslog PID file mismatch — `systemctl is-active rsyslog` returns "inactive" but process is running; use `pgrep rsyslogd` instead

### 5. Update VERIFY-P5

Change from:
```
VERIFY-P5: systemctl status filebeat
```
To:
```
VERIFY-P5: ssh opsadmin@192.168.1.22 \
  'docker exec malcolm-filebeat-1 ps aux | grep filebeat | head -1'
# Confirm Malcolm internal Filebeat is running (not system Filebeat)
```

### 6. Layer 2 (AI-SOC Brain) — Mark as "NOT YET DEPLOYED"

All VERIFY-D and VERIFY-A commands will fail until Phase 11-13 are complete. Add a gate:
```
PREREQUISITE: Phase 11 (Foundation-Sec-8B), Phase 12 (RAG), Phase 13 (Triage Integration)
              must be complete before Domain-3 and Domain-5 are active.
```

### 7. Update Migration State Template

The invocation template's "PHASE 10 MIGRATION STATE" section should become:
```
MIGRATION STATE: COMPLETE
  • Loki decommissioned: 2026-04-06
  • Malcolm receiving EVE JSON: Yes (225K+ docs in arkime_sessions3-*)
  • Malcolm receiving syslog: Yes (628K+ docs in malcolm_beats_syslog_*)
  • Logstash :5044 host-exposed: Yes
  • Filebeat syslog :5514 host-exposed: Yes
```

### 8. Add ADR-E02 Gate to Domain-5

When Phase 11 deploys Ollama, Domain-5 VERIFY-A1 must also check:
```
VERIFY-A1b: ss -tlnp | grep 11434
# MUST show 127.0.0.1:11434, NOT 0.0.0.0:11434
# Per ADR-E02: Ollama LAN exposure is CRITICAL finding
```
