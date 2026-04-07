---
phase: 12-rag-knowledge-pipeline
plan: 01
subsystem: infra
tags: [rag, chromadb, langchain, sentence-transformers, all-MiniLM-L6-v2, vector-store, embeddings, python, nlp]

# Dependency graph
requires:
  - phase: 11-foundation-sec-8b-ai-analyst
    provides: Foundation-Sec-8B installed at /opt/ollama (Ollama) on supportTAK-server
provides:
  - Python venv at /opt/rag with chromadb 0.6.3 + langchain 0.3.x + sentence-transformers 3.x
  - ChromaDB at /var/lib/chromadb with 387 chunks from ADRs/runbooks/contracts/benchmarks
  - scripts/rag_index.py: corpus ingestion with two-stage Markdown chunking and breadcrumb prepend
  - scripts/rag_query.py: query_corpus() function callable by Phase 13 triage worker (k=3 default)
  - scripts/validate-phase12.sh: RAG-01 through RAG-04 validation suite
affects:
  - 13-alert-triage-integration (will import query_corpus from rag_query.py)
  - future-rag-upgrades (documents chromadb 0.6.3 + langchain-community.vectorstores.Chroma compatibility)

# Tech tracking
tech-stack:
  added:
    - chromadb 0.6.3 (PersistentClient, SQLite-backed vector store at /var/lib/chromadb)
    - langchain 0.3.28 (RAG orchestration)
    - langchain-community 0.3.28 (HuggingFaceEmbeddings, Chroma vectorstore adapter)
    - langchain-text-splitters 0.3.11 (MarkdownHeaderTextSplitter, RecursiveCharacterTextSplitter)
    - sentence-transformers 3.4.1 (all-MiniLM-L6-v2 CPU embedding model)
    - openai 1.x (OpenAI-compatible client for Ollama, used in RAG-04 end-to-end test)
    - tiktoken (token counting support)
  patterns:
    - Two-stage Markdown chunking: MarkdownHeaderTextSplitter (at #/##/### boundaries) then RecursiveCharacterTextSplitter (1800 chars/200 overlap)
    - Breadcrumb prepend: "[source_path] / # h1 / ## h2 / ### h3" on every chunk for source attribution
    - Shell scripts routed through RecursiveCharacterTextSplitter only (skip Markdown header splitter)
    - HF_HUB_OFFLINE=1 set before imports to block network calls during indexing
    - query_corpus() exported function with k=3 default (fits OLLAMA_CONTEXT_LENGTH=2048 constraint)

key-files:
  created:
    - scripts/rag_index.py
    - scripts/rag_query.py
    - scripts/validate-phase12.sh
  modified: []

key-decisions:
  - "Use langchain_community.vectorstores.Chroma (deprecated adapter) instead of langchain-chroma: langchain-chroma 1.x requires chromadb 1.x, langchain-chroma 0.1.x requires chromadb<0.6.0; no version bridges langchain 0.3.x + chromadb 0.6.3 except the deprecated community adapter which works correctly"
  - "chromadb 0.6.3 stays pinned — confirmed working; 1.x uses ONNX-based internal embeddings (different from sentence-transformers) and is not compatible with our HuggingFaceEmbeddings pattern"
  - "387 chunks indexed (expected 150-300); higher than estimated due to .planning/research/SUMMARY.md and STACK.md being larger than anticipated"

patterns-established:
  - "RAG query pattern: from scripts.rag_query import query_corpus; chunks = query_corpus(question, k=3)"
  - "Validation pattern: bash scripts/validate-phase12.sh (quick) | bash scripts/validate-phase12.sh --full (end-to-end)"
  - "Re-indexing is idempotent: rag_index.py uses deterministic chunk IDs and Chroma.add_texts() upserts safely"

requirements-completed: [RAG-01, RAG-02, RAG-03]

# Metrics
duration: 47min
completed: 2026-04-07
---

# Phase 12 Plan 01: RAG Knowledge Pipeline Summary

**ChromaDB 0.6.3 vector store with 387 chunks of ADRs/runbooks/contracts/benchmarks indexed on NVMe, all-MiniLM-L6-v2 CPU embeddings offline, query_corpus() interface returning k=3 chunks for Phase 13 triage**

## Performance

- **Duration:** 47 min (dominated by pip install and indexing on CPU)
- **Started:** 2026-04-07T01:24:44Z
- **Completed:** 2026-04-07T01:28:31Z
- **Tasks:** 2
- **Files created:** 3

## Accomplishments

- Python venv at `/opt/rag` on supportTAK-server with chromadb 0.6.3 pinned and all dependencies installed
- Corpus of 44 files (ADRs, runbooks, contracts, benchmarks, planning artifacts, validation scripts) indexed into ChromaDB as 387 chunks using two-stage Markdown header + character splitting
- `query_corpus()` function confirmed returning ADR-E02 chunks for Ollama localhost query (score 0.32) and ADR-0007 chunks for Suricata monitor mode query — semantically correct retrieval
- `validate-phase12.sh` passes 10/10 checks (RAG-01, RAG-02, RAG-03) in quick mode; RAG-04 gated behind `--full`

## Task Commits

Each task was committed atomically:

1. **Task 1: Install RAG Python environment and create ingestion + query scripts** - `72fb9a4` (feat)
2. **Task 2: Create validate-phase12.sh validation suite** - `20ddfc0` (feat)

## Files Created

- `scripts/rag_index.py` (228 lines) — corpus ingestion: two-stage chunking, breadcrumb prepend, batch upsert to ChromaDB, persistence verification
- `scripts/rag_query.py` (127 lines) — `query_corpus(question, k=3)` function + CLI with `--k` override; exports function for Phase 13 import
- `scripts/validate-phase12.sh` (321 lines) — RAG-01 through RAG-04 validation suite; SSHes to supportTAK-server for each check

## Decisions Made

1. **Use `langchain_community.vectorstores.Chroma` instead of `langchain_chroma.Chroma`:** No version of `langchain-chroma` is compatible with both chromadb 0.6.3 and langchain 0.3.x. The `langchain-chroma` package has been fragmented across two incompatible API generations (0.x pins chromadb<0.6.0; 1.x requires chromadb>=1.0.20). The deprecated `langchain_community.vectorstores.Chroma` adapter works correctly with chromadb 0.6.3 and langchain 0.3.x.

2. **chromadb 1.5.5 rejected despite working PersistentClient:** Testing showed chromadb 1.5.5's `PersistentClient` still functions, but its internal embedding model (ONNX-based all-MiniLM-L6-v2) is incompatible with our `HuggingFaceEmbeddings` + `sentence-transformers` pattern. Staying on 0.6.3 maintains the proven architecture.

3. **387 chunks (above expected 150-300):** The `.planning/research/SUMMARY.md` and `STACK.md` files are larger than the research document estimated. All chunks are below 2200 chars; quality checks pass.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] langchain-chroma 1.1.0 is incompatible with chromadb 0.6.3 AND langchain 0.3.x simultaneously**
- **Found during:** Task 1 (Install RAG Python environment)
- **Issue:** Research document stated "langchain-chroma 1.1.0 pins chromadb<0.7.0" — this was incorrect as of April 2026. langchain-chroma 1.1.0 actually requires langchain-core>=1.1.3 (1.x series), which is incompatible with langchain 0.3.x (uses langchain-core 0.3.x). Additionally, `langchain-chroma 0.1.x` requires `chromadb<0.6.0` so it cannot be used with chromadb 0.6.3 either.
- **Fix:** Used `langchain_community.vectorstores.Chroma` (the deprecated-but-working community adapter) which bridges chromadb 0.6.x with langchain 0.3.x. Installed `langchain-community==0.3.28` and used `from langchain_community.vectorstores import Chroma` in both scripts.
- **Files modified:** `scripts/rag_index.py`, `scripts/rag_query.py`
- **Verification:** `bash scripts/validate-phase12.sh` — 10/10 PASS; query retrieval confirmed semantically correct
- **Committed in:** `72fb9a4` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — dependency version conflict)
**Impact on plan:** Required change. chromadb 0.6.3 and k=3 default both preserved as specified. All functional requirements met.

