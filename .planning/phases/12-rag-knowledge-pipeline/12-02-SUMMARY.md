---
phase: 12-rag-knowledge-pipeline
plan: 02
subsystem: infra
tags: [rag, chromadb, langchain, foundation-sec-8b, ollama, end-to-end, validation, python, nlp]

# Dependency graph
requires:
  - phase: 12-rag-knowledge-pipeline
    plan: 01
    provides: ChromaDB at /var/lib/chromadb with 387 chunks, scripts/rag_query.py, scripts/validate-phase12.sh
  - phase: 11-foundation-sec-8b-ai-analyst
    provides: Foundation-Sec-8B Q4_K_M-GGUF via Ollama at localhost:11434 on supportTAK-server
provides:
  - scripts/rag_query.py: updated with --llm flag for end-to-end RAG+LLM testing
  - query_with_llm() function callable for end-to-end Foundation-Sec-8B integration
  - 10/10 manual security queries validated — all return relevant technical chunks
  - End-to-end RAG+LLM test confirmed working (1125-char coherent response referencing ADR-E02)
  - RAG-04 requirement met: Foundation-Sec-8B produces coherent answer with RAG context injected
affects:
  - 13-alert-triage-integration (will import query_corpus from rag_query.py; --llm flag pattern for end-to-end)
  - future-rag-upgrades (documents openai-compatible client path as working; langchain_community.ChatOllama returns empty)

# Tech tracking
tech-stack:
  added:
    - openai 1.x (OpenAI-compatible client for Ollama — confirmed working path for end-to-end LLM queries)
  patterns:
    - End-to-end RAG query pattern: query_with_llm(question, k=3) → retrieves chunks → injects into security analyst prompt → queries Foundation-Sec-8B
    - OpenAI client path: OpenAI(base_url='http://localhost:11434/v1', api_key='ollama') — ChatOllama from langchain_community returns empty in this venv config
    - Chunk context limit: 400 chars/chunk (not 600) to stay within OLLAMA_CONTEXT_LENGTH=2048 with 3 chunks + prompt overhead

key-files:
  created:
    - .planning/phases/12-rag-knowledge-pipeline/12-02-SUMMARY.md
  modified:
    - scripts/rag_query.py (added --llm flag, query_with_llm() function, SECURITY_ANALYST_PROMPT template)

key-decisions:
  - "Use openai client directly for Foundation-Sec-8B queries: langchain_community.chat_models.ChatOllama returns empty content in this venv (chromadb 0.6.3 + langchain 0.3.x). openai client confirmed working via both curl and Python tests with 1125-char coherent responses."
  - "Chunk context limit 400 chars (not 600): full 600-char × 3 chunks exceeds OLLAMA_CONTEXT_LENGTH=2048 budget and caused empty LLM responses. Confirmed working at 400-char limit."
  - "Reboot persistence test blocked: supportTAK-server did not come back online within 90+ minute observation window after sudo reboot — requires human physical intervention or remote console access."

patterns-established:
  - "End-to-end RAG: from scripts.rag_query import query_with_llm; result = query_with_llm(question, k=3)"
  - "LLM query path: from openai import OpenAI; client = OpenAI(base_url='http://localhost:11434/v1', api_key='ollama')"
  - "Temporal separation: Foundation-Sec-8B needs ~5.5GB RAM; Malcolm uses ~10GB; coexistence may be possible (12GB available) but test showed model loads successfully when Malcolm is running in reduced-load state"

requirements-completed: [RAG-03, RAG-04]

# Metrics
duration: 120min
completed: 2026-04-07
---

# Phase 12 Plan 02: RAG Validation and End-to-End Testing Summary

**10/10 manual security queries return relevant corpus chunks, Foundation-Sec-8B produces 1125-char coherent response referencing ADR-E02 localhost binding context — RAG-03 and RAG-04 requirements met; reboot persistence confirmation blocked pending server physical recovery**

## Performance

- **Duration:** ~120 min (dominated by server reboot wait — 90+ min timeout)
- **Started:** 2026-04-07T01:32:17Z
- **Completed:** 2026-04-07T (partial — reboot persistence blocked)
- **Tasks:** 1 complete, 1 partial (Task 2 reboot blocked), 1 checkpoint
- **Files modified:** 1 (scripts/rag_query.py)

## Accomplishments

- Updated `scripts/rag_query.py` with `--llm` flag: `query_with_llm()` function constructs security analyst prompt, retrieves k=3 chunks from ChromaDB, and queries Foundation-Sec-8B via Ollama OpenAI-compatible API
- Ran all 10 manual security queries — 10/10 pass with relevant chunks from expected source documents
- End-to-end RAG+LLM test confirmed: 1125-char response referencing ADR-E02 localhost binding, 127.0.0.1, prompt injection — no hallucinations
- Pre-reboot ChromaDB collection count: 387 chunks (recorded before reboot)
- Identified and fixed context window issue: 600-char chunks overflow OLLAMA_CONTEXT_LENGTH=2048; reduced to 400-char limit confirms working end-to-end

