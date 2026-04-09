# DEPRECATED — ADR-E04: AI removed from data layer. This script validated
# components that have been removed from supportTAK-server. Retained for
# audit trail only. Do not run.
#
#!/usr/bin/env bash
# validate-phase12.sh — Phase 12 RAG Knowledge Pipeline validation suite
# Run FROM local machine — SSHes to supportTAK-server (192.168.1.22) as opsadmin
# Usage: bash scripts/validate-phase12.sh [--full]
# Quick mode (default): RAG-01, RAG-02, RAG-03 checks
# Full mode (--full): includes RAG-04 end-to-end Foundation-Sec-8B check

set -euo pipefail

FULL=false
if [[ "${1:-}" == "--full" ]]; then FULL=true; fi

PASS=0
FAIL=0
SKIP=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "SKIP: $1"; SKIP=$((SKIP + 1)); }

TARGET="opsadmin@192.168.1.22"
SSH_OPTS="-o StrictHostKeyChecking=yes -o ConnectTimeout=15 -o BatchMode=yes"
RAG_PYTHON="/opt/rag/bin/python3"
CHROMA_PATH="/var/lib/chromadb"
COLLECTION="firewall-corpus"
REPO="$HOME/Firewall"   # unused locally; used in server-side commands

echo "=== Phase 12 Validation Suite — RAG Knowledge Pipeline — $(date) ==="
echo ""

# ---------------------------------------------------------------------------
# RAG-01: ChromaDB persistence on NVMe
# ---------------------------------------------------------------------------
echo "[RAG-01a] chroma.sqlite3 exists at ${CHROMA_PATH}"

RAG01A_OUT=$(ssh $SSH_OPTS "$TARGET" \
  "[ -f '${CHROMA_PATH}/chroma.sqlite3' ] && echo 'FOUND' || echo 'MISSING'" 2>/dev/null)
RAG01A_EXIT=$?

if [ $RAG01A_EXIT -ne 0 ] || [ -z "$RAG01A_OUT" ]; then
  fail "RAG-01a: Cannot reach supportTAK-server. Check: ssh $TARGET ls -la ${CHROMA_PATH}/"
elif echo "$RAG01A_OUT" | grep -q "FOUND"; then
  pass "RAG-01a: ${CHROMA_PATH}/chroma.sqlite3 exists on NVMe"
else
  fail "RAG-01a: chroma.sqlite3 NOT found at ${CHROMA_PATH}/. Run rag_index.py to index corpus."
fi
echo ""

# --- RAG-01b: PersistentClient connects without error ---
echo "[RAG-01b] PersistentClient(path='${CHROMA_PATH}') connects without error"

RAG01B_OUT=$(ssh $SSH_OPTS "$TARGET" \
  "${RAG_PYTHON} -c \"
import chromadb, sys
try:
    c = chromadb.PersistentClient(path='${CHROMA_PATH}')
    print('CONNECT_OK')
except Exception as e:
    print('ERROR:', e, file=sys.stderr)
    sys.exit(1)
\" 2>/dev/null" 2>/dev/null)
RAG01B_EXIT=$?

if [ $RAG01B_EXIT -ne 0 ] || [ -z "$RAG01B_OUT" ]; then
  fail "RAG-01b: PersistentClient failed to connect to ${CHROMA_PATH}. Check chromadb installation."
elif echo "$RAG01B_OUT" | grep -q "CONNECT_OK"; then
  pass "RAG-01b: PersistentClient connects to ${CHROMA_PATH} without error"
else
  fail "RAG-01b: Unexpected output: $RAG01B_OUT"
fi
echo ""

# --- RAG-01c: Collection exists and has chunks ---
echo "[RAG-01c] Collection '${COLLECTION}' exists and count > 0"

RAG01C_OUT=$(ssh $SSH_OPTS "$TARGET" \
  "${RAG_PYTHON} -c \"
import chromadb, sys
c = chromadb.PersistentClient(path='${CHROMA_PATH}')
try:
    col = c.get_collection('${COLLECTION}')
    count = col.count()
    print(count)
except Exception as e:
    print('ERROR:', e, file=sys.stderr)
    sys.exit(1)
\" 2>/dev/null" 2>/dev/null)
RAG01C_EXIT=$?

