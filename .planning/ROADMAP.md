# Roadmap: Firewall Appliance

## Milestones

- [x] **v1.0 Firewall Appliance** — Phases 1-8 (shipped 2026-03-26)
- [ ] **v2.0 Local AI SOC** — Phases 9-14 (active)

## Phases

<details>
<summary>v1.0 Firewall Appliance (Phases 1-8) — SHIPPED 2026-03-26</summary>

- [x] Phase 1: Platform Foundation and Firewall (4/4 plans) — completed 2026-03-26
- [x] Phase 2: Core Network Services (3/3 plans) — completed 2026-03-26
- [x] Phase 3: SSH Hardening and Management Security (2/2 plans) — completed 2026-03-26
- [x] Phase 4: Suricata IDS/IPS (2/2 plans) — completed 2026-03-26
- [x] Phase 5: Telemetry Pipeline and Dashboards (4/4 plans) — completed 2026-03-25
- [x] Phase 6: System Hardening and Validation Suite (4/4 plans) — completed 2026-03-26
- [x] Phase 7: Reproducibility and Disaster Recovery (5/5 plans) — completed 2026-03-26
- [x] Phase 8: Milestone Gap Closure (3/3 plans) — completed 2026-03-26

</details>

### v2.0 Local AI SOC

- [ ] **Phase 9: Malcolm NSM Deployment** - Deploy Malcolm on supportTAK-server with heap tuning, storage policies, and Arkime disabled
- [ ] **Phase 10: Telemetry Migration to Malcolm** - Wire EVE JSON and syslog into Malcolm, run parallel validation, decommission Loki stack
- [ ] **Phase 11: Foundation-Sec-8B AI Analyst** - Install Ollama natively, load Foundation-Sec-8B Q4_K_M, benchmark N150 inference throughput
- [x] **Phase 12: RAG Knowledge Pipeline** - Build ChromaDB vector store, index operating corpus, validate retrieval quality (completed 2026-04-07)
- [ ] **Phase 13: Alert Triage Integration** - Wire triage worker to OpenSearch + RAG + AI analyst with async batch delivery
- [ ] **Phase 14: PCAP Investigation + Supply Chain** - Assess SPAN port feasibility, SBOM generation, and signed release artifacts

## Phase Details

### Phase 9: Malcolm NSM Deployment
**Goal**: Malcolm is running stably on supportTAK-server under the 16GB RAM constraint, accepting log data, with storage policies enforced before any data accumulates
**Depends on**: Nothing (first phase of v2.0)
**Requirements**: MAL-01, MAL-04, MAL-05, MAL-06
**Success Criteria** (what must be TRUE):
  1. All Malcolm Docker Compose containers report healthy status (`docker compose ps` shows no unhealthy or restarting containers)
  2. OpenSearch Dashboards are accessible at :5601 and display the Malcolm prebuilt dashboard set
  3. `free -m` on supportTAK-server shows OpenSearch JVM resident within 6GB heap boundary with Malcolm at steady state
  4. OpenSearch ISM policy is active and confirmed via Dashboards Index Management — 30-day max age rule applied to network-* indices
  5. Arkime container is present in Compose but not consuming RAM (disabled/commented) confirmed by `docker stats`
**Plans**: 2 plans
Plans:
- [ ] 09-01-PLAN.md — Install Malcolm with heap tuning, kernel params, swap, Arkime capture disabled, and start the stack
- [ ] 09-02-PLAN.md — Configure ISM retention policy, verify dashboards, run full validation suite