## 10 Manual Security Query Results

| # | Query | Top Source | Status |
|---|-------|-----------|--------|
| 1 | Why is Ollama bound to localhost only? | decisions/ADR-E02-ollama-localhost-binding.md | PASS |
| 2 | What is the SSH hardening configuration? | docs/hardening-deployment-runbook.md | PASS |
| 3 | How is Suricata configured for IDS monitoring? | docs/suricata-ids-runbook.md | PASS |
| 4 | What is the disaster recovery strategy? | decisions/ADR-0012-git-rebuild-as-ha-strategy.md | PASS |
| 5 | How are firewall zones configured? | docs/zone-policy-runbook.md | PASS |
| 6 | What is the telemetry pipeline architecture? | decisions/ADR-0004-telemetry-off-box.md | PASS |
| 7 | Why was Guardian chosen over fail2ban? | decisions/ADR-0006-guardian-over-fail2ban.md | PASS |
| 8 | What is the WUI certificate configuration? | docs/wui-certificate.md | PASS |
| 9 | What is the Foundation-Sec-8B inference throughput on N150? | docs/benchmarks/n150-foundation-sec-8b-benchmark.md | PASS |
| 10 | What are the RAM constraints for Malcolm and AI coexistence? | docs/benchmarks/n150-foundation-sec-8b-benchmark.md | PASS |

**Result: 10/10 PASS** — all queries return relevant technical content from expected source documents.

Query 3 (Suricata IDS) returned `docs/suricata-ids-runbook.md` (not `ADR-0007`) — this is semantically correct (Suricata IDS runbook is the most relevant document for "how is Suricata configured"). ADR-0007 covers the monitor-mode decision rationale specifically.

## End-to-End RAG+LLM Test (RAG-04)

**Query:** "What security controls protect the Ollama API from unauthorized access?"

**Retrieved chunks:** 3 chunks from `decisions/ADR-E02-ollama-localhost-binding.md` (Rationale, Decision, Consequences sections)

**Foundation-Sec-8B response (excerpt):**
> The only control is binding it to `127.0.0.1` (localhost) via systemd and firewall rules. No authentication mechanism exists for Ollama's API — binding restriction is the only viable countermeasure against prompt injection attacks.

**Assessment:**
- Non-empty: YES (1125 chars)
- References corpus context: YES (localhost binding, 127.0.0.1, prompt injection — all from ADR-E02)
- No hallucinations: YES (accurately describes the lack of native auth, references correct control)
- RAG-04 CONFIRMED

## Task Commits

Each task was committed atomically:

1. **Task 1: Run 10 manual security queries and end-to-end RAG+LLM test** - `b27a9d0` (feat)
2. **Task 2: Reboot persistence test** - BLOCKED (server did not return after reboot; pre-count=387 recorded)

## Files Created/Modified

- `scripts/rag_query.py` (270 lines) — added `--llm` flag, `query_with_llm()` function, `SECURITY_ANALYST_PROMPT` template, OpenAI client integration

## Decisions Made

1. **Use openai client directly (not langchain_community.chat_models.ChatOllama):** The deprecated `ChatOllama` from `langchain_community` returns empty content (len=0) in this venv configuration (chromadb 0.6.3 + langchain 0.3.x). The `openai` package client confirmed working via curl and Python tests. Root cause: deprecated ChatOllama's streaming/async behavior is broken in this package combination. The `openai` client uses the Ollama OpenAI-compatible `/v1/chat/completions` endpoint directly.

2. **Reduce chunk context limit from 600 to 400 chars:** Initial tests with 600 chars × 3 chunks returned empty LLM responses. Prompt was exceeding `OLLAMA_CONTEXT_LENGTH=2048` tokens. At 400 chars/chunk the total stays within budget (~1650 tokens). Confirmed working.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] langchain_community.ChatOllama returns empty content**
- **Found during:** Task 1 (end-to-end LLM test)
- **Issue:** `ChatOllama.invoke()` from `langchain_community.chat_models` returns empty string content despite Ollama responding correctly to curl and openai client. Root cause: deprecated ChatOllama in langchain 0.3.x + chromadb 0.6.3 venv has broken response parsing.
- **Fix:** Changed `query_with_llm()` to use `openai.OpenAI(base_url='http://localhost:11434/v1')` client directly. Removed ChatOllama import path. Added comment explaining why openai client is used over langchain wrapper.
- **Files modified:** `scripts/rag_query.py`
- **Committed in:** `b27a9d0` (Task 1 commit)

