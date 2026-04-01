# Architecture Research

**Domain:** Local AI SOC — IPFire + Malcolm NSM + Foundation-Sec-8B + RAG on constrained hardware
**Researched:** 2026-03-31
**Confidence:** HIGH (Malcolm data flows, RAM budget math); MEDIUM (RAG pipeline integration, AI triage workflow); LOW (Malcolm 16GB viability without degradation — untested at this exact hardware)

---

## Executive Summary

v2.0 pivots from a lightweight telemetry stack (Loki + Alloy + Grafana, ~500MB RAM) to a full NSM platform (Malcolm + OpenSearch, 16GB+ recommended) on the same 16GB supportTAK-server. This is the primary architectural constraint for the entire milestone.

**The RAM budget does not support running Malcolm and Foundation-Sec-8B simultaneously at full recommended specs.**

The viable path is a tiered memory strategy: Malcolm's OpenSearch heap is reduced to 6-8GB (below Malcolm's own "pleasant" 10GB floor), leaving ~5-6GB for the OS, other Malcolm containers, and on-demand AI inference. Foundation-Sec-8B must use Q4_K_M quantization (~4.9GB model weight + ~1GB context = ~6GB peak) and run as a dormant service that wakes on analyst request, not as a persistent always-on daemon. This trades peak performance for operational viability on existing hardware.

**IPFire on-box remains completely unchanged.** The only changes are on supportTAK-server (192.168.1.22) and the data path from IPFire to that server.

---

## System Overview

### v1.0 Architecture (Being Replaced)

```
┌──────────────────────────────────────────────────────────────────┐
│  IPFire Host (N100, 192.168.1.1)                                  │
│                                                                    │
│  /var/log/suricata/eve.json  ──── SCP cron (60s) ────────────►   │
│  /var/log/messages           ──── rsyslog UDP :514 ──────────►   │
└────────────────────────────────────────────────────────────────┬─┘
                                                                  │
                                                                  ▼
┌──────────────────────────────────────────────────────────────────┐
│  supportTAK-server (N150, 192.168.1.22, 16GB RAM)                │
│  Docker Compose                                                    │
│                                                                    │
│  [Alloy] → [Loki :3100]                                          │
│  [Grafana :3000]                                                   │
│  [Prometheus :9090] + [node-exporter]                            │
│                                                                    │
│  RAM used: ~500MB                                                 │
└──────────────────────────────────────────────────────────────────┘
```

### v2.0 Target Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  IPFire Host (N100, 192.168.1.1) — UNCHANGED                     │
│                                                                    │
│  Suricata → /var/log/suricata/eve.json                           │
│  iptables → /var/log/messages                                    │
│                                                                    │
│  Data delivery to Malcolm (two paths — see below):               │
│  Path A: SCP pull by Filebeat on supportTAK (replaces cron)      │
│  Path B: rsyslog UDP :514 syslog (unchanged, for iptables logs)  │
│                                                                    │
│  NO PCAP MIRROR REQUIRED for basic deployment                    │
│  (PCAP mirror via SPAN is optional; adds full packet fidelity)   │
└────────────────────────────────────────────────────────────────┬─┘
                                                                  │
                                                                  ▼
