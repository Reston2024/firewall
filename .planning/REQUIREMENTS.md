# Requirements: Firewall Appliance

**Defined:** 2026-03-31
**Core Value:** A secure, observable, AI-augmented network perimeter where threats are detected, triaged, and investigated locally

## v2.0 Requirements

Requirements for Local AI SOC milestone. Each maps to roadmap phases.

### Malcolm NSM Platform

- [x] **MAL-01**: Malcolm Docker Compose stack deployed on supportTAK-server with heap-tuned OpenSearch (6GB) and Logstash (2GB) for 16GB RAM constraint
- [x] **MAL-02**: Suricata EVE JSON from IPFire ingested into Malcolm via internal Filebeat (suricata-logs volume)
- [x] **MAL-03**: IPFire syslog forwarded to Malcolm via rsyslog relay → Filebeat syslog :5514
- [x] **MAL-04**: OpenSearch ISM storage policy configured (hot→delete, 30-day max age, covers network-*, arkime_sessions3-*, triage-results-*)
- [x] **MAL-05**: Malcolm prebuilt dashboards accessible at :443 with 53K+ Suricata alerts visible
- [x] **MAL-06**: Arkime disabled until PCAP mirror hardware is available (ADR-E03)

### Telemetry Migration

- [x] **MIG-01**: Parallel validation window confirmed — both Loki and Malcolm ingesting simultaneously before cutover
- [x] **MIG-02**: Loki/Alloy/Grafana/Prometheus Docker Compose stack decommissioned (containers + volumes removed)
- [x] **MIG-03**: validate-phase10.sh created checking Malcolm endpoints (replaces validate-phase5.sh)
- [x] **MIG-04**: Telemetry runbook fully rewritten for Malcolm architecture (55 Malcolm references, 0 Loki references)

### AI Security Analyst — RETRACTED per ADR-E04

> AI removed from supportTAK-server. All inference runs on desktop SOC (RTX 5080, qwen3:14b).
> These requirements were completed then retracted — retained for audit trail.

- [x] ~~**AI-01**: Ollama installed on supportTAK-server~~ → REMOVED (ADR-E04: desktop does this 30x faster)
- [x] ~~**AI-02**: OLLAMA_KEEP_ALIVE=5m configured~~ → REMOVED (Ollama deleted from N150)
- [x] ~~**AI-03**: Throughput benchmark documented — 2.47 tok/s~~ → RETAINED as docs/benchmarks/ (deprecated)
- [x] **AI-04**: AI analyst produces recommendations only — no automated firewall rule changes ← STILL VALID (enforced on desktop SOC)

### RAG Knowledge Pipeline

- [x] **RAG-01**: ChromaDB embedded vector store initialized on supportTAK-server NVMe
- [x] **RAG-02**: all-MiniLM-L6-v2 embedding model deployed (~90MB) — Foundation-Sec-8B never used for embeddings
- [x] **RAG-03**: ADRs, runbooks, validation results, and control docs indexed with header-aware Markdown chunking (400-600 tokens, 10-15% overlap)
- [x] **RAG-04**: RAG retrieval validated with 10 manual queries against the corpus before production use

### Alert Triage & SOC Integration

- [x] **TRI-01**: Malcolm OpenSearch API exposed to LAN at :9200 with TLS + internal auth — queryable from Windows desktop
- [x] **TRI-02**: ChromaDB RAG API at :8200 serving 387 chunks for alert enrichment — desktop SOC can query
- [x] **TRI-03**: triage-results-* index template created in OpenSearch with ISM retention policy
- [x] **TRI-04**: Integration prompt delivered to desktop SOC (local-ai-soc) with all endpoints and credentials
- [x] **TRI-05**: Firewall executor gate scaffold deployed at :8300 — 6-gate sequence per ADR-E01, returns execution receipts
- [ ] **TRI-06**: End-to-end verified: IPFire alert → Malcolm ingest → SOC pull → detect → investigate → recommend → receipt

### Supply Chain Assurance

