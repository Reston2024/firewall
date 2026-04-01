# Project Research Summary

**Project:** Firewall Appliance — Local AI SOC v2.0
**Domain:** Home/SOHO network security — Malcolm NSM + Foundation-Sec-8B + RAG + SBOM on constrained hardware
**Researched:** 2026-03-31
**Confidence:** MEDIUM (hardware viability is the unresolved variable; all other major areas HIGH)

---

## Executive Summary

v2.0 pivots an already-operational IPFire firewall + telemetry system from a lightweight Loki/Grafana stack to a full NSM platform (Malcolm) with a local AI analyst (Foundation-Sec-8B via Ollama) and a RAG-backed knowledge layer. The defining characteristic of this project is a severe RAM constraint: the supportTAK-server (Intel N150, 16 GB RAM) is below Malcolm's documented 24 GB minimum. Every architectural decision in v2.0 flows from this single fact. The viable path is constrained JVM heap tuning (OpenSearch at 6 GB, Logstash at 1 GB), on-demand AI inference via `OLLAMA_KEEP_ALIVE=5m`, and temporal separation between bulk PCAP ingestion and AI triage sessions. Worst-case simultaneous peak usage lands at ~15.75 GB — technically fits but leaves minimal headroom for GC spikes or PCAP bursts.

The recommended approach is a phased deployment that validates each layer before wiring integrations together. Malcolm is deployed first with aggressive heap tuning and log-forwarding mode only (no live PCAP capture), replacing Loki as the EVE JSON consumer. Foundation-Sec-8B is then stood up independently to validate inference viability on N150 CPU speeds (estimated 3–8 tokens/second, LOW confidence — no N150-specific benchmarks exist). The RAG pipeline is built and tested in isolation before being wired into alert triage. SBOM + signed releases are a relatively independent supply chain feature that can be added in any phase. Live PCAP capture via a SPAN port is deferred to v2.x — it requires managed switch hardware and is the single highest-complexity infrastructure change.

The primary operational risk is OOM instability on the 16 GB host. Secondary risks are CPU inference speed making interactive triage impractical (batch-only design is mandatory), and OpenSearch disk growth consuming the 912 GB NVMe within weeks if storage policies are not configured from day one. The recommended hardware upgrade is adding a second DDR5 SO-DIMM to bring the N150 to 32 GB, which resolves all RAM tension and unlocks Q8_0 quantization and persistent model load. Until that upgrade, the architecture must treat Malcolm and the AI stack as temporally separated workloads.

---

## Key Findings

### Recommended Stack

The core stack for v2.0 is: Malcolm v26.02.0 (CISA-maintained Docker Compose NSM suite, ships OpenSearch 3.5.0 + Zeek 8.0.6 + Arkime), Ollama 0.18.2 (native install, not Docker) serving Foundation-Sec-8B Q4_K_M (4.92 GB, the only viable quantization on 16 GB), ChromaDB in embedded mode for the RAG vector store, sentence-transformers all-MiniLM-L6-v2 (~90 MB) for embeddings, LangChain 0.3.x as the orchestration layer, Syft 1.42.0 + Grype for SBOM, and cosign v3.x for artifact signing. Malcolm replaces the entire Loki/Alloy/Grafana/Prometheus stack — do not retain both simultaneously beyond a 2–4 week transition window.