┌──────────────────────────────────────────────────────────────────┐
│  supportTAK-server (N150, 4 cores, 16GB RAM, 912GB NVMe)         │
│  Docker Compose — Malcolm + AI Stack                              │
│                                                                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  MALCOLM NSM (Docker Compose)                               │  │
│  │                                                             │  │
│  │  [Filebeat] → [Logstash :5044] → [OpenSearch :9200]        │  │
│  │  [Zeek]  ─────────────────────────────────────────┘        │  │
│  │  [Arkime session store]                                     │  │
│  │  [OpenSearch Dashboards :5601]                              │  │
│  │  [Malcolm upload UI :443]                                   │  │
│  │                                                             │  │
│  │  Heap tuning: OpenSearch -Xms6g -Xmx6g                     │  │
│  │              Logstash    -Xms1g -Xmx1g                     │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  AI ANALYST STACK (systemd-managed, NOT Docker)             │  │
│  │                                                             │  │
│  │  [llama-server] ← Foundation-Sec-8B-Q4_K_M.gguf            │  │
│  │      Port :8080, OpenAI-compatible REST API                 │  │
│  │      Loaded ON DEMAND; unloaded when idle                   │  │
│  │                                                             │  │
│  │  [ChromaDB] ← persistent vector store                      │  │
│  │      Indexes: ADRs, runbooks, validation results            │  │
│  │      Port :8000 (local only)                                │  │
│  │                                                             │  │
│  │  [RAG service] ← Python app (LangChain/LlamaIndex)         │  │
│  │      Queries ChromaDB, calls llama-server                   │  │
│  │      Port :8001 (local only)                                │  │
│  │                                                             │  │
│  │  [Triage worker] ← cron / event-driven Python              │  │
│  │      Polls OpenSearch for new high-severity alerts          │  │
│  │      Formats context + calls RAG service                    │  │
│  │      Writes findings to OpenSearch (custom index)           │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                    │
│  RAM budget (tight but viable):                                   │
│  OpenSearch JVM heap:     6 GB                                    │
│  Logstash JVM heap:       1 GB                                    │
│  Malcolm other containers:~1 GB (Zeek, Arkime, Filebeat, nginx)  │
│  OS + Docker overhead:    1.5 GB                                  │
│  llama-server (on demand):~6 GB (Q4_K_M + 4K context)           │
│  ChromaDB + RAG service:  ~0.5 GB                                 │
│  ─────────────────────────────────────────────────────────────   │
│  Malcolm-only peak:       ~9.5 GB  (within 16GB)                 │
│  Malcolm + AI peak:      ~15.5 GB  (fits, 0.5 GB headroom)      │
│  NOTE: AI must be dormant during heavy Malcolm indexing           │
└──────────────────────────────────────────────────────────────────┘
```

---

## Component Responsibilities

### New and Modified Components

| Component | Responsibility | Status | Implementation |
|-----------|----------------|--------|----------------|
| Malcolm (Docker Compose) | NSM platform — replaces Loki/Alloy/Grafana | NEW | CISA cisagov/Malcolm on Docker |
| OpenSearch (in Malcolm) | Index and store Zeek/Suricata/Arkime data | NEW | Malcolm-managed container |
| OpenSearch Dashboards (in Malcolm) | Network traffic visualization, alert dashboards | NEW | Malcolm-managed container, port :5601 |
| Zeek (in Malcolm) | Live PCAP analysis or log enrichment | NEW | Malcolm-managed container |
| Arkime (in Malcolm) | Full-session finder and PCAP playback | NEW | Malcolm-managed container |
| Logstash (in Malcolm) | Ingest pipeline — Filebeat beats input | NEW | Malcolm-managed container, port :5044 |
| Filebeat (on supportTAK) | Replace SCP cron — pull EVE JSON from IPFire, ship to Logstash | REPLACES cron | Native Filebeat .deb on supportTAK-server |
| llama-server (llama.cpp) | Local AI inference endpoint — Foundation-Sec-8B Q4_K_M | NEW | Compiled llama.cpp binary, systemd oneshot |
| ChromaDB | Vector store for RAG over ADRs/runbooks/docs | NEW | Python package or Docker (local only) |
| RAG service | Orchestrate retrieval + generation for analyst queries | NEW | Python (LangChain), local REST API |
| Triage worker | Poll OpenSearch for alerts, trigger AI triage, write findings | NEW | Python script, cron or systemd timer |
| Document indexer | Chunk and embed repo docs into ChromaDB | NEW | Python script, run on doc change |

### Unchanged Components

| Component | Status | Notes |
|-----------|--------|-------|
| IPFire firewall/routing/NAT | UNCHANGED | All native services untouched |
| Suricata IDS/IPS | UNCHANGED | EVE JSON at /var/log/suricata/eve.json — same file path |
| rsyslog UDP syslog forward | UNCHANGED | Still forwards /var/log/messages to supportTAK :514 |
| SSH management (192.168.1.100 only) | UNCHANGED | Access control unchanged |
| IPFire WUI (:444) | UNCHANGED | Management interface unchanged |
| Grafana + Loki + Alloy + Prometheus | REMOVED | Replaced by Malcolm |

---

## Data Flow Changes (v1.0 → v2.0)

### EVE JSON Delivery Path

**v1.0:**
```
IPFire: Suricata → /var/log/suricata/eve.json
                          ↓
        cron (60s): scp eve.json → supportTAK:/tmp/eve.json
                          ↓
        Alloy (file tail) → Loki → Grafana