if [ $RAG01C_EXIT -ne 0 ] || [ -z "$RAG01C_OUT" ]; then
  fail "RAG-01c: Cannot get collection '${COLLECTION}'. Run rag_index.py to create and populate it."
elif echo "$RAG01C_OUT" | grep -qE "^[1-9][0-9]+$"; then
  CHUNK_COUNT="$RAG01C_OUT"
  pass "RAG-01c: Collection '${COLLECTION}' has ${CHUNK_COUNT} chunks (persisted)"
else
  fail "RAG-01c: Collection count returned unexpected value: '$RAG01C_OUT'"
fi
echo ""

# ---------------------------------------------------------------------------
# RAG-02: all-MiniLM-L6-v2 embedding model
# ---------------------------------------------------------------------------
echo "[RAG-02a] all-MiniLM-L6-v2 model cached in ~/.cache/huggingface"

RAG02A_OUT=$(ssh $SSH_OPTS "$TARGET" \
  "[ -d ~/.cache/huggingface/hub/models--sentence-transformers--all-MiniLM-L6-v2 ] && echo 'CACHED' || echo 'MISSING'" 2>/dev/null)
RAG02A_EXIT=$?

if [ $RAG02A_EXIT -ne 0 ] || [ -z "$RAG02A_OUT" ]; then
  fail "RAG-02a: Cannot check model cache on supportTAK-server"
elif echo "$RAG02A_OUT" | grep -q "CACHED"; then
  pass "RAG-02a: all-MiniLM-L6-v2 model cached at ~/.cache/huggingface/hub/"
else
  fail "RAG-02a: Model not cached. Run: /opt/rag/bin/python3 -c \"from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')\""
fi
echo ""

# --- RAG-02b: Embedding generation works offline (HF_HUB_OFFLINE=1) ---
echo "[RAG-02b] Embedding generation works offline (HF_HUB_OFFLINE=1, 384-dim output)"

RAG02B_OUT=$(ssh $SSH_OPTS "$TARGET" \
  "HF_HUB_OFFLINE=1 ${RAG_PYTHON} -c \"
from sentence_transformers import SentenceTransformer
model = SentenceTransformer('all-MiniLM-L6-v2')
emb = model.encode(['test query'])
dim = emb.shape[1]
print(dim)
\" 2>/dev/null" 2>/dev/null)
RAG02B_EXIT=$?

if [ $RAG02B_EXIT -ne 0 ] || [ -z "$RAG02B_OUT" ]; then
  fail "RAG-02b: Embedding generation failed offline. Check that model is cached (RAG-02a) and HF_HUB_OFFLINE=1 works."
elif echo "$RAG02B_OUT" | grep -q "^384$"; then
  pass "RAG-02b: Embedding generation OK offline — 384-dim output confirmed"
else
  fail "RAG-02b: Unexpected embedding dimension: '$RAG02B_OUT' (expected 384)"
fi
echo ""

# --- RAG-02c: Foundation-Sec-8B NOT used for embeddings ---
echo "[RAG-02c] rag_index.py uses all-MiniLM-L6-v2 (not Foundation-Sec-8B) for embeddings"

RAG02C_OUT=$(ssh $SSH_OPTS "$TARGET" \
  "grep -q 'all-MiniLM-L6-v2' ~/Firewall/scripts/rag_index.py && echo 'MINILM_FOUND' || echo 'MINILM_MISSING'" 2>/dev/null)
RAG02C_EXIT=$?

RAG02C_FSEC=$(ssh $SSH_OPTS "$TARGET" \
  "grep -qE 'Foundation-Sec|fdtn-ai' ~/Firewall/scripts/rag_index.py && echo 'FSEC_IN_EMBEDDINGS' || echo 'FSEC_ABSENT'" 2>/dev/null)

if [ $RAG02C_EXIT -ne 0 ] || [ -z "$RAG02C_OUT" ]; then
  fail "RAG-02c: Cannot check rag_index.py on supportTAK-server"
elif echo "$RAG02C_OUT" | grep -q "MINILM_FOUND" && echo "$RAG02C_FSEC" | grep -q "FSEC_ABSENT"; then
  pass "RAG-02c: rag_index.py uses all-MiniLM-L6-v2 — Foundation-Sec-8B NOT in embedding path"