- [ ] **SCA-01**: Syft generates CycloneDX JSON SBOM for the git repository (script ready, tools need install)
- [ ] **SCA-02**: Syft generates a second SBOM against the live deployed system (script ready)
- [ ] **SCA-03**: Grype vulnerability scan runs against generated SBOMs (script ready)
- [ ] **SCA-04**: cosign v3 signs release bundles on git tag with --bundle flag (script ready)
- [x] **SCA-05**: Release process documented: generate-sbom.sh + docs/release-process.md

### PCAP Capture Investigation

- [x] **PCAP-01**: Network hardware assessed — unmanaged switch lacks SPAN capability (ADR-E03)
- [ ] **PCAP-02**: SPAN port deferred to v3.0 — requires managed switch hardware (~$30-50)
- [ ] **PCAP-03**: Arkime deferred to v3.0 — requires SPAN port + USB NIC for capture
- [x] **PCAP-04**: Decision documented in ADR-E03 — PCAP deferred with hardware requirements

## v3.0 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Advanced AI

- **ADV-01**: Dedicated GPU acceleration for LLM inference (40-80+ tok/s)
- **ADV-02**: Multi-source threat intel RAG (MITRE STIX, NVD CVE feeds, ThreatFox IOC)
- **ADV-03**: Agentic multi-LLM orchestration with tool use
- **ADV-04**: DFIR-IRIS case management with formal incident tracking

### Advanced NSM

- **ADV-05**: community-id correlation enabling Zeek + Suricata join queries
- **ADV-06**: Broader telemetry ingestion (endpoint logs, auth logs, NetBox asset inventory)
- **ADV-07**: MITRE ATT&CK auto-mapping on all alerts
- **ADV-08**: DFIR-IRIS + n8n SOAR automation with human approval gates

### Infrastructure

- **ADV-09**: RAM upgrade to 32GB (resolves all RAM tension, unlocks Q8_0 and persistent model load)
- **ADV-10**: ChromaDB migration to OpenSearch k-NN plugin (eliminates dependency)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Real-time LLM analysis on every alert | N150 at 3-8 tok/s cannot sustain burst triage |
| Cloud LLM APIs as fallback | Defeats local-first value, exfiltrates network topology |
| Malcolm on IPFire host | IPFire rejects Docker; would destabilize data plane |
| LLM-generated automated firewall rules | Hallucination in response pipeline = outage risk |
| Qdrant vector database | Only needed beyond 100K vectors or with RBAC requirements |
| VPN server setup | Separate project, not core SOC |
| WiFi AP management | Handled by dedicated APs |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| MAL-01 | Phase 9 | Pending |
| MAL-04 | Phase 9 | Pending |
| MAL-05 | Phase 9 | Pending |
| MAL-06 | Phase 9 | Pending |
| MAL-02 | Phase 10 | Pending |
| MAL-03 | Phase 10 | Pending |
| MIG-01 | Phase 10 | Pending |
| MIG-02 | Phase 10 | Pending |
| MIG-03 | Phase 10 | Pending |
| MIG-04 | Phase 10 | Pending |
| AI-01 | Phase 11 | Complete |
| AI-02 | Phase 11 | Complete |
| AI-03 | Phase 11 | Pending |
| AI-04 | Phase 11 | Complete |
| RAG-01 | Phase 12 | Complete |
| RAG-02 | Phase 12 | Complete |
| RAG-03 | Phase 12 | Complete |
| RAG-04 | Phase 12 | Complete |
| TRI-01 | Phase 13 | Pending |
| TRI-02 | Phase 13 | Pending |
| TRI-03 | Phase 13 | Pending |
| TRI-04 | Phase 13 | Pending |
| PCAP-01 | Phase 14 | Pending |
| PCAP-02 | Phase 14 | Pending |
| PCAP-03 | Phase 14 | Pending |
| PCAP-04 | Phase 14 | Pending |
| SCA-01 | Phase 14 | Pending |
| SCA-02 | Phase 14 | Pending |
| SCA-03 | Phase 14 | Pending |
| SCA-04 | Phase 14 | Pending |
| SCA-05 | Phase 14 | Pending |

**Coverage:**
- v2.0 requirements: 31 total
- Mapped to phases: 31
- Unmapped: 0

---
*Requirements defined: 2026-03-31*
*Last updated: 2026-03-31 — traceability populated after v2.0 roadmap creation*
