# Phase 12: RAG Knowledge Pipeline - Research

**Researched:** 2026-04-06
**Domain:** Python RAG pipeline — ChromaDB embedded, LangChain, sentence-transformers, Ollama context injection on constrained Ubuntu 22.04 hardware
**Confidence:** HIGH (standard pattern; all major decisions are locked; corpus-specific chunking validation is the only project-specific unknown)

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| RAG-01 | ChromaDB embedded vector store initialized on supportTAK-server NVMe | PersistentClient with persist_directory on NVMe path; Python venv at /opt/rag; survives reboot by design |
| RAG-02 | all-MiniLM-L6-v2 embedding model deployed (~90MB) — Foundation-Sec-8B never used for embeddings | sentence-transformers 3.x + HuggingFaceEmbeddings; model pre-cached in venv; ADR-E02 compliance confirmed |
| RAG-03 | ADRs, runbooks, validation results, control docs indexed with header-aware Markdown chunking (400-600 tokens, 10-15% overlap) | MarkdownHeaderTextSplitter → RecursiveCharacterTextSplitter two-stage pipeline; contextual header prepend pattern documented |
| RAG-04 | RAG retrieval validated with 10 manual queries against corpus before production use | Manual query test harness script; validate-phase12.sh with automated checks; success criteria defined |
</phase_requirements>

---

## Summary

Phase 12 builds the knowledge layer that Phase 13 (alert triage) will consume. The stack is fully locked: ChromaDB embedded on NVMe, all-MiniLM-L6-v2 embeddings, LangChain 0.3.x for orchestration. The standard pattern (LangChain + ChromaDB + sentence-transformers + Ollama) is extremely well-documented and has no architecture unknowns. The only project-specific work is (1) the chunking strategy for this corpus's Markdown ADRs and shell scripts, and (2) validating that retrieved chunks contain rationale rather than just keywords.

The critical version constraint for 2026 is that ChromaDB 1.x (released late 2025, Rust rewrite) broke all existing langchain-chroma integrations. The correct pinned stack is `chromadb>=0.4.0,<0.7.0` with `langchain-chroma 1.1.0` — langchain-chroma's PyPI constraint explicitly excludes chromadb 1.x. Installing the latest `pip install chromadb` pulls 1.5.5 (as of April 2026), which is incompatible with langchain-chroma. Pin `chromadb==0.6.3` explicitly.

The corpus is small (~35-50 files total: 12 ADRs, 2 executor ADRs, ~10 docs/ runbooks, validation scripts, planning artifacts). At this scale ChromaDB embedded handles it comfortably with minimal RAM (~100-300 MB). The all-MiniLM-L6-v2 embedding model adds ~300 MB when loaded; this is acceptable during indexing (one-time operation). During triage queries it loads on demand and releases with the Python process.

**Primary recommendation:** Use a Python virtualenv at `/opt/rag`, pin `chromadb==0.6.3` and `langchain-chroma==1.1.0`, persist ChromaDB to `/var/lib/chromadb`, pre-cache the embedding model in the venv, and write a `rag_index.py` ingestion script plus a `rag_query.py` query interface callable from the future triage worker.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| chromadb | 0.6.3 (pinned) | Embedded vector store | Last stable 0.x release before Rust rewrite; fully compatible with langchain-chroma 1.1.0; embedded mode requires no separate server process |
| langchain-chroma | 1.1.0 | LangChain-ChromaDB bridge | Latest stable; explicitly constrains chromadb to <0.7.0 — do not upgrade chromadb past this |
| langchain | 0.3.x | RAG orchestration, text splitters, retrieval chains | Current stable LangChain series; LangChain 0.3 + langchain-chroma 1.1.0 confirmed compatible |
| langchain-text-splitters | 0.3.x | MarkdownHeaderTextSplitter + RecursiveCharacterTextSplitter | Ships with langchain 0.3.x; provides both splitters needed for two-stage chunking |
| langchain-community | 0.3.x | HuggingFaceEmbeddings wrapper | Provides `langchain_community.embeddings.HuggingFaceEmbeddings` for sentence-transformers integration |
| sentence-transformers | 3.x | all-MiniLM-L6-v2 embedding model | 22M parameter model, 384-dim vectors, ~90 MB weights, CPU inference in milliseconds |
| openai | 1.x | OpenAI-compatible client for Ollama | Points at `http://localhost:11434/v1`; used in end-to-end RAG+LLM test |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| langchain-ollama | 0.3.x | LangChain Ollama LLM wrapper | For end-to-end test: RAG context injection into Foundation-Sec-8B (RAG-04 end-to-end check) |
| pypdf | latest | PDF ingestion | If any corpus files are PDF (none expected in current corpus; future-proofing) |
| tiktoken | latest | Token counting for chunk size validation | Verifying 400-600 token chunks are within target; cl100k_base tokenizer approximates MiniLM tokenization |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| chromadb 0.6.3 (pinned) | chromadb 1.5.5 (latest) | 1.x is Rust rewrite with incompatible storage format; langchain-chroma explicitly excludes it; use 0.6.3 until langchain-chroma drops a 1.x-compatible release |
| all-MiniLM-L6-v2 | nomic-embed-text via Ollama | nomic-embed-text has 768-dim embeddings and better retrieval quality, but requires Ollama loaded simultaneously — adds ~500 MB RAM. MiniLM is sufficient for this small structured corpus |
| ChromaDB embedded | OpenSearch k-NN plugin | Malcolm's bundled OpenSearch 3.5.0 includes k-NN plugin; eliminates ChromaDB dependency. Deferred to v3.0 per ADR decision — adds OpenSearch API complexity in Phase 12 |
| langchain-community HuggingFaceEmbeddings | chromadb's own embedding functions | ChromaDB 0.6.x has limited built-in embedding support; LangChain wrapper is cleaner and reusable in triage worker |

