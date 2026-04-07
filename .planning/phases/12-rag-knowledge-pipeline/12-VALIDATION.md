---
phase: 12
slug: rag-knowledge-pipeline
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-06
---

# Phase 12 — Validation Strategy

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Shell scripts + Python + SSH remote commands |
| **Quick run command** | `ssh opsadmin@192.168.1.22 "python3 -c \"import chromadb; c=chromadb.PersistentClient(path='/opt/rag/chroma'); print([col.name+':'+str(col.count()) for col in c.list_collections()])\""`|
| **Full suite command** | `bash scripts/validate-phase12.sh` |
| **Estimated runtime** | ~60 seconds (excludes end-to-end LLM test) |

## Per-Task Verification Map

| Task ID | Plan | Requirement | Test Type | Status |
|---------|------|-------------|-----------|--------|
| 12-01-01 | 01 | RAG-01 | integration | ⬜ pending |
| 12-01-02 | 01 | RAG-02 | integration | ⬜ pending |
| 12-02-01 | 02 | RAG-03 | integration | ⬜ pending |
| 12-02-02 | 02 | RAG-04 | integration | ⬜ pending |

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Chunk relevance quality | RAG-03 | Subjective assessment of retrieval quality | Run 10 queries, verify chunks contain relevant technical content |
| End-to-end answer quality | RAG-04 | Subjective assessment of LLM answer | Query with RAG context, evaluate coherence and accuracy |

**Approval:** pending