```

**v2.0:**
```
IPFire: Suricata → /var/log/suricata/eve.json
                          ↓
        Filebeat (on supportTAK): SSH/SCP pull OR direct file tail via mount
                          ↓
        Logstash :5044 (Malcolm) → OpenSearch
                          ↓
        OpenSearch Dashboards (Malcolm) + Triage Worker
```

The SCP cron job is retired. Filebeat handles continuous log shipping with the Suricata module (native EVE JSON parser). Filebeat runs as a native systemd service on supportTAK-server, outside Malcolm's Docker network, so it can authenticate to IPFire via SSH key and pull the file (same key already exists from v1.0).

Alternative: If IPFire EVE JSON can be NFS-mounted or SFTP-accessible from supportTAK, Filebeat tails the remote file directly without the SCP intermediary. The SCP pull pattern is already proven from v1.0; keep it initially.

### Syslog Delivery Path

**v1.0 and v2.0 (unchanged):**
```
IPFire rsyslog → UDP :514 → supportTAK
```

In v2.0, Malcolm must be configured to accept rsyslog input (enabled during `./scripts/configure` by answering Y to "accept logs from forwarder"). Malcolm's Logstash listens on UDP :514 (or a configurable port). The iptables/firewall syslog data flows into OpenSearch alongside EVE JSON.

### PCAP Mirror (Optional Enhancement)

Malcolm's full power comes from live PCAP capture feeding Zeek + Arkime. Without a PCAP mirror, Malcolm operates in log-forwarding mode only (no Zeek enrichment of live traffic, no Arkime session replay). For v2.0 initial deployment, log-forwarding mode is sufficient and avoids hardware changes. PCAP mirror via SPAN port is documented as a Phase 4+ enhancement.

**If PCAP mirror is added later:**
```
Network switch SPAN port → dedicated NIC on supportTAK-server
                                    ↓
              Malcolm Zeek (live capture on that NIC)
                                    ↓
              Malcolm Arkime (session indexing)
                                    ↓
              OpenSearch (enriched sessions with protocol metadata)
```

This requires supportTAK-server to have a spare NIC available for passive tap use, or requires a managed switch with SPAN capability. The N150 hardware may have this capacity — validate during Phase 1.

### AI Triage Data Flow

```
OpenSearch (Malcolm) — new high-severity alerts
         ↓ (poll every N minutes via opensearch-py REST API)
Triage Worker (Python)
         ↓ (format alert context: src_ip, dst_ip, signature, category, protocol, timestamp)
RAG Service
         ├── ChromaDB query (semantic search over ADRs/runbooks/docs)
         │         returns: relevant context chunks (runbook references, known IOCs, ADR rationale)
         └── llama-server (Foundation-Sec-8B Q4_K_M)
                   prompt: alert context + retrieved runbook chunks
                   response: triage recommendation (investigate / likely FP / escalate)
         ↓
Write triage result to OpenSearch custom index (e.g., arkime_triage)
         ↓