**Installation (run on supportTAK-server as opsadmin):**

```bash
# Create virtualenv
sudo python3 -m venv /opt/rag
sudo chown -R opsadmin:opsadmin /opt/rag

# Activate and install with pinned chromadb
source /opt/rag/bin/activate

pip install \
  "chromadb==0.6.3" \
  "langchain==0.3.*" \
  "langchain-chroma==1.1.0" \
  "langchain-community==0.3.*" \
  "langchain-text-splitters==0.3.*" \
  "langchain-ollama==0.3.*" \
  "sentence-transformers==3.*" \
  "openai>=1.0" \
  tiktoken

# Pre-cache all-MiniLM-L6-v2 embedding model (~90MB download from HuggingFace)
python3 -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"

# Create ChromaDB persist directory on NVMe
sudo mkdir -p /var/lib/chromadb
sudo chown opsadmin:opsadmin /var/lib/chromadb
```

**Version verification before writing the stack table:**
```bash
pip show chromadb langchain langchain-chroma langchain-community sentence-transformers
```

---

## Architecture Patterns

### Recommended Project Structure

```
/opt/rag/                       # Python virtualenv + scripts (on NVMe)
├── bin/                        # venv binaries (python3, pip, etc.)
├── lib/                        # installed packages including chromadb 0.6.3
└── (venv managed)

/var/lib/chromadb/              # ChromaDB persistent data (NVMe)
├── chroma.sqlite3              # SQLite metadata (chromadb 0.6.x uses SQLite)
└── <uuid>/                     # Vector store segment files

# In repo: scripts/rag/
scripts/
├── rag_index.py               # Corpus ingestion — run once + on doc change
├── rag_query.py               # Query interface — called by triage worker (Phase 13)
└── validate-phase12.sh        # Validation suite for RAG-01 through RAG-04
```

### Pattern 1: Two-Stage Markdown Chunking (RAG-03)

**What:** Header-aware split first (preserves ADR section boundaries), then size-constrained split within sections (enforces 400-600 token limit).

**When to use:** All `.md` files in corpus (ADRs, runbooks, planning docs). Shell scripts use recursive character split only (no headers).

**Example:**

```python
# Source: LangChain official docs — MarkdownHeaderTextSplitter
from langchain_text_splitters import MarkdownHeaderTextSplitter, RecursiveCharacterTextSplitter

def chunk_markdown(content: str, source_path: str) -> list[dict]:
    """Two-stage chunker: header-aware split then size-constrained split."""

    # Stage 1: Split on Markdown headers — preserves section integrity
    header_splitter = MarkdownHeaderTextSplitter(
        headers_to_split_on=[
            ("#", "h1"),
            ("##", "h2"),
            ("###", "h3"),
        ],
        strip_headers=False,  # Keep header text in chunk for context
    )
    header_splits = header_splitter.split_text(content)

    # Stage 2: Enforce token budget within each section
    # ~400 chars ≈ 100 tokens; ~2400 chars ≈ 600 tokens (rough 4-char/token estimate)
    # Use 1800 chars with 200 overlap → targets 450-token chunks with ~11% overlap
    char_splitter = RecursiveCharacterTextSplitter(
        chunk_size=1800,      # ~450 tokens
        chunk_overlap=200,    # ~50 tokens / ~11% overlap
        separators=["\n\n", "\n", " ", ""],
    )

    chunks = []
    for section in header_splits:
        # Prepend breadcrumb to each chunk (document title + section path)
        breadcrumb = f"[{source_path}] "
        if section.metadata.get("h1"):
            breadcrumb += f"# {section.metadata['h1']} "
        if section.metadata.get("h2"):
            breadcrumb += f"/ ## {section.metadata['h2']} "
        if section.metadata.get("h3"):
            breadcrumb += f"/ ### {section.metadata['h3']}"

        sub_chunks = char_splitter.split_text(section.page_content)
        for sub in sub_chunks:
            chunks.append({
                "content": breadcrumb.strip() + "\n\n" + sub,
                "metadata": {
                    "source": source_path,
                    **section.metadata,
                }
            })
    return chunks
```