elif echo "$RAG02C_OUT" | grep -q "MINILM_MISSING"; then
  fail "RAG-02c: all-MiniLM-L6-v2 not found in rag_index.py"
else
  fail "RAG-02c: Foundation-Sec-8B reference found in rag_index.py embedding section — ADR-E02 risk. Review script."
fi
echo ""

# ---------------------------------------------------------------------------
# RAG-03: Corpus indexing quality
# ---------------------------------------------------------------------------
echo "[RAG-03a] Collection chunk count >= 100 (expected 150-300)"

RAG03A_COUNT="${RAG01C_OUT:-0}"
# Reuse count from RAG-01c if available
if [ -z "$RAG03A_COUNT" ] || ! echo "$RAG03A_COUNT" | grep -qE "^[0-9]+$"; then
  RAG03A_COUNT=$(ssh $SSH_OPTS "$TARGET" \
    "${RAG_PYTHON} -c \"
import chromadb
c = chromadb.PersistentClient(path='${CHROMA_PATH}')
col = c.get_collection('${COLLECTION}')
print(col.count())
\" 2>/dev/null" 2>/dev/null || echo "0")
fi

if echo "$RAG03A_COUNT" | grep -qE "^[0-9]+$" && [ "$RAG03A_COUNT" -ge 100 ] 2>/dev/null; then
  pass "RAG-03a: Collection has ${RAG03A_COUNT} chunks (>= 100 minimum)"
elif echo "$RAG03A_COUNT" | grep -qE "^[0-9]+$" && [ "$RAG03A_COUNT" -gt 0 ] 2>/dev/null; then
  fail "RAG-03a: Collection has only ${RAG03A_COUNT} chunks — below 100 minimum. Re-run rag_index.py."
else
  fail "RAG-03a: Cannot determine chunk count or collection is empty."
fi
echo ""

# --- RAG-03b: ADR rationale query returns ADR-E02 source ---
echo "[RAG-03b] ADR rationale query returns chunk from ADR-E02"

RAG03B_OUT=$(ssh $SSH_OPTS "$TARGET" \
  "cd ~/Firewall && HF_HUB_OFFLINE=1 ${RAG_PYTHON} scripts/rag_query.py \
  'What is the rationale for binding Ollama to localhost?' 2>/dev/null | grep 'source:'" 2>/dev/null)
RAG03B_EXIT=$?

if [ $RAG03B_EXIT -ne 0 ] || [ -z "$RAG03B_OUT" ]; then
  fail "RAG-03b: ADR rationale query failed. Check that collection is indexed and query script works."
elif echo "$RAG03B_OUT" | grep -qi "ADR-E02"; then
  pass "RAG-03b: ADR rationale query returns chunk from ADR-E02 (Ollama localhost binding)"
else
  fail "RAG-03b: ADR rationale query did not return ADR-E02 chunk. Got sources: $RAG03B_OUT"
fi
echo ""

# --- RAG-03c: ADR decision query returns ADR-0007 source ---
echo "[RAG-03c] ADR decision query returns chunk from ADR-0007"

RAG03C_OUT=$(ssh $SSH_OPTS "$TARGET" \
  "cd ~/Firewall && HF_HUB_OFFLINE=1 ${RAG_PYTHON} scripts/rag_query.py \
  'Why was monitor mode chosen for Suricata?' 2>/dev/null | grep 'source:'" 2>/dev/null)
RAG03C_EXIT=$?

if [ $RAG03C_EXIT -ne 0 ] || [ -z "$RAG03C_OUT" ]; then
  fail "RAG-03c: ADR decision query failed. Check that collection is indexed and query script works."
elif echo "$RAG03C_OUT" | grep -qi "ADR-0007"; then
  pass "RAG-03c: ADR decision query returns chunk from ADR-0007 (Suricata monitor mode)"
else
  fail "RAG-03c: ADR decision query did not return ADR-0007 chunk. Got sources: $RAG03C_OUT"
fi
echo ""

# --- RAG-03d: No chunk exceeds 2200 characters ---
echo "[RAG-03d] No chunk exceeds 2200 characters (sample of first 10 chunks)"