OpenSearch Dashboards annotation or separate Triage panel
```

The AI model is called synchronously by the triage worker. llama-server is started on systemd oneshot before triage runs, then stopped after (to reclaim RAM for Malcolm). Alternatively, llama-server runs as a persistent low-priority service if the RAM budget proves stable in practice.

---

## RAM Budget Analysis

This is the critical constraint. All numbers are measured/documented values from official sources and community reports.

| Component | RAM Allocation | Source |
|-----------|---------------|--------|
| OpenSearch JVM heap (-Xmx6g) | 6.0 GB | Malcolm config, tuned below 10GB recommended |
| OpenSearch OS file cache (50% of JVM) | 3.0 GB | OpenSearch JVM sizing principle |
| Logstash JVM heap (-Xmx1g) | 1.0 GB | Malcolm config, reduced from 3-4GB default |
| Malcolm other containers (Zeek, Arkime, Filebeat, nginx, dashboards) | ~1.0 GB | Estimated from Malcolm container manifest |
| Ubuntu OS + Docker daemon | ~1.5 GB | Typical Ubuntu Server at rest |
| **Malcolm steady-state subtotal** | **~12.5 GB** | |
| Available for AI stack | **~3.5 GB** | |

**Problem:** Foundation-Sec-8B Q4_K_M needs ~6GB at inference time (4.9GB model + 1GB context + 0.1GB overhead). This exceeds the 3.5GB available.

**Resolution strategy (two options):**

**Option A — Scheduled AI (recommended for v2.0):**
Run triage analysis on a schedule (e.g., every 4 hours, overnight). Before triage: reduce OpenSearch heap to 4GB, pause Logstash. After triage: restore heap, restart Logstash. Complex to implement but stays on existing hardware.

**Option B — Trim Malcolm containers:**
Disable Arkime (PCAP session replay) if PCAP mirror is not in use. Arkime without a PCAP source consumes RAM but provides no value. With Arkime disabled: Malcolm steady-state drops to ~10GB, leaving 6GB for AI — workable.

**Option B is recommended for v2.0 initial deployment.** Arkime is only enabled once a PCAP mirror is configured. With Arkime disabled:

| Component | RAM |
|-----------|-----|
| OpenSearch JVM heap (-Xmx6g) | 6.0 GB |
| OpenSearch OS file cache | 3.0 GB |
| Logstash JVM heap (-Xmx1g) | 1.0 GB |
| Malcolm containers (no Arkime) | ~0.5 GB |
| Ubuntu OS + Docker | ~1.5 GB |
| **Malcolm steady-state (no Arkime)** | **~12.0 GB** |
| llama-server Q4_K_M (on demand) | ~6.0 GB |
| ChromaDB + RAG service | ~0.5 GB |
| **Peak (Malcolm + AI active)** | **~18.5 GB** | ← EXCEEDS 16GB |

Even with Arkime disabled, simultaneous operation exceeds 16GB. The only viable resolution without new hardware is to not run Malcolm and the AI stack simultaneously at peak:

**Final recommendation — Temporal separation:**
- Malcolm runs continuously, indexing all traffic (heap at 6GB)
- llama-server starts on-demand (systemd oneshot triggered by triage worker)
- Before llama-server starts: drop OpenSearch to 4GB heap (hot reload via API)
- After llama-server finishes: restore OpenSearch heap to 6GB
- Total simultaneous peak: 4 + 1 + 0.5 + 1.5 + 6 + 0.5 = ~13.5GB (fits in 16GB)

This requires tooling to hot-resize the OpenSearch heap or requires a service restart sequence. Document this as a known operational procedure, not a transparent background task.

**Confidence: LOW — real-world validation required.** Malcolm + reduced heap on 16GB is documented as "possible" by community reports but Malcolm's own docs warn against heaps below 10GB. Actual performance with this SOHO traffic volume (home network, not enterprise) may be acceptable.

---

## Architectural Patterns

### Pattern 1: Log-Forward Mode Before PCAP Mode

**What:** Deploy Malcolm accepting only forwarded logs (EVE JSON + syslog) before acquiring PCAP capability. Malcolm works in this mode and provides OpenSearch + Dashboards value without live packet capture.

**When to use:** v2.0 initial deployment — avoids SPAN port/switch configuration complexity and keeps the scope achievable.

**Trade-offs:** No Zeek enrichment of live traffic (Zeek only sees logs already parsed by Suricata), no Arkime session replay. OpenSearch Dashboards still provides alert visualization and threat hunting over indexed data.

### Pattern 2: On-Demand AI with Memory Guard

**What:** llama-server is a systemd oneshot service, not a persistent daemon. The triage worker script: (1) signals Malcolm to reduce OpenSearch heap, (2) starts llama-server, (3) runs triage, (4) stops llama-server, (5) signals Malcolm to restore heap.

**When to use:** Required given 16GB RAM constraint. This pattern allows both stacks to coexist on the same host without OOM risk.

**Trade-offs:** Latency: AI triage runs in batches (e.g., every 2-4 hours) rather than in real-time. Real-time triage requires hardware upgrade (32GB RAM) or a dedicated second host.

### Pattern 3: RAG Over Static Corpus

**What:** The RAG corpus (ADRs, runbooks, validation results, control docs) is indexed once at setup and re-indexed on document change (git commit hook or cron). ChromaDB persists embeddings to NVMe. The RAG service queries ChromaDB at triage time.

**When to use:** Always — the operating corpus is small (dozens of documents), changes infrequently, and benefits enormously from semantic retrieval rather than keyword search.

**Trade-offs:** Embeddings must be re-generated when documents change. Use a lightweight embedding model (all-MiniLM-L6-v2 at ~90MB) rather than the AI model itself for embedding, to keep the indexing pipeline fast and RAM-cheap.

### Pattern 4: OpenSearch as Integration Backbone

**What:** OpenSearch (within Malcolm) serves as the single source of truth for all security events AND triage outputs. The triage worker writes AI findings back to OpenSearch. Dashboards display both raw alerts and AI annotations in the same interface.

**When to use:** Preferred over a separate database for triage results — keeps the toolchain minimal and allows OpenSearch Dashboards to show correlated views of alerts + triage.

**Trade-offs:** Requires custom index mapping in OpenSearch for triage results. Risk: if triage worker writes malformed data, it could affect Malcolm's OpenSearch performance. Mitigate by writing to a separate index (e.g., `triage-results-*`) not shared with network data.

---

## Integration Points

### IPFire → Malcolm (Data Ingestion)

| Path | Method | What Flows | Notes |
|------|--------|------------|-------|
| EVE JSON | Filebeat SSH pull → Logstash :5044 | Suricata alerts, flows, DNS, HTTP | Replaces SCP cron; Filebeat Suricata module parses EVE natively |
| Syslog | rsyslog UDP :514 → Malcolm Logstash | iptables drop/accept events, system logs | Unchanged from v1.0; Malcolm must expose :514 during configure |
| PCAP (future) | SPAN port → passive NIC → Malcolm Zeek/Arkime | Full packet capture | Requires managed switch + spare NIC on supportTAK-server |

### Malcolm OpenSearch → AI Triage

| Interface | Method | Notes |
|-----------|--------|-------|
| Alert polling | opensearch-py REST API | Query arkime_sessions3-* index for high-severity events since last run |
| Triage write-back | opensearch-py PUT | Write to triage-results-YYYY.MM.DD index |
| Dashboard integration | OpenSearch Dashboards index pattern | Create index pattern for triage-results-* in dashboards |

### AI Analyst Stack Internal

| Boundary | Protocol | Notes |
|----------|----------|-------|
| Triage worker → llama-server | HTTP POST /completion (OpenAI-compatible) | localhost :8080; no auth needed (local only) |
| Triage worker → RAG service | HTTP POST (local) | localhost :8001 |
| RAG service → ChromaDB | Python SDK (in-process or HTTP) | localhost :8000 if separate service; in-process if embedded |
| RAG service → llama-server | HTTP POST /completion | Same llama-server endpoint |
| Document indexer → ChromaDB | Python SDK | Runs on git commit hook or manual trigger |

### Management Access (Unchanged)

| Boundary | Protocol | Notes |
|----------|----------|-------|
| Admin (192.168.1.100) → IPFire WUI | HTTPS :444 | Unchanged |
| Admin (192.168.1.100) → supportTAK SSH | SSH :22 | Unchanged |
| Admin → Malcolm Dashboards | HTTPS :443 (Malcolm nginx) | New — Malcolm exposes its own nginx reverse proxy |
| Admin → OpenSearch Dashboards | HTTPS :5601 (via Malcolm) | Malcolm manages auth |

---

## Build Order

Dependencies dictate this sequence. Do not reorder phases without re-validating prerequisites.

```
Phase 1: Malcolm Deployment
    Prerequisites: supportTAK-server accessible, Docker Compose v2 installed
    Deliverables:
      - Malcolm Docker Compose running (all containers healthy)
      - OpenSearch heap configured to 6GB (not default)
      - Logstash heap configured to 1GB
      - Malcolm configured to accept rsyslog :514 and Beats :5044
      - OpenSearch Dashboards accessible at :5601
    Why first: All subsequent components depend on OpenSearch being available.
               Malcolm's Logstash must be running before Filebeat can ship logs.