### Pattern 2: ChromaDB PersistentClient Initialization (RAG-01)

**What:** Embedded mode with NVMe persistence. Collection survives reboot — SQLite file on NVMe is the durable store.

**Example:**

```python
# Source: ChromaDB official docs — PersistentClient
import chromadb

CHROMA_PATH = "/var/lib/chromadb"
COLLECTION_NAME = "firewall-corpus"

def get_chroma_client():
    """Return persistent ChromaDB client bound to NVMe path."""
    client = chromadb.PersistentClient(path=CHROMA_PATH)
    return client

def get_or_create_collection(client):
    """Get existing collection or create new one."""
    return client.get_or_create_collection(
        name=COLLECTION_NAME,
        metadata={"hnsw:space": "cosine"},  # cosine similarity for MiniLM embeddings
    )
```

### Pattern 3: LangChain Retrieval Chain with Ollama (RAG-04 end-to-end)

**What:** Complete RAG pipeline — retrieve relevant chunks from ChromaDB, inject into prompt, query Foundation-Sec-8B via Ollama's OpenAI-compatible API.

**Example:**

```python
# Source: LangChain docs — Chroma integration + Ollama
from langchain_chroma import Chroma
from langchain_community.embeddings import HuggingFaceEmbeddings
from langchain_ollama import ChatOllama
from langchain.chains import RetrievalQA
from langchain.prompts import PromptTemplate

EMBED_MODEL = "all-MiniLM-L6-v2"
LLM_MODEL = "hf.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF"
OLLAMA_BASE = "http://localhost:11434"

def build_rag_chain():
    embeddings = HuggingFaceEmbeddings(
        model_name=EMBED_MODEL,
        model_kwargs={"device": "cpu"},
    )

    vector_store = Chroma(
        collection_name="firewall-corpus",
        embedding_function=embeddings,
        persist_directory="/var/lib/chromadb",
    )

    retriever = vector_store.as_retriever(
        search_type="similarity",
        search_kwargs={"k": 5},  # Return top-5 chunks
    )

    # Security analyst prompt — keeps response focused on operational context
    prompt = PromptTemplate(
        template="""You are a security analyst assistant for a local network security system.
Use the following context from operational documents to answer the question accurately.

Context:
{context}

Question: {question}

Answer (cite document sections where relevant):""",
        input_variables=["context", "question"],
    )

    llm = ChatOllama(
        model=LLM_MODEL,
        base_url=OLLAMA_BASE,
        temperature=0.1,       # Low temperature for factual retrieval
        num_predict=512,       # Cap at 512 tokens (~3.5 min at 2.47 tok/s)
    )

    return RetrievalQA.from_chain_type(
        llm=llm,
        chain_type="stuff",    # Stuff all chunks into context (small corpus)
        retriever=retriever,
        chain_type_kwargs={"prompt": prompt},
        return_source_documents=True,
    )
```

### Anti-Patterns to Avoid

- **Installing latest chromadb (`pip install chromadb`):** Pulls 1.5.5 as of April 2026 — completely incompatible with langchain-chroma 1.1.0. Always pin `chromadb==0.6.3`.
- **Using Foundation-Sec-8B for embeddings:** RAM-prohibitive double-load (5.5 GB model + 16 GB physical RAM). all-MiniLM-L6-v2 is 90 MB. Never call Ollama's `/v1/embeddings` endpoint.
- **Fixed-size chunking without header awareness:** LangChain's default `RecursiveCharacterTextSplitter` alone splits across ADR decision rationale sections mid-sentence. Always apply `MarkdownHeaderTextSplitter` first.
- **No breadcrumb prepend:** Without "ADR-0012 / ## Decision" prefix, retrieved chunks lose all context about which document and section they came from. The LLM cannot cite sources.
- **Storing ChromaDB in the git repo or home directory:** Use `/var/lib/chromadb` (NVMe path, not home directory, not `/tmp`). The database is a runtime artifact, not a source artifact.
- **Running ingestion with Malcolm at full load:** all-MiniLM-L6-v2 loads ~300 MB; ChromaDB adds ~100 MB. Combined with Malcolm's 11.7 GB steady-state this is manageable (total ~12.1 GB). Ingestion is not a RAM concern — only Foundation-Sec-8B inference requires temporal separation.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Markdown document sectioning | Custom regex ADR parser | `MarkdownHeaderTextSplitter` from `langchain-text-splitters` | Header detection edge cases, nested headers, code blocks within sections — all handled |
| Token-accurate chunk sizing | Character-count estimator | `RecursiveCharacterTextSplitter` with `tiktoken` (or `from_tiktoken_encoder`) | Character/token ratio varies by content; ADR rationale sections have denser terminology |
| Vector similarity search | Cosine similarity in NumPy | ChromaDB PersistentClient | Thread safety, HNSW index, persistence, metadata filtering — all built-in |
| Embedding model loading | Custom transformers pipeline | `sentence_transformers.SentenceTransformer` | Handles tokenization, pooling, normalization; returns normalized 384-dim vectors ready for cosine similarity |
| LLM prompt injection | Manual string format | `langchain.prompts.PromptTemplate` + `RetrievalQA` | Input sanitization, context truncation when chunks exceed context window, chain composition |