**Core technologies:**
- **Malcolm v26.02.0**: Full NSM suite (Zeek, Arkime, OpenSearch, Logstash, Dashboards) — single Docker Compose deployment maintained by CISA; replaces Loki stack entirely
- **Ollama 0.18.2 (native)**: Local LLM inference server with `OLLAMA_KEEP_ALIVE=5m` — ~43 MB idle footprint; native install avoids Docker networking overhead and ~0.5 GB container overhead
- **Foundation-Sec-8B Q4_K_M**: Cybersecurity-domain LLM (Llama 3.1 8B, continued-pretrained on CVEs + ATT&CK + threat intel) — 4.92 GB disk, only viable quantization on 16 GB; Q8_0 (8.54 GB) is not viable
- **ChromaDB (embedded)**: Zero-server vector store for RAG corpus; migrate to OpenSearch k-NN plugin (already bundled in Malcolm's OpenSearch 3.5.0) in v2.x to eliminate the dependency
- **all-MiniLM-L6-v2**: Dedicated 22M-parameter embedding model (~90 MB); never use Foundation-Sec-8B for embeddings (RAM-prohibitive double-load)
- **Syft 1.42.0 + cosign v3.x**: SBOM generation (CycloneDX JSON) and keyless Sigstore signing — cosign v3 requires `--bundle` flag from day one; do not start with v2.x

**Critical version constraints:**
- cosign v3 breaking change: `--bundle` flag now required — commit to v3 from the start
- Malcolm manages its own OpenSearch 3.5.0 — do not install separately (doubles JVM heap to ~12 GB)
- Q8_0 Foundation-Sec-8B (8.54 GB) is not viable on 16 GB hardware alongside Malcolm

### Expected Features

Research distinguishes clearly between what Malcolm provides out-of-the-box (zero custom code) and what requires custom integration. Malcolm delivers: Zeek protocol metadata, Suricata alert indexing, Arkime PCAP investigation, GeoIP enrichment, JA4/JA3 TLS fingerprinting, file extraction + ClamAV/YARA scanning, NetBox asset inventory, and dozens of prebuilt OpenSearch dashboards. Custom integration is required for: IPFire EVE JSON delivery via Filebeat, Foundation-Sec-8B triage prompt templates, the RAG corpus ingestion pipeline, the alert triage worker, and SBOM generation scripts.

**Must have (table stakes for v2.0):**
- Malcolm deployed and ingesting traffic on supportTAK-server (heap-tuned before first start)
- Suricata EVE JSON from IPFire flowing into Malcolm via Filebeat
- Foundation-Sec-8B Q4_K_M running locally via Ollama
- RAG corpus indexed (ADRs, runbooks, validation results) with structure-aware chunking
- Alert triage script: high-severity alerts enriched with AI summary + ATT&CK mapping
- SBOM generated (Syft, CycloneDX JSON) and signed (cosign) on git tag
- Loki stack decommissioned after Malcolm validation

**Should have (differentiators, v2.x):**
- Network tap / SPAN port for Zeek live packet capture (requires managed switch)
- DFIR-IRIS case management (formal incident tracking with audit trail)
- community-id correlation enabling Zeek + Suricata join queries in OpenSearch
- Broader telemetry ingestion (endpoint logs, auth logs, NetBox asset inventory)
- MITRE ATT&CK auto-mapping on all alerts (requires triage pipeline to be proven first)

**Defer (v3+):**
- Dedicated GPU acceleration for LLM inference (moves from 3–8 t/s to 40–80+ t/s)
- Multi-source threat intel RAG (MITRE STIX, NVD CVE feeds, ThreatFox IOC)
- Agentic multi-LLM orchestration (N150 cannot sustain concurrent inference)
- DFIR-IRIS + n8n SOAR automation with human approval gates
- Qdrant replacing ChromaDB (only needed beyond 100K vectors or with RBAC requirements)

**Confirmed anti-features (explicitly not building):**
- Real-time LLM analysis on every alert — N150 at 3–8 t/s cannot sustain burst triage
- Cloud LLM APIs as fallback — defeats local-first value, exfiltrates network topology to third parties
- Malcolm on IPFire host — IPFire rejects Docker; would destabilize the data plane
- LLM-generated automated firewall rule changes — hallucination in response pipeline = outage risk; AI produces recommendations only

### Architecture Approach

The v2.0 architecture is a single-server deployment on supportTAK-server (192.168.1.22) where Malcolm's Docker Compose stack and a systemd-managed AI analyst stack coexist under a strict temporal separation model. IPFire (192.168.1.1) remains completely unchanged — it continues forwarding Suricata EVE JSON and syslog to supportTAK-server, now via Filebeat to Malcolm's Logstash instead of via SCP cron to Loki/Alloy. OpenSearch within Malcolm serves as the integration backbone: raw events flow in via Logstash, the triage worker reads alerts out via opensearch-py REST API, and AI-enriched triage results write back to a separate `triage-results-*` index visible in OpenSearch Dashboards.

**Major components:**
1. **Malcolm (Docker Compose)** — NSM platform: OpenSearch (6 GB heap), Logstash (1 GB heap), Zeek, Arkime (disabled initially), Filebeat, nginx; heap configured before first start; ISM storage policy and Arkime PCAP pruning configured on day one
2. **Ollama + Foundation-Sec-8B** (systemd, native) — On-demand AI inference; `OLLAMA_KEEP_ALIVE=5m` prevents permanent model residency; never left running during Malcolm indexing peaks
3. **ChromaDB + RAG service** (Python, local) — Persistent vector store on NVMe; all-MiniLM-L6-v2 for embeddings; LangChain orchestration; structure-aware Markdown chunking of ADRs/runbooks
4. **Triage worker** (Python, systemd timer) — Polls OpenSearch for high-severity alerts, formats context, calls RAG service, writes enriched results back to OpenSearch `triage-results-*` index
5. **Filebeat** (native systemd) — Replaces SCP cron; uses existing SSH key to pull IPFire EVE JSON; ships to Malcolm Logstash :5044 via Suricata module

**Key architectural patterns:**
- **Log-forward mode first**: Deploy Malcolm accepting EVE JSON + syslog before live PCAP; avoids SPAN port hardware complexity in v2.0
- **On-demand AI with memory guard**: Triage worker starts Ollama as needed; `OLLAMA_KEEP_ALIVE=5m` handles unload; temporal separation from peak Malcolm indexing is explicit operational policy
- **RAG over static corpus**: Corpus indexed once at setup, re-indexed on document change; ChromaDB persists to NVMe; all-MiniLM-L6-v2 is the embedding model (not Foundation-Sec-8B)
- **OpenSearch as integration backbone**: Single source of truth for both raw events and AI-enriched triage results; triage writes to a dedicated index to avoid polluting Malcolm's network data indices

### Critical Pitfalls

1. **Malcolm OOM on 16 GB RAM** — Set `OPENSEARCH_JAVA_OPTS=-Xms6g -Xmx6g` and `LS_JAVA_OPTS=-Xms1g -Xmx1g` before first start; disable Arkime until PCAP mirror is available; set `bootstrap.memory_lock=false` to prevent Docker allocation failure at startup; monitor `dmesg | grep -i oom` — OOM kills appear as silent container restarts with exit code 137, not as error logs

2. **OpenSearch disk fills in under 2–3 weeks with PCAP enabled** — Configure `OPENSEARCH_INDEX_SIZE_PRUNE_LIMIT` and `ARKIME_FREESPACEG=15%` on day one; create an ISM policy (hot→delete, 30-day max age) immediately after first startup; at 50–100 Mbps average throughput, 912 GB fills in under 2 weeks with full PCAP enabled — silent write-block causes event loss with no visible error

3. **Foundation-Sec-8B inference too slow for interactive triage** — N150 CPU produces 3–8 tokens/second; a 512-token response takes 1–3 minutes; design the triage workflow as async batch (submit alert → enrich in next scheduled cycle), not synchronous blocking call; run `llama-bench` after Phase 3 deployment to document actual throughput before designing latency SLOs

4. **PCAP capture requires unplanned network changes** — Malcolm's Zeek needs traffic mirrored from IPFire's data plane; supportTAK-server on GREEN only sees traffic to/from itself; SPAN port requires a managed switch; IPFire daemonlogger in soft-tap mode produces malformed packets per IPFire community; deploy in log-forwarding mode only for v2.0

5. **RAG chunking quality silently degrades answer quality** — Default fixed-size chunking (LangChain RecursiveCharacterTextSplitter, 1000 tokens) splits across ADR rationale sections; use header-aware Markdown chunking (split on `##`/`###`), target 400–600 tokens per chunk with 10–15% overlap, prepend document title + section path to each chunk before embedding; validate with 10 manual queries before declaring corpus production-ready

6. **Loki-to-Malcolm migration creates a telemetry dark period** — Historical Loki data cannot be migrated to OpenSearch (incompatible formats); document the data break explicitly in a decision log; archive last 7 days of EVE JSON before stopping Loki; plan a 30–60 minute maintenance window for cutover; keep Loki in read-only mode for 2–4 weeks in parallel if RAM permits

7. **SBOM is misleading for a shell-script-heavy repository** — Syft finds zero or minimal components in a bash/YAML/Markdown repo; generate two separate SBOMs: (a) repo source SBOM from `syft dir:.`, and (b) deployed system SBOM from `syft packages /` run on the live host post-install; document scope limitations in release notes

---

## Implications for Roadmap

Based on research, the architecture's dependency graph is unambiguous. Malcolm must exist before the triage pipeline can be built. The AI stack must be validated independently before integration. SBOM is fully independent and can be parallelized. Live PCAP capture is deferred to v2.x. Temporal separation between Malcolm and AI inference is a hard operational constraint, not an optimization.

### Phase 1: Malcolm Deployment + Memory Tuning

**Rationale:** Everything else depends on OpenSearch being available and stable. Malcolm heap misconfiguration is the most common single point of failure on constrained hardware and must be resolved before any other work begins. This phase also starts the Loki deprecation clock and must establish storage policies before any data accumulates.

**Delivers:**
- Malcolm Docker Compose stack running on supportTAK-server with all containers healthy
- OpenSearch heap at 6 GB, Logstash at 1 GB, `bootstrap.memory_lock=false`, Arkime disabled
- Malcolm configured to accept rsyslog :514 and Filebeat Beats :5044
- OpenSearch Dashboards accessible at :5601
- ISM policy and disk pruning configured (30-day retention, PCAP deletion enabled)
- `vm.max_map_count=262144` set in sysctl
- IPFire access controls (CUSTOMINPUT rules) restricting Malcolm ports to management subnet
- 4 GB swap (zram or disk) as OOM safety net

**Addresses from FEATURES.md:** Malcolm deployed and ingesting traffic (table stakes P1)

**Avoids from PITFALLS.md:** Malcolm OOM (Pitfall 1), OpenSearch disk fill (Pitfall 2), Malcolm API exposure on GREEN subnet (security mistake)

**Research flag:** STANDARD PATTERN — Malcolm Docker Compose deployment + heap tuning is fully documented in official docs and GitHub issue history; no per-phase research needed

---

### Phase 2: EVE JSON + Syslog Ingestion + Loki Decommission

**Rationale:** Validates the core data flow (IPFire → Malcolm) before any AI complexity is introduced. Confirms Malcolm correctly ingests and indexes IPFire Suricata data. Must happen before the triage worker can query OpenSearch for live alerts. The 2–4 week parallel validation window with Loki must be respected before decommission.

**Delivers:**
- Filebeat Suricata module on supportTAK-server pulling IPFire EVE JSON via existing SSH key
- EVE JSON events appearing in Malcolm OpenSearch Dashboards
- rsyslog UDP :514 syslog flowing into Malcolm Logstash
- Malcolm dashboard showing representative event counts matching known IPFire alert volume
- Loki data archived (last 7 days EVE JSON exported to flat files; decision log entry documenting data break)
- Loki/Alloy/Grafana/Prometheus stack decommissioned; RAM reclaimed

**Addresses from FEATURES.md:** EVE JSON flowing into Malcolm (table stakes), Loki decommission (P1)

**Avoids from PITFALLS.md:** Loki dark period (Pitfall 5); running both stacks indefinitely (exhausts 16 GB headroom)

**Research flag:** STANDARD PATTERN — Filebeat Suricata module + Malcolm Logstash Beats input is a documented Malcolm setup path with official examples

---

### Phase 3: Foundation-Sec-8B Setup + Inference Benchmarking

**Rationale:** Isolates the AI inference component validation before building any integration plumbing. RAM and performance unknowns on N150 must be characterized before designing a triage workflow with latency expectations. Inference speed determines whether the triage pipeline design is viable as planned. This phase has a hard stop: if measured throughput is below 2 t/s, the triage design requires revision before Phase 5 is planned.

**Delivers:**
- Ollama installed natively (not Docker) on supportTAK-server
- Foundation-Sec-8B Q4_K_M pulled and verified via `ollama run`
- `OLLAMA_KEEP_ALIVE=5m` and `OLLAMA_HOST=127.0.0.1:11434` configured via systemd override
- `llama-bench` results documented: actual tokens/second on N150 (both CPU-only and Vulkan if available)
- RAM budget validated: Malcolm steady-state + Ollama loaded simultaneously measured with `free -m`
- Triage workflow latency expectations documented based on measured throughput
- `--ctx-size 2048` and `--cram 0` or `--cram 64` as default llama-server startup flags

**Addresses from FEATURES.md:** Foundation-Sec-8B running via Ollama (table stakes P1), inference throughput baseline for triage design

**Avoids from PITFALLS.md:** Inference speed surprise (Pitfall 3); Q8_0 on 16 GB (Architecture Anti-Pattern 2); simultaneous Malcolm + AI without memory guard (Architecture Anti-Pattern 1)

**Research flag:** NEEDS VALIDATION — No N150-specific LLM benchmarks exist in public sources (LOW confidence on 3–8 t/s estimate); actual throughput must be measured post-deployment; triage latency SLOs cannot be set until this data exists

---

### Phase 4: RAG Pipeline

**Rationale:** The RAG corpus and retrieval layer is independent of Malcolm alert data and can be built and fully validated against synthetic security questions before being wired to live alerts. Chunking strategy must be designed and validated before ingesting the full corpus — rework after ingestion is expensive, and poor chunking silently degrades AI answer quality with no visible error signal.

**Delivers:**
- ChromaDB persistent on NVMe (`/var/lib/chromadb` or equivalent)
- all-MiniLM-L6-v2 embedding model pre-fetched locally (~90 MB, CPU inference)
- Structure-aware document indexer: splits on Markdown `##`/`###` headers, 400–600 token chunks, 10–15% overlap, contextual header prepended to each chunk (document title + section path)
- Full `.planning/` corpus + runbooks + ADRs ingested
- RAG service (LangChain 0.3.x, local REST API on :8001, localhost-only)
- 10-query manual validation of chunking quality: retrieved chunks must contain rationale, not just keywords; no chunk splits mid-decision
- End-to-end test: analyst security question → retrieved context chunks + Foundation-Sec-8B answer

**Addresses from FEATURES.md:** RAG corpus indexed and queryable (table stakes P1), RAG over ADRs and runbooks (differentiator)

**Avoids from PITFALLS.md:** RAG chunking quality degradation (Pitfall 6); embedding with Foundation-Sec-8B instead of dedicated embedding model (Architecture Anti-Pattern 6)

**Research flag:** STANDARD PATTERN for RAG mechanics (LangChain + ChromaDB + MiniLM is well-documented); project-specific work is chunking validation for this Markdown/shell-script corpus

---

### Phase 5: Alert Triage Integration

**Rationale:** Requires both Malcolm (Phase 2) and the RAG service (Phase 4) to be independently validated before joining them. The triage worker is the highest-complexity integration point — it touches OpenSearch, the RAG service, and writes back to a custom index. The on-demand memory management procedure (temporal separation of Malcolm indexing and AI inference) must be documented as an explicit operational SOP here.

**Delivers:**
- Triage worker (Python, systemd timer) polling OpenSearch for new high-severity Suricata alerts via opensearch-py
- Alert context formatting: src_ip, dst_ip, signature, category, protocol, timestamp → Foundation-Sec-8B prompt template
- RAG retrieval integrated: relevant ADR/runbook chunks injected into Foundation-Sec-8B context
- MITRE ATT&CK technique mapping appended to each enriched alert (TID + confidence)
- Triage results written to `triage-results-YYYY.MM.DD` index in OpenSearch (separate from Malcolm's network indices)
- OpenSearch Dashboards index pattern for `triage-results-*` visible to analyst
- Temporal separation SOP documented: never run triage worker during bulk PCAP ingestion windows

**Addresses from FEATURES.md:** Alert triage mechanism (table stakes P1), AI-enriched alert summaries (differentiator), ATT&CK mapping (differentiator P2)

**Avoids from PITFALLS.md:** Real-time LLM on every alert (anti-feature); automated response actions (anti-feature); concurrent Malcolm + AI without memory guard (Architecture Anti-Pattern 1)

**Research flag:** NEEDS RESEARCH — OpenSearch hot-resize heap API behavior under load; whether `OLLAMA_KEEP_ALIVE` cold-start latency (~15–20 seconds) is acceptable in the batch triage workflow or requires an alternative startup strategy

---

### Phase 6: SBOM + Signed Releases

**Rationale:** Non-blocking for SOC functionality; can be executed independently of Phases 1–5. Positioned last so the SBOM accurately reflects the final stable v2.0 component set. Supply chain deliverable required to declare the v2.0 milestone complete.

**Delivers:**
- Syft 1.42.0 + Grype installed on supportTAK-server
- cosign v3.x installed with `--bundle` flag used from the start
- Release script: git tag → `syft dir:. -o cyclonedx-json > sbom-repo.json` + `syft packages / > sbom-system.json`
- Both SBOMs signed: `cosign sign-blob SHA256SUMS --bundle SHA256SUMS.sigstore.json`
- Grype scan result attached to release notes
- ADR documenting SBOM scope limitations: repo SBOM covers source artifacts only; system SBOM covers deployed state at point in time; shell scripts + YAML have no package manifest — this is expected and documented
- cosign private key stored outside the repo (not committed)

**Addresses from FEATURES.md:** SBOM generated and signed on git tag (table stakes P1)

**Avoids from PITFALLS.md:** SBOM misleading for shell-script repo (Pitfall 7); signing key stored in repo (security mistake); cosign v2 migration debt

**Research flag:** STANDARD PATTERN — Syft + cosign workflow is fully documented via Anchore and Sigstore official documentation

---

### Phase Ordering Rationale

- Malcolm must precede all other phases — OpenSearch is the event source and triage write-back target; all subsequent phases depend on it being stable
- EVE JSON ingestion (Phase 2) must precede alert triage (Phase 5) — triage worker requires live alerts in OpenSearch
- Foundation-Sec-8B setup (Phase 3) must precede both RAG (Phase 4) and triage (Phase 5) — the LLM is the inference engine for both; throughput benchmarking must gate Phase 5 design
- RAG pipeline (Phase 4) must precede triage integration (Phase 5) — triage quality depends on retrieval augmentation
- SBOM (Phase 6) is fully independent and can be parallelized with any phase after Phase 1; positioned last to reflect the final component set
- Live PCAP capture / SPAN port intentionally omitted from v2.0 — requires managed switch hardware and carries network outage risk; belongs in a post-v2.0 iteration
- DFIR-IRIS intentionally deferred — add only after triage pipeline quality is proven through operational use; integration complexity without proven triage output is wasted effort

### Research Flags

**Phases needing `/gsd:research-phase` during planning:**
- **Phase 3:** N150-specific Ollama inference benchmarks do not exist in public sources; actual token/second throughput must be measured post-deployment; if below 2 t/s, triage workflow design requires revision before Phase 5 is planned
- **Phase 5:** OpenSearch hot-resize heap API behavior under production load; whether `OLLAMA_KEEP_ALIVE` cold-start (~15–20 s model load) is acceptable in batch triage or requires a different memory management strategy

**Phases with standard patterns (skip research-phase):**
- **Phase 1:** Malcolm Docker Compose deployment + heap tuning is fully documented in official Malcolm docs and GitHub issue history
- **Phase 2:** Filebeat Suricata module + Malcolm Logstash Beats :5044 integration is a documented Malcolm setup path
- **Phase 4:** LangChain + ChromaDB + all-MiniLM-L6-v2 RAG pattern is well-established; only corpus-specific chunking validation is project-specific
- **Phase 6:** Syft + cosign release pipeline is a standard Anchore/Sigstore documented workflow

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM-HIGH | Malcolm version and capabilities (HIGH); Foundation-Sec-8B Q4_K_M sizing (HIGH); RAG library choices (HIGH); N150 inference speed (LOW — no hardware-specific benchmarks) |
| Features | HIGH | Malcolm out-of-the-box capabilities verified via official docs; custom integration scope clearly delineated; Foundation-Sec-8B instruct variant confirmed via Cisco blog + HuggingFace |
| Architecture | MEDIUM | Data flow design (HIGH); RAM budget math (MEDIUM — documented heap guidance + community reports, not live measurement on this hardware); Malcolm 16 GB viability (LOW confidence until deployed) |
| Pitfalls | HIGH | Malcolm OOM and disk growth sourced from official Malcolm docs and GitHub issues; PCAP topology constraint from IPFire community; RAG chunking from Vectara NAACL 2025 research |

**Overall confidence:** MEDIUM

### Gaps to Address

- **N150 inference throughput:** No public benchmarks for Foundation-Sec-8B Q4_K_M on Intel N150 or comparable Alder Lake-N hardware. Must benchmark immediately after Phase 3 deployment. If actual throughput is below 2 t/s, the triage pipeline design requires revision (longer batch windows, shorter max response length, or hardware upgrade trigger).

- **Malcolm 16 GB RAM viability in practice:** The 15.75 GB worst-case simultaneous estimate has ~250 MB headroom, insufficient to absorb JVM GC spikes or PCAP bursts. Real-world stability on SOHO traffic volumes is undocumented at this exact RAM budget. Plan for a 2–4 week observation period with `docker stats` logging and `dmesg | grep -i oom` monitoring before declaring Phase 1 stable.

- **OpenSearch heap hot-resize behavior:** The temporal separation strategy assumes OpenSearch heap can be adjusted without a full Malcolm stack restart. Whether the OpenSearch Cluster Settings API supports live heap reduction in Docker on this Malcolm version needs validation during Phase 5.

- **N150 DDR5 upgrade ceiling:** The recommended "upgrade to 32 GB" path depends on verifying the specific N150 board's maximum supported RAM and SO-DIMM slot count before purchasing. Confirm before the 16 GB architecture is locked in long-term.

---

## Sources

### Primary (HIGH confidence)
- [Malcolm NSM Official Documentation](https://malcolm.fyi/docs/) — system requirements, configuration, capabilities, Filebeat integration, ISM index management
- [Malcolm GitHub (cisagov/Malcolm)](https://github.com/cisagov/Malcolm) — v26.02.0 release notes (Feb 19, 2026), Docker Compose environment variables, heap config
- [Malcolm GitHub Issue #204](https://github.com/cisagov/Malcolm/issues/204) — low RAM OOM guidance; heaps below 12 GB flagged as problematic
- [fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF (HuggingFace)](https://huggingface.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF) — official GGUF from model authors, 4.92 GB file size
- [Cisco Foundation-Sec-8B Blog](https://blogs.cisco.com/security/foundation-sec-cisco-foundation-ai-first-open-source-security-model) — benchmark claims, Apache 2.0 license, model lineage
- [Syft v1.42.0 (anchore/syft)](https://github.com/anchore/syft) — SBOM generation, CycloneDX JSON output, February 2026
- [Sigstore cosign v3 documentation](https://docs.sigstore.dev/quickstart/quickstart-cosign/) — `--bundle` flag requirement, keyless signing via Fulcio + Rekor
- [OpenSearch JVM heap sizing (Opster)](https://opster.com/guides/opensearch/opensearch-basics/opensearch-heap-size-usage-and-jvm-garbage-collection/) — 50% RAM rule, 10 GB minimum guidance
- [Malcolm Index Management](https://cisagov.github.io/Malcolm/docs/index-management.html) — ISM policy, PCAP pruning thresholds, `OPENSEARCH_INDEX_SIZE_PRUNE_LIMIT`
- [OpenSearch bootstrap.memory_lock Docker bug (GitHub #5865)](https://github.com/opensearch-project/OpenSearch/issues/5865) — Docker memory lock allocation failure

### Secondary (MEDIUM confidence)
- [Ollama FAQ](https://docs.ollama.com/faq) — OLLAMA_KEEP_ALIVE behavior, model memory management
- [Vectara NAACL 2025 RAG chunking study](https://blog.premai.io/rag-chunking-strategies-the-2026-benchmark-guide/) — 400–600 token sweet spot with 10–15% overlap
- [LangChain + ChromaDB + Ollama RAG pattern (DEV Community)](https://dev.to/sophyia/how-to-build-a-rag-solution-with-llama-index-chromadb-and-ollama-20lb) — standard RAG implementation reference
- [Vector Database Comparison 2026 (4xxi)](https://4xxi.com/articles/vector-database-comparison/) — ChromaDB vs. Qdrant for small corpus use cases
- [Ollama 0.18.2 Ubuntu March 2026 deployment guide](https://rafftechnologies.com/learn/tutorials/deploy-open-webui-ollama-ubuntu-24-04) — version confirmation
- [Anchore SBOM Guide — Syft + Grype workflow](https://anchore.com/sbom/how-to-generate-an-sbom-with-free-open-source-tools/) — two-SBOM pattern for infrastructure repos

### Tertiary (LOW confidence, requires live validation)
- Intel Iris Xe Vulkan benchmarks — [llama.cpp discussion #10879](https://github.com/ggml-org/llama.cpp/discussions/10879) showing ~10.58 t/s tg128 for 7B Q4_0; basis for N150 inference estimate; treat as order-of-magnitude only (different microarchitecture)
- Malcolm 16 GB community anecdotes — "possible but painful" reports without reproducible configs at exactly 16 GB with simultaneous AI stack; real-world stability unconfirmed

---

*Research completed: 2026-03-31*
*Supersedes: 2026-03-21 SUMMARY.md (v1.0 IPFire + Loki telemetry research)*
*Ready for roadmap: yes*
