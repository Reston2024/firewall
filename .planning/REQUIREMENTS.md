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
- [x] **MAL-06**: Arkime capture state consistent with SPAN posture — post-SPAN (GS308EP acquired 2026-04-09) Arkime + Zeek + Suricata live containers healthy; validate-phase9.sh MAL-06 accepts pre-SPAN and post-SPAN modes per updated ADR-E03

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
- [x] **TRI-05**: Executor gate contract defined — 6-gate sequence per ADR-E01, schema in contracts/execution-receipt.schema.json. Original scaffold at supportTAK :8300 retracted per ADR-E04; executor gate now owned by desktop SOC
- [~] **TRI-06**: Firewall-side rails complete and live-tested (validate-tri06.sh 3 PASS / 2 SKIP, write path proven via smoke test + reference emitter); desktop-side forwarder that emits real AI-generated receipts into triage-results-* tracked as v2.1 follow-up. See `.planning/phases/13-alert-triage-soc-integration/13-02-SUMMARY.md` and `docs/tri06-receipt-contract.md`

### Supply Chain Assurance

- [x] **SCA-01**: Syft 1.42.4 generates CycloneDX JSON SBOM for the git repository (`releases/v2.0.0/sbom-repo.json`)
- [x] **SCA-02**: Syft 1.42.4 generates CycloneDX JSON SBOM against the live deployed system, dpkg scope for memory safety (`releases/v2.0.0/sbom-system.json`, 5.1 MB, all Ubuntu 22.04 packages with CPE strings)
- [x] **SCA-03**: Grype 0.111.0 distro-aware vulnerability scan runs against both SBOMs (`releases/v2.0.0/grype-repo.txt`, `releases/v2.0.0/grype-system.txt`); findings disclosed in 14-02-SUMMARY per NIST SSDF audit-ship pattern (0 Critical, 68 High, 14,423 Medium, 990 Low, 280 Negligible)
- [x] **SCA-04**: Cosign v3.0.6 keyless Sigstore signature on `releases/v2.0.0/v2.0.0-bundle.tar.gz`, verifiable with `--certificate-identity-regexp='.+@.+\..+' --certificate-oidc-issuer-regexp='^https://.+/login/oauth$'`
- [x] **SCA-05**: Release process documented: generate-sbom.sh + docs/release-process.md

### PCAP Capture Investigation

- [x] **PCAP-01**: Network hardware assessed and acquired — Netgear GS308EP managed switch + USB 2.5GbE adapter deployed 2026-04-09 (ADR-E03 updated)
- [x] **PCAP-02**: SPAN port live — GS308EP Port 1 (IPFire GREEN uplink) mirrored to Port 5 (supportTAK USB adapter, NIC enx6c6e072d459d, promiscuous, no IP)
- [x] **PCAP-03**: Arkime + Zeek (2 workers) + Suricata live (2 threads) all healthy on supportTAK consuming SPAN mirror
- [x] **PCAP-04**: ADR-E03 updated 2026-04-09 documenting hardware acquisition and live-capture posture

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
| MAL-01 | Phase 9 | Complete |
| MAL-04 | Phase 9 | Complete |
| MAL-05 | Phase 9 | Complete |
| MAL-06 | Phase 9 | Complete (re-enabled with SPAN in Phase 14+) |
| MAL-02 | Phase 10 | Complete |
| MAL-03 | Phase 10 | Complete |
| MIG-01 | Phase 10 | Complete |
| MIG-02 | Phase 10 | Complete |
| MIG-03 | Phase 10 | Complete |
| MIG-04 | Phase 10 | Complete |
| AI-01 | Phase 11 | Removed (ADR-E04) |
| AI-02 | Phase 11 | Removed (ADR-E04) |
| AI-03 | Phase 11 | Removed (ADR-E04) |
| AI-04 | Phase 11 | Retained — enforced on desktop SOC |
| RAG-01 | Phase 12 | Complete (ChromaDB API at :8200) |
| RAG-02 | Phase 12 | Complete |
| RAG-03 | Phase 12 | Complete |
| RAG-04 | Phase 12 | Complete |
| TRI-01 | Phase 13 | Complete (OpenSearch :9200 LAN-exposed) |
| TRI-02 | Phase 13 | Complete (ChromaDB API serving desktop) |
| TRI-03 | Phase 13 | Complete (triage-results-* template created) |
| TRI-04 | Phase 13 | Complete (integration prompt delivered) |
| TRI-05 | Phase 13 | Complete (contract defined; supportTAK scaffold retracted per ADR-E04, gate on desktop SOC) |
| TRI-06 | Phase 13 | Partial — Firewall-side rails complete and live-tested; desktop-side forwarder tracked as v2.1 |
| PCAP-01 | Phase 14 | Complete (GS308EP + USB NIC acquired and deployed 2026-04-09) |
| PCAP-02 | Phase 14 | Complete (Port 1 → Port 5 mirror active) |
| PCAP-03 | Phase 14 | Complete (Arkime re-enabled, Zeek + Suricata live) |
| PCAP-04 | Phase 14 | Complete (ADR-E03 updated 2026-04-09) |
| SCA-01 | Phase 14 | Complete (syft 1.42.4 repo SBOM) |
| SCA-02 | Phase 14 | Complete (syft 1.42.4 system SBOM, dpkg scope for N150 memory) |
| SCA-03 | Phase 14 | Complete (grype 0.111.0 distro-aware scan, findings disclosed) |
| SCA-04 | Phase 14 | Complete (cosign 3.0.6 keyless Sigstore signature) |
| SCA-05 | Phase 14 | Complete (process documented) |

**Coverage (v2.0 closure 2026-04-10):**
- v2.0 requirements: 33 total
- Complete: 29 (27 from Phase 9-12 + SCA-01..04 + PCAP state corrections)
- Removed (ADR-E04): 3 (AI-01, AI-02, AI-03)
- Partial: 1 (TRI-06 — Firewall-side rails complete; desktop-side forwarder is v2.1 work tracked in audit)

---
*Requirements defined: 2026-03-31*
*Last updated: 2026-04-10 — v2.0 milestone closure (29/33 complete, 3 retracted, 1 partial)*