**Key insight:** The "small corpus, simple use case" temptation is to write a raw NumPy + SQLite vector store. Resist this — HNSW index performance, thread safety during Phase 13 concurrent queries, and the LangChain retriever interface that Phase 13 needs are all reasons to use the established stack.

---

## Common Pitfalls

### Pitfall 1: chromadb 1.x Incompatibility With langchain-chroma

**What goes wrong:** `pip install chromadb` (no version pin) installs 1.5.5 as of April 2026. `import langchain_chroma` then fails with `ImportError` or `TypeError: Instance and class checks can only be used with @runtime_checkable protocols`. The error message does not mention the version conflict.

**Why it happens:** ChromaDB 1.x was a complete Rust rewrite (late 2025) with incompatible Python API and storage format. langchain-chroma 1.1.0 pins `chromadb<0.7.0` in its dependency metadata, but pip may install a non-conflicting chromadb 1.x if the constraint is not read correctly in all environments.

**How to avoid:** Always install with explicit pin: `pip install "chromadb==0.6.3"`. Verify after: `python3 -c "import chromadb; print(chromadb.__version__)"` must show `0.6.x`.

**Warning signs:** `TypeError: Instance and class checks can only be used with @runtime_checkable protocols` on import; any `chromadb` version starting with `1.`.

### Pitfall 2: ADR Chunking Splits Across Decision/Rationale Boundary

**What goes wrong:** A large ADR (e.g., ADR-E02 at ~80 lines) gets split such that the "## Decision" header and its body land in chunk N, and "## Rationale" lands in chunk N+1. A query for "why is Ollama bound to localhost" retrieves chunk N+1 (rationale) but not chunk N (decision), producing incomplete answers.

**Why it happens:** `RecursiveCharacterTextSplitter` alone splits by character count without knowledge of header boundaries. An ADR's full Decision + Rationale section often exceeds 600 tokens combined.

**How to avoid:** Always run `MarkdownHeaderTextSplitter` first (splits at `##` boundaries), then apply size constraint within each section. Individual sections that still exceed 600 tokens get split at paragraph boundaries (`\n\n`), not mid-sentence.

**Warning signs:** Manual query test returns chunks that start mid-paragraph; chunks have no `h2` or `h3` metadata attached.

### Pitfall 3: Embedding Model Download Fails at Index Time

**What goes wrong:** `SentenceTransformer('all-MiniLM-L6-v2')` on first call attempts to download from HuggingFace. If supportTAK-server has restricted outbound access (firewall rules, no DNS for `huggingface.co`) this fails silently or with a `ConnectionError` during indexing.

**Why it happens:** sentence-transformers downloads model weights on first use to `~/.cache/huggingface/` by default.

**How to avoid:** Pre-cache the model during setup (before indexing): `python3 -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"`. Verify the cache directory exists and contains model files before running `rag_index.py`. If outbound is restricted, copy the model to the venv path manually or use `HF_HUB_OFFLINE=1` after caching.

**Warning signs:** `requests.exceptions.ConnectionError: Unable to connect to huggingface.co` during indexing; model cache at `~/.cache/huggingface/hub/` is empty.

### Pitfall 4: ChromaDB Collection Count Mismatch After Reboot

**What goes wrong:** Reboot validation check shows `collection_count == 0` even though indexing succeeded. The collection appears gone.

**Why it happens:** The persist_directory path either (a) was set to a temp path or relative path that doesn't survive reboot, (b) has permissions issues after reboot preventing chromadb from reading the SQLite file, or (c) the indexing script used an ephemeral `chromadb.Client()` instead of `chromadb.PersistentClient(path=...)`.

**How to avoid:** Always use `chromadb.PersistentClient(path="/var/lib/chromadb")` (absolute path, NVMe). Verify after indexing: `client.list_collections()` must return the collection. Reboot and verify again before marking RAG-01 complete.

