#!/usr/bin/env python3
# scripts/rag_index.py — Corpus ingestion for Phase 12 RAG pipeline
# Run from repo root: /opt/rag/bin/python3 scripts/rag_index.py
#
# Indexes ADRs, runbooks, contracts, benchmarks, planning artifacts, and
# validation scripts into ChromaDB at /var/lib/chromadb using:
#   - Two-stage chunking for .md files: MarkdownHeaderTextSplitter → RecursiveCharacterTextSplitter
#   - Size-only chunking for .sh/.py files (no header splitting)
#   - Breadcrumb prepend: "[source_path] / # h1 / ## h2 / ### h3"
#   - Embedding: all-MiniLM-L6-v2 (CPU, offline via HF_HUB_OFFLINE=1)
#
# Sources:
#   LangChain MarkdownHeaderTextSplitter docs
#   ChromaDB PersistentClient docs

import os
import glob
import sys

# Force offline mode — embedding model must be pre-cached; do not attempt network download
os.environ.setdefault("HF_HUB_OFFLINE", "1")

import chromadb
from langchain_text_splitters import MarkdownHeaderTextSplitter, RecursiveCharacterTextSplitter
from langchain_community.embeddings import HuggingFaceEmbeddings
from langchain_community.vectorstores import Chroma

CHROMA_PATH = "/var/lib/chromadb"
COLLECTION_NAME = "firewall-corpus"
EMBED_MODEL = "all-MiniLM-L6-v2"

# Corpus globs (relative to repo root)
CORPUS_GLOBS = [
    "decisions/*.md",
    "docs/*.md",
    "docs/benchmarks/*.md",
    "contracts/*.md",
    "contracts/*.json",
    ".planning/REQUIREMENTS.md",
    ".planning/research/SUMMARY.md",
    ".planning/research/STACK.md",
    "scripts/validate-*.sh",
]