Phase 2: EVE JSON + Syslog Ingestion
    Prerequisites: Phase 1 complete, Filebeat installed on supportTAK-server
    Deliverables:
      - Filebeat Suricata module reading IPFire eve.json via SCP/SSH pull
      - EVE JSON events appearing in Malcolm OpenSearch
      - rsyslog UDP :514 syslog flowing into Malcolm
      - Malcolm dashboard showing alerts from IPFire Suricata
    Why second: Validates the core data flow before adding AI complexity.
                Confirms Malcolm is correctly receiving and indexing IPFire data.
    Decommission: After validation, remove old Loki/Alloy/Grafana stack

Phase 3: Foundation-Sec-8B Setup
    Prerequisites: Phase 2 complete, ~6GB headroom confirmed after Malcolm steady-state
    Deliverables:
      - llama.cpp compiled (or Ollama installed) on supportTAK-server
      - Foundation-Sec-8B-Q4_K_M.gguf downloaded and verified
      - llama-server starts, accepts /completion requests, returns valid JSON
      - RAM usage validated: Malcolm + llama-server fits within 16GB
    Why third: Validates the AI inference component before building the integration
               pipeline. Isolates any RAM/performance issues to a single variable.

Phase 4: RAG Pipeline
    Prerequisites: Phase 3 complete
    Deliverables:
      - ChromaDB installed and persistent (NVMe-backed)
      - Embedding model (all-MiniLM-L6-v2) available locally
      - Document indexer script ingesting ADRs, runbooks, docs/decisions/
      - RAG service querying ChromaDB and calling llama-server
      - End-to-end test: analyst question → retrieved context + AI answer
    Why fourth: RAG pipeline is independent of Malcolm; can be built and tested
                against synthetic security questions before wiring to live alerts.