**Warning signs:** `chromadb.Client()` anywhere in the codebase (ephemeral); relative paths like `./chroma_db` (home directory, not NVMe); empty `/var/lib/chromadb/` after reboot.

### Pitfall 5: Chunking Shell Scripts (.sh files) with Markdown Header Splitter

**What goes wrong:** `MarkdownHeaderTextSplitter` applied to `.sh` files raises no error but produces zero header-based splits (shell scripts have no `##` Markdown headers). The file is returned as a single chunk — if the validation script is long, this creates a 2000+ token chunk that exceeds context window or retrieval quality.

**Why it happens:** Shell scripts use `#` for comments, which the header splitter misidentifies as H1 Markdown headers in some versions.

**How to avoid:** Route `.sh`, `.py`, and non-Markdown files through `RecursiveCharacterTextSplitter` directly (skip the header-aware stage). Split on `["\n\n", "\n", " ", ""]` with the same 1800-char / 200-overlap settings.

**Warning signs:** A shell script chunk has `h1` metadata set to a comment text like `"validate-phase11.sh — Phase 11 validation suite"`.

### Pitfall 6: Context Window Overflow When Injecting RAG Chunks

**What goes wrong:** The Phase 13 triage worker injects 5 RAG chunks (each ~450 tokens = 2250 tokens total) plus an alert description and prompt template into Foundation-Sec-8B. With `OLLAMA_CONTEXT_LENGTH=2048`, the prompt is truncated and the model produces a confused or truncated answer.

**Why it happens:** RAG chunk retrieval (`k=5`) assumes context window can hold the chunks. `OLLAMA_CONTEXT_LENGTH=2048` was set in Phase 11 to reduce KV cache RAM. Total prompt = system prompt (~100 tokens) + RAG chunks (5 × 450 = 2250 tokens) + alert description (~200 tokens) = ~2550 tokens — exceeds the 2048 limit.

**How to avoid:** Cap RAG retrieval at `k=3` for production triage (3 × 450 = 1350 tokens chunks + ~300 tokens overhead = ~1650 tokens — fits within 2048). For the Phase 12 manual validation test (RAG-04), use `k=3` to match Phase 13's production configuration. Document this in the triage worker design.

**Warning signs:** Foundation-Sec-8B outputs trailing incomplete sentences; `ollama run --verbose` shows `context filled=100%`.

---

## Code Examples

Verified patterns from official sources:

### Ingestion Script Skeleton (rag_index.py)

```python
#!/usr/bin/env python3
# scripts/rag_index.py — Corpus ingestion for Phase 12 RAG pipeline
# Run from repo root: /opt/rag/bin/python3 scripts/rag_index.py
# Source: LangChain MarkdownHeaderTextSplitter docs + ChromaDB PersistentClient docs

import os
import glob
import chromadb
from langchain_text_splitters import MarkdownHeaderTextSplitter, RecursiveCharacterTextSplitter
from langchain_community.embeddings import HuggingFaceEmbeddings
from langchain_chroma import Chroma

CHROMA_PATH = "/var/lib/chromadb"
COLLECTION_NAME = "firewall-corpus"
EMBED_MODEL = "all-MiniLM-L6-v2"

CORPUS_GLOBS = [
    "decisions/*.md",
    "docs/**/*.md",
    "docs/**/*.sh",
    ".planning/REQUIREMENTS.md",
    ".planning/research/SUMMARY.md",
    ".planning/research/STACK.md",
    "scripts/validate-*.sh",
]

def load_corpus(repo_root: str) -> list[tuple[str, str]]:
    """Return list of (relative_path, content) tuples."""
    files = []
    for pattern in CORPUS_GLOBS:
        for path in glob.glob(os.path.join(repo_root, pattern), recursive=True):
            rel = os.path.relpath(path, repo_root)
            with open(path, "r", encoding="utf-8", errors="ignore") as f:
                files.append((rel, f.read()))
    return files

def chunk_file(rel_path: str, content: str) -> list[dict]:
    """Route to correct splitter based on file extension."""
    chunks = []
    char_splitter = RecursiveCharacterTextSplitter(
        chunk_size=1800, chunk_overlap=200,
        separators=["\n\n", "\n", " ", ""],
    )

    if rel_path.endswith(".md"):
        header_splitter = MarkdownHeaderTextSplitter(
            headers_to_split_on=[("#", "h1"), ("##", "h2"), ("###", "h3")],
            strip_headers=False,
        )
        sections = header_splitter.split_text(content)
        for section in sections:
            breadcrumb = f"[{rel_path}]"
            for level in ["h1", "h2", "h3"]:
                if section.metadata.get(level):
                    breadcrumb += f" / {section.metadata[level]}"
            sub_chunks = char_splitter.split_text(section.page_content)
            for sub in sub_chunks:
                chunks.append({
                    "content": breadcrumb + "\n\n" + sub,
                    "metadata": {"source": rel_path, **section.metadata},
                })
    else:
        # Shell scripts and other text files — size-only splitting
        sub_chunks = char_splitter.split_text(content)
        for i, sub in enumerate(sub_chunks):
            chunks.append({
                "content": f"[{rel_path}]\n\n{sub}",
                "metadata": {"source": rel_path, "chunk_index": i},
            })
    return chunks

def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    print(f"Loading corpus from {repo_root}...")
    files = load_corpus(repo_root)
    print(f"  Loaded {len(files)} files")

    all_chunks = []
    for rel_path, content in files:
        chunks = chunk_file(rel_path, content)
        all_chunks.extend(chunks)
        print(f"  {rel_path}: {len(chunks)} chunks")

    print(f"\nTotal chunks: {len(all_chunks)}")
    print(f"Initializing ChromaDB at {CHROMA_PATH}...")

    embeddings = HuggingFaceEmbeddings(
        model_name=EMBED_MODEL,
        model_kwargs={"device": "cpu"},
    )

    vector_store = Chroma(
        collection_name=COLLECTION_NAME,
        embedding_function=embeddings,
        persist_directory=CHROMA_PATH,
    )

    # Upsert all chunks (idempotent — safe to re-run)
    texts = [c["content"] for c in all_chunks]
    metadatas = [c["metadata"] for c in all_chunks]
    ids = [f"{c['metadata']['source']}-{i}" for i, c in enumerate(all_chunks)]

    vector_store.add_texts(texts=texts, metadatas=metadatas, ids=ids)
    print(f"\nIndexed {len(all_chunks)} chunks into collection '{COLLECTION_NAME}'")

    # Verify persistence
    client = chromadb.PersistentClient(path=CHROMA_PATH)
    count = client.get_collection(COLLECTION_NAME).count()
    print(f"Verification: collection count = {count} chunks")

if __name__ == "__main__":
    main()
```

