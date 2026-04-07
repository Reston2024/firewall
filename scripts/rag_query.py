#!/usr/bin/env python3
# scripts/rag_query.py — RAG query interface for manual testing and Phase 13 consumption
#
# Usage (CLI):
#   /opt/rag/bin/python3 scripts/rag_query.py "Why is Ollama bound to localhost?"
#   /opt/rag/bin/python3 scripts/rag_query.py "Why was monitor mode chosen for Suricata?" --k 5
#
# Import (Phase 13 triage worker):
#   from scripts.rag_query import query_corpus
#   chunks = query_corpus("Explain this Suricata alert", k=3)
#
# Default k=3 to fit within OLLAMA_CONTEXT_LENGTH=2048 (per Phase 12 research Pitfall 6):
#   3 chunks × ~450 tokens + ~300 tokens overhead ≈ 1650 tokens — safely within 2048
#
# ChromaDB: /var/lib/chromadb (NVMe, PersistentClient)
# Embedding model: all-MiniLM-L6-v2 (CPU, offline)

import argparse
import os
import sys

# Force offline mode — model must be pre-cached
os.environ.setdefault("HF_HUB_OFFLINE", "1")

from langchain_community.vectorstores import Chroma
from langchain_community.embeddings import HuggingFaceEmbeddings

CHROMA_PATH = "/var/lib/chromadb"
COLLECTION_NAME = "firewall-corpus"
EMBED_MODEL = "all-MiniLM-L6-v2"
DEFAULT_K = 3


def query_corpus(question: str, k: int = DEFAULT_K) -> list[dict]:
    """Return top-k relevant chunks for a question.

    Args:
        question: Natural language query string.
        k: Number of chunks to retrieve. Default 3 (fits within OLLAMA_CONTEXT_LENGTH=2048).

    Returns:
        List of dicts with keys: content, source, score.
        Score is cosine distance (lower = more similar; 0.0 = identical).
    """
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
        {
            "content": doc.page_content,
            "source": doc.metadata.get("source", "unknown"),
            "score": float(score),
            "metadata": doc.metadata,
        }
        for doc, score in results
    ]


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Query the firewall corpus RAG index",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 rag_query.py "Why is Ollama bound to localhost?"
  python3 rag_query.py "Why was monitor mode chosen for Suricata?" --k 5
  python3 rag_query.py "What is the ChromaDB migration plan for v3.0?"
        """,
    )
    parser.add_argument(
        "query",
        nargs="?",
        default="What is the Ollama security configuration?",
        help="Query string (default: 'What is the Ollama security configuration?')",
    )
    parser.add_argument(
        "--k",
        type=int,
        default=DEFAULT_K,
        help=f"Number of chunks to retrieve (default: {DEFAULT_K}; max recommended: 5 for OLLAMA_CONTEXT_LENGTH=2048)",
    )
    args = parser.parse_args()

    question = args.query
    k = args.k

    if k < 1:
        print("ERROR: --k must be >= 1", file=sys.stderr)
        sys.exit(1)
    if k > 10:
        print(f"WARNING: --k={k} may overflow OLLAMA_CONTEXT_LENGTH=2048 in Phase 13 triage", file=sys.stderr)

    print(f"Query: {question}")
    print(f"k={k} | model={EMBED_MODEL} | db={CHROMA_PATH}")
    print()

    try:
        chunks = query_corpus(question, k=k)
    except Exception as e:
        print(f"ERROR: Query failed: {e}", file=sys.stderr)
        print("Check that:", file=sys.stderr)
        print(f"  - ChromaDB exists at {CHROMA_PATH}/chroma.sqlite3", file=sys.stderr)
        print(f"  - Collection '{COLLECTION_NAME}' has been indexed (run rag_index.py first)", file=sys.stderr)
        print(f"  - Embedding model is cached: ls ~/.cache/huggingface/hub/models--sentence-transformers--all-MiniLM-L6-v2/", file=sys.stderr)
        sys.exit(1)

    if not chunks:
        print("No results returned — collection may be empty. Run rag_index.py first.")
        sys.exit(1)

    for i, chunk in enumerate(chunks, 1):
        print(f"--- Chunk {i} (score: {chunk['score']:.4f}, source: {chunk['source']}) ---")
        print(chunk["content"][:500])
        if len(chunk["content"]) > 500:
            print(f"  ... [{len(chunk['content']) - 500} chars truncated]")
        print()


if __name__ == "__main__":
    main()