Phase 5: Alert Triage Integration
    Prerequisites: Phase 4 complete, Phase 2 complete
    Deliverables:
      - Triage worker polling OpenSearch for new high-severity alerts
      - Triage worker formatting alert context and calling RAG service
      - Triage results written back to OpenSearch triage-results-* index
      - OpenSearch Dashboards index pattern for triage results visible
      - On-demand memory management: Malcolm heap reduction before AI start
    Why fifth: Requires both OpenSearch (Phase 2) and RAG service (Phase 4)
               to be independently validated before integration.

Phase 6: SBOM + Signed Releases
    Prerequisites: Phase 5 stable
    Deliverables:
      - SBOM generation (syft or trivy) for Malcolm Docker images
      - SBOM generation for llama.cpp binary and Python dependencies
      - Signed release artifacts (cosign or GPG) committed to repo
      - Release pipeline documented in docs/decisions/ as ADR
    Why last: Non-blocking for functionality. Can be done independently
              but is gated on all components being known and stable.

Phase 7: Broader Telemetry + Case Management (deferred)
    Prerequisites: Phase 5 stable, operational experience gathered
    Deliverables:
      - Endpoint telemetry (logs from GREEN zone hosts into Malcolm)
      - Auth log ingestion (SSH auth events from network devices)
      - Asset inventory integration (NetBox or simple YAML)
      - Alert-to-case workflow (manual or lightweight ticketing)
    Why deferred: Scope creep risk. Core SOC capability (Phases 1-5) must
                  be proven before expanding telemetry surface.