### Query Interface Skeleton (rag_query.py)

```python
#!/usr/bin/env python3
# scripts/rag_query.py — RAG query interface for manual testing and Phase 13 consumption
# Usage: /opt/rag/bin/python3 scripts/rag_query.py "What is the rationale for localhost binding?"

import sys
from langchain_chroma import Chroma
from langchain_community.embeddings import HuggingFaceEmbeddings

CHROMA_PATH = "/var/lib/chromadb"
COLLECTION_NAME = "firewall-corpus"
EMBED_MODEL = "all-MiniLM-L6-v2"

def query_corpus(question: str, k: int = 3) -> list[dict]:
    """Return top-k relevant chunks for a question."""
    embeddings = HuggingFaceEmbeddings(
        model_name=EMBED_MODEL,
        model_kwargs={"device": "cpu"},
    )
    vector_store = Chroma(
        collection_name=COLLECTION_NAME,
        embedding_function=embeddings,
        persist_directory=CHROMA_PATH,
    )
    results = vector_store.similarity_search_with_score(question, k=k)
    return [
        {"content": doc.page_content, "source": doc.metadata.get("source"), "score": score}
        for doc, score in results
    ]

if __name__ == "__main__":
    question = " ".join(sys.argv[1:]) or "What is the Ollama security configuration?"
    chunks = query_corpus(question)
    for i, chunk in enumerate(chunks, 1):
        print(f"\n--- Chunk {i} (score: {chunk['score']:.4f}, source: {chunk['source']}) ---")
        print(chunk["content"][:500])
```

---

## Corpus Inventory

The following files constitute the index corpus for Phase 12. All exist in the current repository state.

### ADRs (decisions/)

| File | Type | Lines |
|------|------|-------|
| ADR-0001 through ADR-0012 (12 files) | Architecture Decision Records | ~30-80 lines each |
| ADR-E01-executor-failure-taxonomy.md | Executor ADR | ~60 lines |
| ADR-E02-ollama-localhost-binding.md | Executor ADR | ~50 lines |

### Runbooks and Docs (docs/)

| File | Type |
|------|------|
| hardening-deployment-runbook.md | Deployment runbook |
| services-runbook.md | Services runbook |
| ssh-management-runbook.md | SSH runbook |
| suricata-ids-runbook.md | IDS runbook |
| telemetry-deployment-runbook.md | Telemetry runbook |
| zone-policy-runbook.md | Zone policy runbook |
| deployment-checklist.md | Checklist |
| wui-certificate.md | WUI certificate doc |

### Planning Artifacts (.planning/research/)

| File | Type |
|------|------|
| SUMMARY.md | Architecture summary |
| STACK.md | Stack decisions |
| REQUIREMENTS.md | Requirements |

### Validation Scripts (scripts/)

| Pattern | Purpose |
|---------|---------|
| validate-phase*.sh (~12 files) | Phase validation suites |