RAG03D_OUT=$(ssh $SSH_OPTS "$TARGET" \
  "${RAG_PYTHON} -c \"
import chromadb
c = chromadb.PersistentClient(path='${CHROMA_PATH}')
col = c.get_collection('${COLLECTION}')
result = col.peek(10)
docs = result.get('documents', [])
over_limit = [(i, len(d)) for i, d in enumerate(docs) if len(d) > 2200]
if over_limit:
    for i, length in over_limit:
        print(f'OVER_LIMIT chunk {i}: {length} chars')
else:
    max_len = max((len(d) for d in docs), default=0)
    print(f'OK max_sampled={max_len}')
\" 2>/dev/null" 2>/dev/null)
RAG03D_EXIT=$?

if [ $RAG03D_EXIT -ne 0 ] || [ -z "$RAG03D_OUT" ]; then
  fail "RAG-03d: Cannot sample chunks from collection for size check."
elif echo "$RAG03D_OUT" | grep -q "OVER_LIMIT"; then
  fail "RAG-03d: Chunks exceed 2200 char limit: $RAG03D_OUT"
else
  pass "RAG-03d: Chunk size check OK — $RAG03D_OUT"
fi
echo ""

# ---------------------------------------------------------------------------
# RAG-04: End-to-end check (Foundation-Sec-8B) — --full flag only
# ---------------------------------------------------------------------------
echo "[RAG-04] End-to-end RAG + Foundation-Sec-8B check"

if $FULL; then
  RAG04_OUT=$(ssh $SSH_OPTS "$TARGET" \
    "cd ~/Firewall && HF_HUB_OFFLINE=1 ${RAG_PYTHON} -c \"
import os, sys
os.environ['HF_HUB_OFFLINE'] = '1'
sys.path.insert(0, '.')
from scripts.rag_query import query_corpus
from openai import OpenAI

# Retrieve top-3 chunks
question = 'Why is Ollama bound to localhost and what are the security implications?'
chunks = query_corpus(question, k=3)
context = '\n\n'.join(c['content'][:400] for c in chunks)
sources = [c['source'] for c in chunks]

# Query Foundation-Sec-8B via Ollama OpenAI-compatible API
client = OpenAI(base_url='http://localhost:11434/v1', api_key='ollama')
response = client.chat.completions.create(
    model='hf.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF',
    messages=[
        {'role': 'user', 'content': f'Context:\n{context}\n\nQuestion: {question}\n\nAnswer briefly:'}
    ],
    max_tokens=200,
    temperature=0.1,
)
answer = response.choices[0].message.content.strip()
if answer and len(answer) > 20:
    print('ANSWER_OK')
    print('Sources:', sources)
    print('Answer preview:', answer[:200])
else:
    print('ANSWER_EMPTY')
    sys.exit(1)
\" 2>&1 | grep -v 'LangChainDeprecation\|Failed to send\|W:onnx'" 2>/dev/null)
  RAG04_EXIT=$?

  if [ $RAG04_EXIT -ne 0 ] || [ -z "$RAG04_OUT" ]; then
    fail "RAG-04: End-to-end test failed. Check that Foundation-Sec-8B is loaded in Ollama and temporal separation policy is applied (stop Malcolm's OpenSearch/Logstash if needed)."
  elif echo "$RAG04_OUT" | grep -q "ANSWER_OK"; then
    pass "RAG-04: End-to-end RAG + Foundation-Sec-8B returned coherent response"
    echo "  $RAG04_OUT"
  elif echo "$RAG04_OUT" | grep -qE "more system memory|cannot allocate|oom"; then
    fail "RAG-04: Insufficient RAM for Foundation-Sec-8B alongside Malcolm. Apply temporal separation: sudo docker stop malcolm-opensearch-1 malcolm-logstash-1"
  else
    fail "RAG-04: End-to-end test returned unexpected output: $RAG04_OUT"
  fi
else
  skip "RAG-04: End-to-end Foundation-Sec-8B check — run with --full flag to execute"
  echo "  Note: RAG-04 requires temporal separation (Foundation-Sec-8B needs ~5.5GB RAM)."
  echo "  Apply: sudo docker stop malcolm-opensearch-1 malcolm-logstash-1 on supportTAK-server"
  echo "  Then: bash scripts/validate-phase12.sh --full"
fi
echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "=== Phase 12 Validation Summary ==="
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "=== FAILED: ${FAIL} check(s) require attention ==="
  exit "$FAIL"
else
  echo "=== ALL CHECKS PASS (${SKIP} skipped) ==="
  exit 0
fi
