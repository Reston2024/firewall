# Requirements: Firewall Appliance

**Defined:** 2026-03-31
**Core Value:** A secure, observable, AI-augmented network perimeter where threats are detected, triaged, and investigated locally

## v2.0 Requirements

Requirements for Local AI SOC milestone. Each maps to roadmap phases.

### Malcolm NSM Platform

- [ ] **MAL-01**: Malcolm Docker Compose stack deployed on supportTAK-server with heap-tuned OpenSearch (6GB) and Logstash (1GB) for 16GB RAM constraint
- [ ] **MAL-02**: Suricata EVE JSON from IPFire ingested into Malcolm via Filebeat with Suricata module
- [ ] **MAL-03**: IPFire syslog forwarded to Malcolm Logstash replacing the rsyslog→Alloy→Loki path
- [ ] **MAL-04**: OpenSearch ISM storage policy configured on first startup (hot→delete, 30-day max age) preventing silent disk exhaustion
- [ ] **MAL-05**: Malcolm prebuilt dashboards accessible and displaying live IPFire/Suricata data
- [ ] **MAL-06**: Arkime disabled until PCAP mirror hardware is available to prevent idle RAM consumption

### Telemetry Migration

- [ ] **MIG-01**: Parallel validation window (2-4 weeks) where both Loki and Malcolm ingest simultaneously
- [ ] **MIG-02**: Loki/Alloy/Grafana/Prometheus Docker Compose stack decommissioned after Malcolm validation
- [ ] **MIG-03**: validate-phase5.sh updated to check Malcolm endpoints instead of Loki/Grafana
- [ ] **MIG-04**: Telemetry runbook updated for Malcolm architecture (replaces Loki-era runbook)

### AI Security Analyst

- [x] **AI-01**: Ollama installed natively (not Docker) on supportTAK-server with Foundation-Sec-8B Q4_K_M model
- [x] **AI-02**: OLLAMA_KEEP_ALIVE=5m configured to unload model after idle periods, preventing permanent 5GB RAM pinning
- [ ] **AI-03**: llama-bench throughput benchmark run and documented to establish actual N150 tokens/second before triage pipeline design
- [x] **AI-04**: AI analyst produces recommendations only — no automated firewall rule changes or response actions

### RAG Knowledge Pipeline

- [x] **RAG-01**: ChromaDB embedded vector store initialized on supportTAK-server NVMe
- [x] **RAG-02**: all-MiniLM-L6-v2 embedding model deployed (~90MB) — Foundation-Sec-8B never used for embeddings
- [x] **RAG-03**: ADRs, runbooks, validation results, and control docs indexed with header-aware Markdown chunking (400-600 tokens, 10-15% overlap)
- [x] **RAG-04**: RAG retrieval validated with 10 manual queries against the corpus before production use

### Alert Triage

- [ ] **TRI-01**: Triage worker script queries OpenSearch for high-severity Suricata alerts via opensearch-py REST API
- [ ] **TRI-02**: Each alert enriched with RAG context from operating corpus and AI-generated summary including ATT&CK mapping
- [ ] **TRI-03**: Enriched triage results written to dedicated OpenSearch triage-results-* index (not polluting Malcolm's network data indices)
- [ ] **TRI-04**: Triage runs as async batch process (systemd timer), not synchronous blocking — designed for 3-8 tok/s CPU inference speed

### Supply Chain Assurance

- [ ] **SCA-01**: Syft generates CycloneDX JSON SBOM for the git repository
- [ ] **SCA-02**: Syft generates a second SBOM against the live deployed IPFire filesystem
- [ ] **SCA-03**: Grype vulnerability scan runs against generated SBOMs
- [ ] **SCA-04**: cosign v3 signs release bundles on git tag with --bundle flag
- [ ] **SCA-05**: Release process documented: tag → SBOM → Grype scan → cosign sign → evidence bundle

### PCAP Capture Investigation

- [ ] **PCAP-01**: Network hardware assessed for SPAN/mirror port capability (managed switch required)
- [ ] **PCAP-02**: If managed switch available, SPAN port configured to mirror IPFire traffic to supportTAK-server spare NIC
- [ ] **PCAP-03**: If SPAN available, Arkime re-enabled in Malcolm with ARKIME_FREESPACEG=15% disk guard
- [ ] **PCAP-04**: Decision documented (ADR) on PCAP capture feasibility and timeline

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