### Phase 10: Telemetry Migration to Malcolm
**Goal**: IPFire Suricata EVE JSON and syslog flow exclusively into Malcolm/OpenSearch, the Loki stack is decommissioned, and validation scripts reflect the new architecture
**Depends on**: Phase 9
**Requirements**: MAL-02, MAL-03, MIG-01, MIG-02, MIG-03, MIG-04
**Success Criteria** (what must be TRUE):
  1. Malcolm OpenSearch Dashboards show Suricata alert events with source IPs matching known IPFire traffic patterns — at least one live alert visible within 5 minutes of a test scan
  2. IPFire syslog entries (FORWARDFW, CUSTOMINPUT, GUARDIAN) appear in Malcolm Logstash-indexed OpenSearch indices
  3. Loki/Alloy/Grafana/Prometheus containers are stopped and removed; `docker ps` on supportTAK-server shows only Malcolm containers
  4. validate-phase5.sh (or its replacement) checks Malcolm endpoints and passes with no FAIL results
  5. Telemetry runbook accurately describes the Filebeat-to-Malcolm architecture — no references to Alloy, Loki, or SCP cron as active paths
**Plans**: 2 plans
Plans:
- [ ] 10-01-PLAN.md — Wire EVE JSON and syslog into Malcolm via Filebeat and rsyslog relay, verify parallel ingestion
- [ ] 10-02-PLAN.md — Decommission Loki stack, create validate-phase10.sh, rewrite telemetry runbook

### Phase 11: Foundation-Sec-8B AI Analyst
**Goal**: Foundation-Sec-8B Q4_K_M is running via Ollama on supportTAK-server with measured inference throughput documented, memory behavior validated, and the AI constrained to recommendations only
**Depends on**: Phase 9
**Requirements**: AI-01, AI-02, AI-03, AI-04
**Success Criteria** (what must be TRUE):
  1. `ollama run fdtn-ai/Foundation-Sec-8B-Q4_K_M` responds to a security question from the command line on supportTAK-server
  2. `llama-bench` output is documented with actual tokens/second on N150 CPU (result committed to repo as benchmark artifact)
  3. After 5 minutes of idle, model is unloaded from RAM — confirmed via `free -m` showing RAM recovered and `OLLAMA_KEEP_ALIVE=5m` in systemd override
  4. `free -m` with Malcolm at steady state and Ollama loaded simultaneously shows total usage under 15.5GB
**Plans**: 2 plans
Plans:
- [x] 11-01-PLAN.md — Install Ollama, apply security override (ADR-E02), pull Foundation-Sec-8B Q4_K_M, create validation script
- [ ] 11-02-PLAN.md — Run throughput benchmarks, measure RAM coexistence, document results, evaluate Phase 13 gate

### Phase 12: RAG Knowledge Pipeline
**Goal**: The operating corpus (ADRs, runbooks, validation results, control docs) is indexed in ChromaDB and RAG retrieval produces accurate, contextually relevant chunks validated by manual query testing
**Depends on**: Phase 11
**Requirements**: RAG-01, RAG-02, RAG-03, RAG-04
**Success Criteria** (what must be TRUE):
  1. ChromaDB is persisted on NVMe and survives a supportTAK-server reboot with corpus intact (collection count unchanged after restart)
  2. A query about a specific ADR decision returns the rationale section of that ADR as a top-3 retrieved chunk — no chunk splits mid-decision
  3. 10 manual security queries against the corpus all return chunks that contain the relevant technical content (not just keyword matches)
  4. Foundation-Sec-8B produces a coherent answer to a security question with RAG context injected — end-to-end pipeline confirmed working
**Plans**: 2 plans
Plans:
- [x] 12-01-PLAN.md — Install RAG Python environment, create ingestion + query scripts, index corpus into ChromaDB
- [x] 12-02-PLAN.md — Validate retrieval quality with 10 queries, end-to-end LLM test, reboot persistence check