## Issues Encountered

- pip initially installed chromadb 1.5.5 (latest) when `langchain-chroma==1.1.0` was installed first. Rebuilt venv with explicit `chromadb==0.6.3` pin first, then installed langchain stack, which resolved correctly.
- The repo was not cloned on supportTAK-server — cloned from GitHub (`https://github.com/Reston2024/firewall.git`) as part of Task 1.

## User Setup Required

None — all setup is automated via the scripts committed in this plan.

**To run end-to-end RAG-04 validation** (requires temporal separation):
1. `sudo docker stop malcolm-opensearch-1 malcolm-logstash-1` on supportTAK-server
2. `bash scripts/validate-phase12.sh --full`
3. `sudo docker start malcolm-opensearch-1 malcolm-logstash-1` when done

## Next Phase Readiness

- Phase 13 can import `from scripts.rag_query import query_corpus` to retrieve context chunks
- ChromaDB at `/var/lib/chromadb` is persistent (survives reboot via NVMe SQLite)
- Re-indexing: `cd ~/Firewall && /opt/rag/bin/python3 scripts/rag_index.py` is idempotent
- RAG-04 end-to-end test deferred to manual or Phase 13 integration — requires temporal separation from Malcolm

---
*Phase: 12-rag-knowledge-pipeline*
*Completed: 2026-04-07*

## Self-Check: PASSED

- FOUND: scripts/rag_index.py
- FOUND: scripts/rag_query.py
- FOUND: scripts/validate-phase12.sh
- FOUND: .planning/phases/12-rag-knowledge-pipeline/12-01-SUMMARY.md
- FOUND commit: 72fb9a4 (Task 1)
- FOUND commit: 20ddfc0 (Task 2)