**Total estimated corpus size:** ~35-50 files, ~5,000-8,000 lines. Expected chunk count after two-stage splitting: 150-300 chunks. Well within ChromaDB embedded capacity.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `chromadb.Client()` (in-memory) | `chromadb.PersistentClient(path=...)` | chromadb 0.4.x | Old API is deprecated; `Client()` does not persist to disk reliably |
| langchain `Chroma` from langchain-community | `Chroma` from `langchain-chroma` (separate package) | LangChain 0.2.x | langchain-community Chroma is deprecated; use `langchain-chroma` package |
| `chromadb` latest (1.x) | `chromadb==0.6.3` (pinned) | Late 2025 (Rust rewrite) | 1.x completely incompatible with langchain-chroma; pin required |
| `langchain-chroma 0.1.x` | `langchain-chroma 1.1.0` | December 2025 | 1.1.0 is current stable; still pins chromadb<0.7.0 |
| `chroma.persist()` method call | No explicit persist call needed | chromadb 0.4.x | PersistentClient auto-commits; explicit `persist()` was removed |

**Deprecated/outdated:**
- `langchain_community.vectorstores.Chroma`: deprecated in favor of `langchain_chroma.Chroma`
- `chromadb.Client()`: use `chromadb.PersistentClient(path=...)` for persistent storage
- `chroma.persist()` explicit call: removed in chromadb 0.4.x; PersistentClient auto-persists
- `chromadb>=1.0.0`: incompatible with all existing langchain-chroma versions as of April 2026

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | bash (validate-phase12.sh) — consistent with validate-phase11.sh pattern |
| Config file | none — standalone script |
| Quick run command | `bash scripts/validate-phase12.sh` |
| Full suite command | `bash scripts/validate-phase12.sh --full` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| RAG-01 | ChromaDB persists on NVMe, survives reboot — collection count unchanged | smoke | `bash scripts/validate-phase12.sh` (RAG-01 check) | Wave 0 |
| RAG-02 | all-MiniLM-L6-v2 model cached locally, embedding succeeds without network | smoke | `bash scripts/validate-phase12.sh` (RAG-02 check) | Wave 0 |
| RAG-03 | ADR query returns rationale as top-3 chunk; no chunk splits mid-decision | manual + automated check | `bash scripts/validate-phase12.sh` (RAG-03 ADR check) | Wave 0 |
| RAG-04 | 10 manual security queries return relevant content; Foundation-Sec-8B end-to-end confirmed | manual (10 queries) + automated (1 smoke) | `bash scripts/validate-phase12.sh --full` | Wave 0 |

### Sampling Rate

- **Per task commit:** `bash scripts/validate-phase12.sh` (quick: RAG-01 + RAG-02 + one RAG-03 smoke)
- **Per wave merge:** `bash scripts/validate-phase12.sh --full` (all checks + 1 end-to-end LLM test)
- **Phase gate:** All 4 RAG requirements passing before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `scripts/validate-phase12.sh` — covers RAG-01 through RAG-04 (create in Wave 1)
- [ ] `scripts/rag_index.py` — corpus ingestion script (create in Wave 1)
- [ ] `scripts/rag_query.py` — query interface for manual testing and Phase 13 (create in Wave 1)
- [ ] Python venv at `/opt/rag` with pinned dependencies (install in Wave 1)
- [ ] ChromaDB persist directory at `/var/lib/chromadb` (create in Wave 1)

---

## Open Questions

1. **Python 3.10 adequacy on Ubuntu 22.04**
   - What we know: Ubuntu 22.04 ships Python 3.10 by default; langchain-chroma 1.1.0 requires `>=3.10.0`; sentence-transformers 3.x requires `>=3.8`
   - What's unclear: Whether any transitive dependency of chromadb 0.6.3 requires Python 3.11+
   - Recommendation: Use `python3 --version` check in validate-phase12.sh; if `3.10.x` is present, proceed. If a dependency fails install, add `deadsnakes/ppa` to get Python 3.11 (one-line fix, no architecture change)
   - Confidence: HIGH that 3.10 is sufficient — langchain-chroma 1.1.0 explicitly supports 3.10

2. **HuggingFace outbound access on supportTAK-server**
   - What we know: Embedding model must be pre-cached before indexing; no HuggingFace access at index time should be required
   - What's unclear: Whether supportTAK-server has unrestricted outbound HTTPS to `huggingface.co` during setup; IPFire RED interface routes outbound traffic
   - Recommendation: Pre-cache model during setup wave (Wave 1), before any indexing tasks; add `HF_HUB_OFFLINE=1` env var to all non-setup scripts as a guard
   - Confidence: MEDIUM — standard home network setup likely has unrestricted outbound; verify with `curl -sI https://huggingface.co` from supportTAK-server