def load_corpus(repo_root: str) -> list[tuple[str, str]]:
    """Return list of (relative_path, content) tuples from all corpus globs."""
    seen = set()
    files = []
    for pattern in CORPUS_GLOBS:
        matched = glob.glob(os.path.join(repo_root, pattern), recursive=True)
        for path in sorted(matched):
            abs_path = os.path.abspath(path)
            if abs_path in seen:
                continue
            seen.add(abs_path)
            rel = os.path.relpath(abs_path, repo_root)
            try:
                with open(abs_path, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read().strip()
                if content:
                    files.append((rel, content))
            except OSError as e:
                print(f"  WARNING: Could not read {rel}: {e}", file=sys.stderr)
    return files


def chunk_markdown(rel_path: str, content: str) -> list[dict]:
    """Two-stage chunker for .md files: header-aware split then size-constrained split."""
    header_splitter = MarkdownHeaderTextSplitter(
        headers_to_split_on=[
            ("#", "h1"),
            ("##", "h2"),
            ("###", "h3"),
        ],
        strip_headers=False,  # Keep header text in chunk for context
    )
    char_splitter = RecursiveCharacterTextSplitter(
        chunk_size=1800,
        chunk_overlap=200,
        separators=["\n\n", "\n", " ", ""],
    )

    sections = header_splitter.split_text(content)
    chunks = []
    for section in sections:
        # Build breadcrumb: [source_path] / # h1 / ## h2 / ### h3
        breadcrumb = f"[{rel_path}]"
        if section.metadata.get("h1"):
            breadcrumb += f" / # {section.metadata['h1']}"
        if section.metadata.get("h2"):
            breadcrumb += f" / ## {section.metadata['h2']}"
        if section.metadata.get("h3"):
            breadcrumb += f" / ### {section.metadata['h3']}"

        sub_chunks = char_splitter.split_text(section.page_content)
        for sub in sub_chunks:
            if not sub.strip():
                continue
            chunks.append({
                "content": breadcrumb + "\n\n" + sub,
                "metadata": {
                    "source": rel_path,
                    **{k: v for k, v in section.metadata.items()},
                },
            })
    return chunks


def chunk_text(rel_path: str, content: str) -> list[dict]:
    """Size-only chunker for .sh, .py, .json and other non-Markdown files."""
    char_splitter = RecursiveCharacterTextSplitter(
        chunk_size=1800,
        chunk_overlap=200,
        separators=["\n\n", "\n", " ", ""],
    )
    sub_chunks = char_splitter.split_text(content)
    chunks = []
    for i, sub in enumerate(sub_chunks):
        if not sub.strip():
            continue
        chunks.append({
            "content": f"[{rel_path}]\n\n{sub}",
            "metadata": {"source": rel_path, "chunk_index": i},
        })
    return chunks


def chunk_file(rel_path: str, content: str) -> list[dict]:
    """Route to correct splitter based on file extension."""
    if rel_path.endswith(".md"):
        return chunk_markdown(rel_path, content)
    else:
        # Shell scripts, Python scripts, JSON — size-only splitting
        return chunk_text(rel_path, content)


def main() -> None:
    # Resolve repo root: scripts/ is one level below repo root
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    print(f"=== RAG Corpus Ingestion ===")
    print(f"Repo root : {repo_root}")
    print(f"ChromaDB  : {CHROMA_PATH}")
    print(f"Collection: {COLLECTION_NAME}")
    print(f"Model     : {EMBED_MODEL}")
    print()

    # Load all corpus files
    print("Loading corpus...")
    files = load_corpus(repo_root)
    print(f"  Found {len(files)} files")
    print()

    # Chunk all files
    print("Chunking files...")
    all_chunks: list[dict] = []
    for rel_path, content in files:
        chunks = chunk_file(rel_path, content)
        all_chunks.extend(chunks)
        print(f"  {rel_path}: {len(chunks)} chunks")

    print()
    print(f"Total chunks: {len(all_chunks)}")

    if not all_chunks:
        print("ERROR: No chunks produced — check CORPUS_GLOBS and file paths.", file=sys.stderr)
        sys.exit(1)

    # Initialize embedding model (must be pre-cached; HF_HUB_OFFLINE=1 prevents network calls)
    print()
    print(f"Loading embedding model: {EMBED_MODEL} (device=cpu, offline)...")
    embeddings = HuggingFaceEmbeddings(
        model_name=EMBED_MODEL,
        model_kwargs={"device": "cpu"},
    )

    # Initialize ChromaDB vector store
    print(f"Initializing ChromaDB at {CHROMA_PATH}...")
    vector_store = Chroma(
        collection_name=COLLECTION_NAME,
        embedding_function=embeddings,
        persist_directory=CHROMA_PATH,
        collection_metadata={"hnsw:space": "cosine"},
    )

    # Upsert all chunks (idempotent — safe to re-run; existing IDs are updated)
    print("Embedding and upserting chunks (this may take a few minutes on CPU)...")
    texts = [c["content"] for c in all_chunks]
    metadatas = [c["metadata"] for c in all_chunks]
    # Deterministic IDs: source + position index — allows idempotent re-indexing
    ids = [f"{c['metadata']['source'].replace(os.sep, '/')}-{i}" for i, c in enumerate(all_chunks)]

    # Upsert in batches of 100 to avoid memory spikes
    BATCH_SIZE = 100
    for batch_start in range(0, len(texts), BATCH_SIZE):
        batch_end = min(batch_start + BATCH_SIZE, len(texts))
        vector_store.add_texts(
            texts=texts[batch_start:batch_end],
            metadatas=metadatas[batch_start:batch_end],
            ids=ids[batch_start:batch_end],
        )
        print(f"  Upserted chunks {batch_start + 1}–{batch_end} / {len(texts)}")

    print()
    print(f"Indexed {len(all_chunks)} chunks into collection '{COLLECTION_NAME}'")

    # Verify persistence by re-opening a fresh PersistentClient
    print()
    print("Verifying persistence...")
    verify_client = chromadb.PersistentClient(path=CHROMA_PATH)
    count = verify_client.get_collection(COLLECTION_NAME).count()
    print(f"  Verification: collection '{COLLECTION_NAME}' count = {count} chunks")

    if count == 0:
        print("ERROR: Collection count is 0 after indexing — persistence verification failed.", file=sys.stderr)
        sys.exit(1)
    elif count < 100:
        print(f"WARNING: Collection has only {count} chunks (expected 150-300). Check corpus globs.")
    else:
        print(f"  OK: {count} chunks persisted to {CHROMA_PATH}/chroma.sqlite3")

    print()
    print("=== Ingestion complete ===")


if __name__ == "__main__":
    main()
