# ADR-E04: Architecture Pivot — Data Layer Separation

- **Date:** 2026-04-08
- **Status:** Accepted
- **Supersedes:** Phase 11 (Foundation-Sec-8B on N150), Phase 12 (RAG on N150), Phase 13 (executor on N150)
- **Trigger:** Post-deployment review identified ~9-10 hours of wasted effort and architectural theater

## Context

During v2.0 execution, the following problems were identified:

1. **AI on the N150 was redundant.** The desktop SOC (local-ai-soc) has an RTX 5080 running qwen3:14b at 50-80+ tok/s. Foundation-Sec-8B on the N150 runs at 2.47 tok/s (CPU-only). The N150 AI was 20-30x slower and required temporal separation (pausing Malcolm to free RAM).

2. **AI on the N150 distorts data.** If AI pre-processes or summarizes alerts before the desktop SOC sees them, the desktop AI reasons about another AI's interpretation — not the raw evidence. This compounds error and reduces analyst trust.

3. **17 of 27 Malcolm containers were idle theater.** Zeek, Arkime, Strelka, PCAP capture, file scanning, NetBox — all require a SPAN mirror port (managed switch) that doesn't exist. They consumed ~630MB RAM producing zero data.

4. **~9-10 hours were wasted** on problems that could have been avoided: LUKS passphrase not identified (4 incidents of "box won't boot"), NIC map fabricated without physical verification, external Filebeat dead end, repeated SSH key recovery.

## Decision

### The Ubuntu box (supportTAK-server) is a DATA LAYER ONLY.

It does three things:
1. **Collect:** Malcolm indexes raw IPFire syslog and Suricata EVE JSON into OpenSearch
2. **Archive:** Raw untouched logs written to external drive with SHA256 checksums (chain of custody)
3. **Serve:** Expose OpenSearch API (:9200) and ChromaDB corpus API (:8200) to the desktop SOC

It does NOT:
- Run AI inference (removed: Ollama, Foundation-Sec-8B)
- Run the firewall executor (removed: executor scaffold)
- Summarize, triage, or interpret data
- Modify raw events

### The desktop SOC (local-ai-soc) is the ANALYSIS LAYER.

All AI inference, detection, investigation, and recommendation generation happens on the desktop with GPU acceleration.

### Malcolm runs 27/27 containers (SPAN hardware acquired 2026-04-09).

> Originally 17 containers were disabled (no SPAN hardware). GS308EP managed switch
> and USB Ethernet adapter were acquired and deployed on 2026-04-09. All containers
> re-enabled with live capture on enx6c6e072d459d. Zeek and Suricata are now producing data.

## Active Malcolm Containers (10)

| Container | Purpose | Why Active |
|-----------|---------|-----------|
| opensearch | Event storage and search | Core — all data lives here |
| logstash | Parse and enrich incoming data | Core — processes EVE JSON and syslog |
| filebeat | Receive syslog on :5514, tail EVE JSON | Core — data ingestion |
| nginx-proxy | HTTPS frontend at :443, auth | Core — dashboard and API access |
| dashboards | OpenSearch Dashboards UI | Core — analyst visualization |
| dashboards-helper | Dashboard initialization and management | Required by dashboards |
| api | Malcolm REST API | Required for status and management |
| htadmin | Password management UI | Required for auth management |
| redis | Message queue | Required by logstash |
| redis-cache | Cache layer | Required by logstash |

## Disabled Malcolm Containers (17) — Require SPAN Hardware

| Container | Why Disabled | Re-enable When |
|-----------|-------------|----------------|
| zeek | No packet source | Managed switch + USB NIC |
| zeek-live | No live capture | Managed switch + USB NIC |
| suricata | Malcolm's own Suricata (we use IPFire's) | Managed switch + USB NIC |
| suricata-live | No live capture | Managed switch + USB NIC |
| arkime | PCAP viewer with no PCAPs | Managed switch + USB NIC |
| arkime-live | No live capture | Managed switch + USB NIC |
| pcap-capture | No SPAN port | Managed switch + USB NIC |
| pcap-monitor | Monitors empty directory | Managed switch + USB NIC |
| strelka-backend | File analysis with no files | PCAP extraction working |
| strelka-frontend | Strelka UI | PCAP extraction working |
| strelka-manager | Strelka orchestrator | PCAP extraction working |
| filescan | ClamAV/YARA with nothing to scan | PCAP extraction working |
| upload | PCAP upload handler | PCAP available |
| freq | Frequency analysis | Zeek DNS data available |
| keycloak | SSO — not configured, using basic auth | If SSO needed |
| netbox | Asset inventory — empty | Zeek conn.log populates it |
| postgres | NetBox database | NetBox active |

## Hardware Required for Full Malcolm (v3.0)

| Item | Cost | Enables |
|------|------|---------|
| Managed switch (Netgear GS308E) | ~$30 | SPAN mirror port |
| USB-A to GbE adapter | ~$14 | Dedicated capture NIC on GMKtec |
| UPS (APC BE600M1) | ~$65 | Prevents crash/reboot incidents |

## Removed Components

| Component | Was | Action Taken |
|-----------|-----|-------------|
| Ollama 0.9.2 | systemd service, 2 models (9.6GB) | Service disabled, models deleted |
| Foundation-Sec-8B Q4_K_M | 4.9GB GGUF model | Deleted via `ollama rm` |
| llama3:latest | 4.7GB model (unused) | Deleted via `ollama rm` |
| Ollama systemd override | OLLAMA_HOST, KEEP_ALIVE, CONTEXT_LENGTH | Override directory removed |
| Executor scaffold | localhost:8300, 6-gate validation | Service removed |

## What This Means for v2.0 Phases

| Phase | Original | Now |
|-------|----------|-----|
| Phase 9 (Malcolm) | 27 containers | 10 containers — 17 disabled |
| Phase 10 (Migration) | Unchanged | Unchanged — syslog + EVE paths still work |
| Phase 11 (AI Analyst) | Foundation-Sec-8B on N150 | **REMOVED** — desktop SOC handles all AI |
| Phase 12 (RAG Pipeline) | ChromaDB on N150 | ChromaDB API stays (lightweight, serves desktop) |
| Phase 13 (SOC Integration) | Executor on N150 | Executor removed — desktop SOC dispatches directly |
| Phase 14 (PCAP + Supply Chain) | PCAP deferred | Unchanged — still needs hardware |

## Lessons Learned

1. **Ask about hardware constraints before deploying.** LUKS encryption, available ports, switch capabilities — ask first, deploy second.
2. **State what's idle.** When deploying a multi-container system, explicitly list which containers are active vs. idle and what each needs to function.
3. **Don't put AI where compute is weak.** If a GPU desktop exists, AI goes there. A 16GB CPU box running Malcolm doesn't have room for LLM inference.
4. **Raw data to the analyst, not AI summaries.** Pre-processing with AI before the analyst sees data introduces distortion. The analyst (human or GPU-powered AI) should see raw events.
5. **Verify physical hardware before documenting.** Don't fabricate NIC maps, port assignments, or wiring diagrams without physically confirming them.

## Consequences

- Phase 11 (AI) and parts of Phase 13 (executor) are retracted as deployed-then-removed
- v2.0 milestone completion should document this pivot honestly
- ~9.6GB disk freed on N150, ~1.2GB RAM freed from stopped containers
- Desktop SOC becomes the single point of AI analysis — no split-brain architecture