**2. [Rule 1 - Bug] Context window overflow at 600 chars/chunk**
- **Found during:** Task 1 (initial end-to-end test attempts)
- **Issue:** Using 600-char context per chunk caused empty LLM responses. The prompt with 3 × 600-char chunks + security analyst template + question exceeded OLLAMA_CONTEXT_LENGTH=2048.
- **Fix:** Reduced chunk context limit to 400 chars in `query_with_llm()`. Confirmed working at 400-char limit with 1125-char response.
- **Files modified:** `scripts/rag_query.py`
- **Committed in:** `b27a9d0` (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (Rule 1 — bugs in LLM integration path)
**Impact on plan:** Required fixes. All functional requirements met. End-to-end test confirmed working.

### Blocking Issue (Not Auto-fixed — Requires Human Action)

**Server reboot did not complete within 90+ minute observation window**
- **Found during:** Task 2 (reboot persistence test)
- **Issue:** `sudo reboot` was issued on supportTAK-server. Server stopped responding to SSH and ping. Pre-reboot ChromaDB count (387) was recorded. Server did not return to SSH-accessible state within 90+ minutes of polling.
- **Likely cause:** Server may be stuck at BIOS/UEFI prompt, running fsck, or has a hardware issue requiring physical intervention.
- **Action required:** Physical access or remote console (iDRAC/iLO if available) to verify server state and complete boot cycle.
- **Post-recovery verification:** `ssh opsadmin@192.168.1.22 "/opt/rag/bin/python3 -c \"import chromadb; c=chromadb.PersistentClient(path='/var/lib/chromadb'); print(c.get_collection('firewall-corpus').count())\""` — must return 387.

## Issues Encountered

- `langchain-ollama` package not installed in `/opt/rag` venv — Plan 12-01 did not install it during Task 1 setup. `from langchain_ollama import ChatOllama` raises `ModuleNotFoundError`. Worked around by using `openai` client directly.
- Server reboot did not complete — 90+ minute wait exceeded reasonable automation window. Documented as blocking issue requiring physical intervention.

## User Setup Required

**Physical intervention required for reboot persistence confirmation:**

1. Physically check supportTAK-server (192.168.1.22) — it may be stuck at a boot prompt
2. If stuck: power cycle the machine
3. Once SSH is accessible, verify ChromaDB persistence:
   ```
   ssh opsadmin@192.168.1.22 "/opt/rag/bin/python3 -c \"import chromadb; c=chromadb.PersistentClient(path='/var/lib/chromadb'); print(c.get_collection('firewall-corpus').count())\""
   ```
   Expected output: 387
4. Run a post-reboot query:
   ```
   ssh opsadmin@192.168.1.22 "cd ~/Firewall && HF_HUB_OFFLINE=1 /opt/rag/bin/python3 scripts/rag_query.py 'SSH hardening'"
   ```
5. Run the full validation suite:
   ```
   bash scripts/validate-phase12.sh
   ```
   Expected: 0 FAIL

## RAG-04 Requirement Status

| Requirement | Status | Evidence |
|-------------|--------|---------|
| RAG-01 (ChromaDB persistence) | PARTIAL — reboot persistence not yet confirmed post-reboot | Pre-reboot count: 387; post-reboot count: UNKNOWN (server not responding) |
| RAG-02 (all-MiniLM-L6-v2 embeddings) | CONFIRMED (Plan 12-01) | 10/10 queries return semantically correct chunks |
| RAG-03 (10 manual query validation) | CONFIRMED | 10/10 queries return relevant technical content from expected sources |
| RAG-04 (end-to-end RAG+LLM test) | CONFIRMED | Foundation-Sec-8B produced 1125-char coherent response referencing ADR-E02 context |

## Next Phase Readiness

**Blocked on reboot persistence confirmation.** Once server is back online:
- Run `bash scripts/validate-phase12.sh` → should pass all 10 checks
- Run `bash scripts/validate-phase12.sh --full` → should pass including RAG-04 end-to-end

Phase 13 can proceed with `from scripts.rag_query import query_corpus` and `query_with_llm` for alert triage integration.

## Known Stubs

None — all RAG functionality is wired end-to-end with real ChromaDB data and real Foundation-Sec-8B inference.

---
*Phase: 12-rag-knowledge-pipeline*
*Completed: 2026-04-07 (partial — reboot persistence blocked)*

## Self-Check: PASSED (with noted blocker)

- FOUND: scripts/rag_query.py
- FOUND: scripts/validate-phase12.sh
- FOUND: .planning/phases/12-rag-knowledge-pipeline/12-02-SUMMARY.md
- FOUND commit: b27a9d0 (Task 1: --llm flag)
- FOUND commit: c1eaf79 (docs: plan metadata)
- FOUND: --llm flag in scripts/rag_query.py
- BLOCKER: supportTAK-server not accessible post-reboot — reboot persistence count cannot be verified automatically
