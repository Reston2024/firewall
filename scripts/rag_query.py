#!/usr/bin/env python3
# scripts/rag_query.py — RAG query interface for manual testing and Phase 13 consumption
#
# Usage (CLI):
#   /opt/rag/bin/python3 scripts/rag_query.py "Why is Ollama bound to localhost?"
#   /opt/rag/bin/python3 scripts/rag_query.py "Why was monitor mode chosen for Suricata?" --k 5
#   /opt/rag/bin/python3 scripts/rag_query.py --llm "What security controls protect the Ollama API?"
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
# LLM (--llm flag): Foundation-Sec-8B via ChatOllama at http://localhost:11434
#   Requires temporal separation — Foundation-Sec-8B needs ~5.5GB RAM
#   Model auto-unloads after OLLAMA_KEEP_ALIVE=5m idle

import argparse
import os
import subprocess
import sys

# Force offline mode — model must be pre-cached
os.environ.setdefault("HF_HUB_OFFLINE", "1")

from langchain_community.vectorstores import Chroma
from langchain_community.embeddings import HuggingFaceEmbeddings

CHROMA_PATH = "/var/lib/chromadb"
COLLECTION_NAME = "firewall-corpus"
EMBED_MODEL = "all-MiniLM-L6-v2"
LLM_MODEL = "hf.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF"
OLLAMA_BASE_URL = "http://localhost:11434"
DEFAULT_K = 3

SECURITY_ANALYST_PROMPT = """You are a security analyst assistant for a local network security system.
Use the following context from operational documents to answer the question accurately.

Context:
{context}

Question: {question}

Answer (cite document sections where relevant):"""


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


def query_with_llm(question: str, k: int = DEFAULT_K) -> dict:
    """Run end-to-end RAG+LLM query: retrieve chunks, inject into prompt, query Foundation-Sec-8B.

    Requires temporal separation — Foundation-Sec-8B needs ~5.5GB RAM.
    Model: hf.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF via Ollama at localhost:11434.
    Model auto-unloads after OLLAMA_KEEP_ALIVE=5m idle.

    Args:
        question: Natural language query string.
        k: Number of chunks to retrieve. Default 3.

    Returns:
        Dict with keys: answer, sources, chunks.
    """
    # Check if Ollama service is running
    try:
        result = subprocess.run(
            ["systemctl", "is-active", "ollama"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.stdout.strip() != "active":
            print(
                "WARNING: Ollama service is not active (systemctl is-active ollama returned"
                f" '{result.stdout.strip()}'). Foundation-Sec-8B may not respond.",
                file=sys.stderr,
            )
            print(
                "  Start with: sudo systemctl start ollama",
                file=sys.stderr,
            )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        # systemctl not available (e.g., running locally on Windows); skip check
        pass

    # Retrieve chunks
    chunks = query_corpus(question, k=k)
    if not chunks:
        raise RuntimeError("No chunks retrieved from corpus — run rag_index.py first")

    # Build context from top-k chunks
    # Limit per-chunk context to 400 chars to stay within OLLAMA_CONTEXT_LENGTH=2048
    # 3 chunks × ~400 chars ≈ 1200 chars + prompt overhead ≈ 1650 tokens — within budget
    context_parts = []
    for chunk in chunks:
        context_parts.append(f"[Source: {chunk['source']}]\n{chunk['content'][:400]}")
    context = "\n\n---\n\n".join(context_parts)

    # Build prompt using security analyst template
    prompt = SECURITY_ANALYST_PROMPT.format(context=context, question=question)

    # Query Foundation-Sec-8B via Ollama OpenAI-compatible API
    # Using openai client directly — langchain_community.chat_models.ChatOllama (deprecated)
    # returns empty content in langchain 0.3.x + chromadb 0.6.3 environment.
    # openai client confirmed working via direct API calls.
    from openai import OpenAI  # type: ignore
    client = OpenAI(base_url=f"{OLLAMA_BASE_URL}/v1", api_key="ollama")
    completion = client.chat.completions.create(
        model=LLM_MODEL,
        messages=[{"role": "user", "content": prompt}],
        max_tokens=512,
        temperature=0.1,
    )
    answer = completion.choices[0].message.content.strip()

    return {
        "answer": answer,
        "sources": [chunk["source"] for chunk in chunks],
        "chunks": chunks,
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Query the firewall corpus RAG index",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 rag_query.py "Why is Ollama bound to localhost?"
  python3 rag_query.py "Why was monitor mode chosen for Suricata?" --k 5
  python3 rag_query.py "What is the ChromaDB migration plan for v3.0?"
  python3 rag_query.py --llm "What security controls protect the Ollama API?"
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
    parser.add_argument(
        "--llm",
        action="store_true",
        default=False,
        help=(
            "Enable end-to-end RAG+LLM mode: retrieve chunks then query Foundation-Sec-8B via Ollama. "
            "Requires temporal separation — Foundation-Sec-8B needs ~5.5GB RAM alongside ChromaDB/MiniLM. "
            f"Model: {LLM_MODEL} at {OLLAMA_BASE_URL}. "
            "OLLAMA_KEEP_ALIVE=5m — model auto-unloads after idle."
        ),
    )
    args = parser.parse_args()

    question = args.query
    k = args.k

    if k < 1:
        print("ERROR: --k must be >= 1", file=sys.stderr)
        sys.exit(1)
    if k > 10:
        print(f"WARNING: --k={k} may overflow OLLAMA_CONTEXT_LENGTH=2048 in Phase 13 triage", file=sys.stderr)

    if args.llm:
        # End-to-end RAG+LLM mode
        print(f"Query (RAG+LLM): {question}")
        print(f"k={k} | embed={EMBED_MODEL} | llm={LLM_MODEL}")
        print(f"Ollama base URL: {OLLAMA_BASE_URL}")
        print("NOTE: Foundation-Sec-8B needs ~5.5GB RAM. Apply temporal separation if Malcolm is running.")
        print()

        try:
            result = query_with_llm(question, k=k)
        except Exception as e:
            print(f"ERROR: End-to-end query failed: {e}", file=sys.stderr)
            print("Check that:", file=sys.stderr)
            print(f"  - Ollama is running: systemctl is-active ollama", file=sys.stderr)
            print(f"  - Foundation-Sec-8B model is loaded: ollama list | grep Foundation-Sec", file=sys.stderr)
            print(f"  - Temporal separation applied (Malcolm OpenSearch/Logstash paused if needed)", file=sys.stderr)
            sys.exit(1)

        print("=== Retrieved Chunks ===")
        for i, chunk in enumerate(result["chunks"], 1):
            print(f"--- Chunk {i} (score: {chunk['score']:.4f}, source: {chunk['source']}) ---")
            print(chunk["content"][:300])
            if len(chunk["content"]) > 300:
                print(f"  ... [{len(chunk['content']) - 300} chars truncated]")
            print()

        print("=== Foundation-Sec-8B Response ===")
        print(f"Sources: {result['sources']}")
        print()
        print(result["answer"])
    else:
        # Retrieval-only mode (default)
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