### Phase 13: Alert Triage & SOC Integration
**Goal**: local-ai-soc (Windows desktop, RTX 5080) is connected to Malcolm (supportTAK-server) as the SOC analysis plane — alerts flow from Malcolm into the SOC Brain, are enriched with RAG context and GPU-accelerated AI triage (qwen3:14b), and recommendation artifacts can be dispatched to the firewall executor gate
**Depends on**: Phase 10, Phase 11, Phase 12
**Requirements**: TRI-01, TRI-02, TRI-03, TRI-04, TRI-05, TRI-06
**Success Criteria** (what must be TRUE):
  1. Malcolm OpenSearch API is accessible from the Windows desktop via authenticated HTTPS — `curl -sk -u admin:PASS https://192.168.1.22:9200/_cat/indices` returns index list
  2. local-ai-soc FirewallCollector pulls Suricata alerts from Malcolm OpenSearch — `GET /api/firewall/status` returns `{"status":"connected","enabled":true}` with events growing
  3. A Suricata alert ingested by Malcolm appears in the local-ai-soc Svelte dashboard Detections view with ATT&CK mapping and AI-generated summary (GPU inference via qwen3:14b)
  4. A recommendation artifact generated by local-ai-soc validates against `contracts/recommendation.schema.json` v1.0 and can be dispatched to the firewall executor gate contract
  5. Enriched triage results are written to both local-ai-soc DuckDB and Malcolm OpenSearch `triage-results-*` index
  6. End-to-end verified: trigger Suricata alert on IPFire → appears in Malcolm → pulled by SOC → investigated in Svelte UI → recommendation generated
**Plans**: TBD

### Phase 14: PCAP Investigation + Supply Chain
**Goal**: PCAP capture feasibility is formally assessed and documented, and the project produces signed SBOM artifacts on git tag that accurately represent the deployed v2.0 component set
**Depends on**: Phase 9 (for Arkime re-enable decision), all other phases complete for accurate SBOM
**Requirements**: PCAP-01, PCAP-02, PCAP-03, PCAP-04, SCA-01, SCA-02, SCA-03, SCA-04, SCA-05
**Success Criteria** (what must be TRUE):
  1. An ADR exists documenting the PCAP capture decision: either SPAN port hardware confirmed available and Arkime re-enabled with `ARKIME_FREESPACEG=15%`, or PCAP deferred with hardware requirements documented
  2. `syft dir:.` produces a CycloneDX JSON SBOM for the git repository (scope limitations documented in release notes)
  3. `syft packages /` run on supportTAK-server produces a second SBOM covering the deployed system state
  4. `grype sbom-repo.json` and `grype sbom-system.json` both complete without error and their output is attached to the release
  5. A git-tagged release bundle has a `.sigstore.json` cosign bundle alongside SHA256SUMS — `cosign verify-blob` succeeds against it
**Plans**: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Platform Foundation and Firewall | v1.0 | 4/4 | Complete | 2026-03-26 |
| 2. Core Network Services | v1.0 | 3/3 | Complete | 2026-03-26 |
| 3. SSH Hardening and Management Security | v1.0 | 2/2 | Complete | 2026-03-26 |
| 4. Suricata IDS/IPS | v1.0 | 2/2 | Complete | 2026-03-26 |
| 5. Telemetry Pipeline and Dashboards | v1.0 | 4/4 | Complete | 2026-03-25 |
| 6. System Hardening and Validation Suite | v1.0 | 4/4 | Complete | 2026-03-26 |
| 7. Reproducibility and Disaster Recovery | v1.0 | 5/5 | Complete | 2026-03-26 |
| 8. Milestone Gap Closure | v1.0 | 3/3 | Complete | 2026-03-26 |
| 9. Malcolm NSM Deployment | v2.0 | 0/2 | Planning complete | - |
| 10. Telemetry Migration to Malcolm | v2.0 | 0/2 | Planning complete | - |
| 11. Foundation-Sec-8B AI Analyst | v2.0 | 1/2 | In Progress|  |
| 12. RAG Knowledge Pipeline | v2.0 | 2/2 | Complete   | 2026-04-07 |
| 13. Alert Triage Integration | v2.0 | 0/- | Not started | - |
| 14. PCAP Investigation + Supply Chain | v2.0 | 0/- | Not started | - |
