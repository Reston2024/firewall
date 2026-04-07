---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Local AI SOC
status: unknown
stopped_at: "Checkpoint: supportTAK-server did not come back after reboot — requires physical intervention. 10/10 queries pass, RAG-04 end-to-end confirmed, reboot persistence test blocked."
last_updated: "2026-04-07T03:18:25.665Z"
progress:
  total_phases: 6
  completed_phases: 4
  total_plans: 8
  completed_plans: 8
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-31)

**Core value:** A secure, observable, AI-augmented network perimeter where threats are detected, triaged, and investigated locally
**Current focus:** Phase 12 — rag-knowledge-pipeline

## Current Position

Phase: 12 (rag-knowledge-pipeline) — EXECUTING
Plan: 2 of 2

## Performance Metrics

**Velocity (v2.0):**

- Total plans completed: 0
- Average duration: —
- Total execution time: 0 hours

**By Phase (v2.0):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 9 - Malcolm NSM Deployment | 2 | 210 min | 105 min |
| 10 - Telemetry Migration | - | - | - |
| 11 - Foundation-Sec-8B AI Analyst | - | - | - |
| 12 - RAG Knowledge Pipeline | - | - | - |
| 13 - Alert Triage Integration | - | - | - |
| 14 - PCAP + Supply Chain | - | - | - |

*Updated after each plan completion*
| Phase 11 P01 | 27 | 2 tasks | 2 files |
| Phase 12 P01 | 47 | 2 tasks | 3 files |
| Phase 12 P02 | 105 | 1 tasks | 1 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v2.0 architecture]: Malcolm replaces Loki/Alloy/Grafana/Prometheus entirely — do not retain both stacks beyond 2-4 week parallel validation window
- [v2.0 architecture]: Foundation-Sec-8B Q4_K_M is the only viable quantization on 16GB RAM alongside Malcolm — Q8_0 (8.54GB) not viable
- [v2.0 architecture]: Ollama installed natively (not Docker) to avoid ~0.5GB container overhead and Docker networking complexity
- [v2.0 architecture]: Arkime disabled until managed switch SPAN port hardware is available — prevents idle RAM consumption with no data source
- [v2.0 architecture]: Temporal separation is an explicit operational policy — never run AI triage during peak Malcolm indexing windows
- [v2.0 architecture]: AI analyst produces recommendations only — no automated firewall rule changes (hallucination in response pipeline = outage risk)
- [v2.0 architecture]: ChromaDB embedded mode on NVMe — migrate to OpenSearch k-NN plugin (bundled in Malcolm's OpenSearch 3.5.0) in v3.0
- [v2.0 architecture]: all-MiniLM-L6-v2 is the embedding model — never use Foundation-Sec-8B for embeddings (RAM-prohibitive double-load at 16GB)
- [v2.0 architecture]: cosign v3 with --bundle flag from day one — do not start with v2.x to avoid migration debt
- [Phase 11 gate]: If llama-bench measures below 2 t/s on N150, triage pipeline design requires revision before Phase 13 is planned
- [Phase 11]: OLLAMA_CONTEXT_LENGTH=2048 added to systemd override to reduce KV cache RAM footprint for Malcolm coexistence
- [Phase 11]: UFW deny rule for port 11434 configured but UFW is inactive on supportTAK-server; primary ADR-E02 control is 127.0.0.1 binding which works correctly
- [Phase 11]: Temporal separation confirmed required in practice: Foundation-Sec-8B needs 5.4GB, Malcolm uses 12-14GB of 16GB — simultaneous load requires pausing OpenSearch/Logstash
- [Phase 12]: langchain_community.vectorstores.Chroma used instead of langchain-chroma: no version of langchain-chroma bridges chromadb 0.6.3 + langchain 0.3.x (1.x requires chromadb 1.x; 0.1.x requires chromadb<0.6.0)
- [Phase 12]: chromadb 0.6.3 pinned confirmed correct; 1.x uses ONNX internal embeddings incompatible with HuggingFaceEmbeddings pattern
- [Phase 12]: Use openai client directly for Foundation-Sec-8B queries: langchain_community.chat_models.ChatOllama returns empty content in chromadb 0.6.3 + langchain 0.3.x venv; openai client confirmed working with 1125-char coherent responses
- [Phase 12]: Chunk context limit set to 400 chars in query_with_llm: 600-char limit causes prompt to overflow OLLAMA_CONTEXT_LENGTH=2048 with 3 chunks + template overhead; 400-char confirmed working

### Key RAM Budget (supportTAK-server 16GB)

| Component | Resident RAM |
|-----------|-------------|
| Malcolm OpenSearch JVM heap | 6.0 GB |
| Malcolm Logstash JVM heap | 1.0 GB |
| Malcolm other containers (Zeek, Filebeat, nginx) | ~1.5 GB |
| Ubuntu OS baseline | ~1.5 GB |
| Foundation-Sec-8B Q4_K_M (loaded) | ~5.5 GB |
| Worst-case simultaneous | ~15.5 GB |
| Headroom | ~0.5 GB |

Temporal separation between Malcolm indexing peaks and AI triage is mandatory — not an optimization.

### Research Flags

- **Phase 11 (needs validation):** No N150-specific llama-bench results exist in public sources; 3-8 t/s is an order-of-magnitude estimate from different hardware; actual throughput gates Phase 13 design
- **Phase 13 (needs validation):** OpenSearch heap hot-resize API behavior under production load; OLLAMA_KEEP_ALIVE cold-start (~15-20s) acceptability in batch triage workflow
- **Phase 9 (standard pattern):** Malcolm Docker Compose + heap tuning is fully documented in official docs and GitHub issue history
- **Phase 10 (standard pattern):** Filebeat Suricata module + Malcolm Logstash Beats :5044 is a documented Malcolm setup path
- **Phase 12 (standard pattern):** LangChain + ChromaDB + all-MiniLM-L6-v2 RAG is well-established; only corpus-specific chunking validation is project-specific
- **Phase 14 (standard pattern):** Syft + cosign release pipeline is documented via Anchore and Sigstore official docs

### Pending Todos

- Run `docker stats` and `dmesg | grep -i oom` logging during Phase 9 — 2-4 week observation period before declaring Malcolm stable
- Verify N150 board maximum RAM and SO-DIMM slot count before committing long-term to 16GB architecture
- Arkime re-enable decision deferred to Phase 14 — depends on managed switch SPAN port hardware availability

### Blockers/Concerns

- Malcolm 16GB RAM viability: worst-case 15.5GB leaves ~500MB headroom insufficient for JVM GC spikes; plan observation period post-Phase 9 deployment
- N150 inference throughput: no public benchmarks; if measured below 2 t/s in Phase 11, Phase 13 triage design requires revision (longer batch windows, shorter max response length, or hardware upgrade trigger)
- PCAP capture: requires managed switch hardware not currently confirmed available — Phase 14 scopes assessment, not guaranteed delivery

## Session Continuity

Last session: 2026-04-07T03:18:25.658Z
Stopped at: Checkpoint: supportTAK-server did not come back after reboot — requires physical intervention. 10/10 queries pass, RAG-04 end-to-end confirmed, reboot persistence test blocked.
Resume file: None
Next action: `/gsd:plan-phase 10` — Data Ingestion & Loki Migration