```

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Running Malcolm and AI Simultaneously Without Memory Guard

**What goes wrong:** Both OpenSearch (6GB heap + 3GB OS cache) and llama-server (~6GB) are resident simultaneously. System swaps to disk. Malcolm becomes unresponsive. OOM killer terminates containers. Data loss risk.

**Do this instead:** Implement the on-demand AI pattern (Pattern 2). Explicitly manage llama-server as a start/stop service. Never leave llama-server running unless triage is actively executing.

### Anti-Pattern 2: Using Q8_0 Quantization on 16GB Hardware

**What goes wrong:** Foundation-Sec-8B Q8_0 requires ~10.4GB at 8K context. Combined with even a reduced Malcolm stack, this consistently exceeds 16GB.

**Do this instead:** Use Q4_K_M (~4.9GB weights). Accuracy difference is measurable but acceptable for alert triage on an 8B model. Q4_K_M is the official recommendation from fdtn-ai for resource-constrained deployments.

### Anti-Pattern 3: Building the RAG Pipeline Before Malcolm Is Stable

**What goes wrong:** If OpenSearch is misconfigured or Malcolm containers are restarting, the triage worker cannot poll alerts, making the RAG integration impossible to test end-to-end.

**Do this instead:** Follow the build order strictly. Malcolm stable with live IPFire data (Phase 2) is the prerequisite gating Phase 5.

### Anti-Pattern 4: Running Malcolm in Full Default Configuration on 16GB

**What goes wrong:** Malcolm's default OpenSearch heap is set to half of system RAM (8GB), plus Logstash at 3-4GB, plus other containers. On 16GB, this exhausts available memory before any AI workload is added.

**Do this instead:** Edit `docker-compose.yml` before first start. Set `OPENSEARCH_JAVA_OPTS=-Xms6g -Xmx6g` and `LS_JAVA_OPTS=-Xms1g -Xmx1g`. Set `vm.max_map_count=262144` in sysctl. Monitor `free -h` during first 24 hours of operation.

### Anti-Pattern 5: Enabling PCAP Capture Without a SPAN Port

**What goes wrong:** If Zeek or Arkime are configured for live capture on an interface without mirrored traffic (e.g., the green0 management interface), they see only traffic to/from supportTAK-server itself, not the full GREEN zone traffic. This wastes CPU/RAM and produces misleading data.

**Do this instead:** Either deploy in log-forward mode only (Phase 2 baseline), or configure a proper SPAN port on the network switch before enabling live capture. Document which physical interface is the SPAN tap target.

### Anti-Pattern 6: Embedding with Foundation-Sec-8B

**What goes wrong:** Using the main AI model to generate RAG embeddings is RAM-prohibitive (model must be loaded twice — once for embedding, once for generation) and slow (8B model is far larger than needed for embedding).

**Do this instead:** Use a dedicated lightweight embedding model: `sentence-transformers/all-MiniLM-L6-v2` (~90MB). It runs on CPU in ~50-100ms per chunk, needs no GPU, and produces 384-dimensional vectors sufficient for semantic search over a corpus of dozens of documents.

---

## Scaling Considerations

This architecture is explicitly scoped to a single-server 16GB constraint. Scaling paths exist but require hardware.

| Concern | Current (16GB) | With 32GB RAM | With Dedicated AI Host |
|---------|----------------|---------------|------------------------|
| Malcolm + AI simultaneous | Not viable | Fully viable | Fully viable |
| Real-time alert triage | Not viable | Viable (streaming) | Viable (streaming) |
| PCAP mirror + Zeek enrichment | Adds ~1GB RAM load | Viable | Viable |
| Q8_0 model accuracy | Not viable | Viable | Viable |
| Concurrent analyst queries | 1 at a time | 2-4 with batching | Multiple |
| Full packet retention | Storage-limited (912GB NVMe) | Same | Same |

**Recommended upgrade path** if 16GB proves insufficient: Add a second DDR5 stick to the N150 (verify max RAM spec for N150 platform before purchase). The N150 SoC supports up to 32GB in most configurations. This doubles available RAM, makes Malcolm + AI simultaneous operation viable, and unlocks PCAP capture.

---

## Repo Structure Changes (v2.0)

```
/
├── docs/
│   ├── decisions/              # ADRs — new ADRs for Malcolm, AI stack, RAM budget decisions
│   ├── runbooks/               # NEW: operational runbooks (triage procedures, Malcolm restart)
│   └── zones.md                # Unchanged
│
├── firewall/                   # Unchanged (IPFire native configs)
│
├── telemetry/                  # REPLACES old Loki/Alloy/Grafana stack
│   ├── malcolm/
│   │   ├── docker-compose.yml  # Malcolm compose with tuned heap values
│   │   ├── env/                # Malcolm environment files (malcolm.env, etc.)
│   │   └── dashboards/         # Custom dashboard exports
│   └── filebeat/
│       └── filebeat.yml        # Suricata module config, IPFire SSH pull
│
├── ai/                         # NEW: AI analyst stack
│   ├── llama/
│   │   ├── setup.sh            # Download model, compile llama.cpp, create systemd unit
│   │   └── triage.service      # systemd oneshot unit for llama-server
│   ├── rag/
│   │   ├── indexer.py          # Document chunker and ChromaDB ingester
│   │   ├── rag_service.py      # Retrieval + generation service
│   │   └── requirements.txt    # langchain, chromadb, sentence-transformers, opensearch-py
│   └── triage/
│       ├── worker.py           # OpenSearch alert poller + triage orchestrator
│       └── triage.timer        # systemd timer for scheduled triage runs
│
├── scripts/
│   ├── validate-malcolm.sh     # NEW: verify Malcolm containers healthy, data flowing
│   ├── validate-ai.sh          # NEW: verify llama-server responds, RAG returns results
│   ├── memory-check.sh         # NEW: validate RAM budget before starting AI stack
│   └── rebuild.sh              # Updated for v2.0 component set
│
└── validation/
    └── test-results/           # Timestamped outputs from validate-*.sh