3. **OLLAMA_CONTEXT_LENGTH=2048 vs RAG chunk injection budget**
   - What we know: `OLLAMA_CONTEXT_LENGTH=2048` was set in Phase 11 to reduce KV cache RAM; 5 chunks × 450 tokens + prompt overhead = ~2550 tokens which overflows
   - What's unclear: Whether the context length should be increased for Phase 12 RAG use, or whether `k=3` is the correct constraint
   - Recommendation: Use `k=3` in RAG queries throughout Phase 12 and Phase 13; document this as the production configuration; do not increase context length (would add ~500 MB KV cache pressure). This is already the correct answer based on RAM constraints.
   - Confidence: HIGH — context math is clear; k=3 fits within 2048 tokens

---

## Sources

### Primary (HIGH confidence)

- [PyPI: langchain-chroma 1.1.0](https://pypi.org/project/langchain-chroma/) — confirmed latest version December 12, 2025; Python >=3.10 requirement
- [LangChain Chroma Integration Docs](https://docs.langchain.com/oss/python/integrations/vectorstores/chroma) — official langchain-chroma usage, persist_directory pattern, `langchain-chroma>=0.1.2` minimum documented
- [LangChain MarkdownHeaderTextSplitter Reference](https://python.langchain.com/api_reference/text_splitters/markdown/langchain_text_splitters.markdown.MarkdownHeaderTextSplitter.html) — strip_headers parameter, metadata preservation behavior
- [ChromaDB PersistentClient Docs](https://docs.trychroma.com/docs/run-chroma/persistent-client) — PersistentClient with path parameter survives restarts
- [PyPI: chromadb](https://pypi.org/project/chromadb/) — version 1.5.5 released March 10, 2026 (latest 1.x)
- [STATE.md — Accumulated Context decisions](../../STATE.md) — ChromaDB embedded on NVMe, all-MiniLM-L6-v2, temporal separation, context 2048
- [docs/benchmarks/n150-foundation-sec-8b-benchmark.md](../../../docs/benchmarks/n150-foundation-sec-8b-benchmark.md) — confirmed 2.47 tok/s, Malcolm 11.7 GB steady-state RAM

### Secondary (MEDIUM confidence)

- [GitHub Issue: Latest chroma incompatible with langchain-chroma #31047](https://github.com/langchain-ai/langchain/issues/31047) — langchain-chroma pins chromadb<0.7.0 confirmed; 1.x incompatibility documented
- [PyPI: langchain-chroma dependency graph](https://pypi.org/project/langchain-chroma/) — `chromadb!=0.5.4,...,<0.7.0,>=0.4.0` constraint confirmed from earlier langchain-chroma 0.2.x; 1.1.0 likely extends to `<1.0.0` or similar
- [ChromaDB Migration Docs](https://docs.trychroma.com/docs/overview/migration) — 0.x to 1.x storage format incompatibility, chroma-migrate issues documented
- [Vectara NAACL 2025 chunking study via SUMMARY.md](../../research/SUMMARY.md) — 400-600 token sweet spot with 10-15% overlap as research consensus
- [LangChain Sentence Transformers Integration](https://docs.langchain.com/oss/python/integrations/text_embedding/sentence_transformers) — HuggingFaceEmbeddings with model_kwargs usage pattern
- [Ubuntu 22.04 Python version documentation](https://documentation.ubuntu.com/ubuntu-for-developers/reference/availability/python/) — Python 3.10 confirmed as default on Ubuntu 22.04

### Tertiary (LOW confidence, requires validation)

- WebSearch results indicating langchain-chroma 1.1.0 chromadb version constraint — the exact `<0.7.0` vs `<1.0.0` boundary needs live verification with `pip show langchain-chroma` on the server
- ChromaDB SQLite file locking edge cases on reboot — documented in GitHub issues but rare; mitigation is absolute path + correct permissions

---

## Metadata

**Confidence breakdown:**
- Standard stack (ChromaDB embedded, LangChain, MiniLM): HIGH — multiple verified sources, well-established pattern
- Version pinning (chromadb==0.6.3): HIGH — incompatibility with 1.x confirmed from multiple sources; specific version may need adjustment to highest 0.6.x patch
- Architecture (two-stage chunking, breadcrumb prepend): HIGH — sourced from LangChain official docs + project SUMMARY.md research
- Pitfalls (chromadb version, chunk boundary): HIGH — sourced from real GitHub issues and prior project research
- Corpus inventory: HIGH — files verified to exist via directory listing
- Python 3.10 adequacy: HIGH — langchain-chroma 1.1.0 explicitly requires >=3.10

**Research date:** 2026-04-06
**Valid until:** 2026-07-06 (90 days — langchain and chromadb are moving targets; re-verify chromadb version constraint before planning if more than 30 days pass)