```

---

## Sources

- [Malcolm system requirements (official)](https://malcolm.fyi/docs/system-requirements.html) — 24GB min, 32GB recommended, 8 cores min
- [Malcolm live analysis documentation](https://malcolm.fyi/docs/live-analysis.html) — SPAN port, log-forward mode, Hedgehog profile
- [Malcolm upload and ingest documentation](https://malcolm.fyi/docs/upload.html) — Filebeat, rsyslog, SFTP ingest paths
- [cisagov/Malcolm GitHub](https://github.com/cisagov/Malcolm) — Docker Compose source, environment variable reference
- [Malcolm OpenSearch instances](https://cisagov.github.io/Malcolm/docs/opensearch-instances.html) — heap tuning, external OpenSearch
- [fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF (Hugging Face)](https://huggingface.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF) — Q4_K_M file size ~4.92GB
- [fdtn-ai/Foundation-Sec-8B-Q8_0-GGUF (Hugging Face)](https://huggingface.co/fdtn-ai/Foundation-Sec-8B-Q8_0-GGUF) — Q8_0 file size ~8.54GB
- [llama.cpp GitHub](https://github.com/ggml-org/llama.cpp) — server compilation, OpenAI-compatible API
- [llama.cpp GGUF VRAM requirements (LocalLLM.in)](https://localllm.in/blog/llamacpp-vram-requirements-for-local-llms) — Q4_K_M memory sizing
- [OpenSearch Docker heap sizing](https://docs.opensearch.org/latest/install-and-configure/install-opensearch/docker/) — JVM heap = 50% RAM rule
- [OpenSearch memory usage best practices (opster.io)](https://opster.com/guides/opensearch/opensearch-capacity-planning/memory-usage/) — heap + OS file cache sizing
- [ChromaDB local deployment](https://www.trychroma.com/) — persistent vector store, local-only
- [LangChain RAG with llama.cpp (MachineLearningMastery)](https://machinelearningmastery.com/building-a-rag-pipeline-with-llama-cpp-in-python/) — RAG pipeline pattern
- [sentence-transformers all-MiniLM-L6-v2](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2) — embedding model, ~90MB

---

*Architecture research for: Local AI SOC — Malcolm NSM + Foundation-Sec-8B + RAG on 16GB supportTAK-server*
*Researched: 2026-03-31*
*Supersedes: v1.0 architecture (IPFire + Loki/Alloy/Grafana), which remains valid for the IPFire on-box sections*
