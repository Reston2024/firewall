# Stack Research

**Domain:** Local AI SOC — Malcolm NSM + Local LLM Inference + RAG + SBOM on supportTAK-server
**Researched:** 2026-03-31
**Confidence:** MEDIUM overall — Malcolm RAM constraint verified, AI inference speeds estimated from comparable hardware (no N150-specific LLM benchmarks exist in public sources), RAG stack choices HIGH confidence

---

## CRITICAL: RAM Budget Constraint

The supportTAK-server has **16GB RAM total** (Intel N150, 4 cores). Malcolm's documented minimum is **24GB**. This is the defining architectural constraint for all v2.0 decisions.

### RAM Budget Analysis

| Component | Min Viable | Comfortable | Notes |
|-----------|-----------|-------------|-------|
| Ubuntu OS + kernel | 1.5 GB | 2.0 GB | Base system overhead |
| Malcolm: OpenSearch JVM heap | 6.0 GB | 10.0 GB | Docs say "not recommended below 10g" — 6g is survivable for low-traffic home network |
| Malcolm: Logstash JVM | 1.0 GB | 3.0 GB | `LS_JAVA_OPTS=-Xmx1g` constrained from default 3-4g |
| Malcolm: supporting containers (Zeek, Arkime, filebeat, netbox, dashboards, nginx, etc.) | 2.5 GB | 3.5 GB | 8+ containers with persistent processes |
| **Malcolm total** | **9.5 GB** | **16.5 GB** | At minimum settings Malcolm just fits; comfortable settings overflow |
| Foundation-Sec-8B Q4_K_M (model weights + KV cache at ctx=4096) | 5.5 GB | 6.0 GB | ~4.92 GB model file + ~0.5 GB KV cache |
| Ollama server process (idle) | 0.05 GB | 0.1 GB | ~43 MB at idle with no model loaded |
| Embedding model (all-MiniLM-L6-v2, in-process) | 0.3 GB | 0.5 GB | 22M parameters, loaded during RAG ingestion/query |
| ChromaDB (embedded/in-process) | 0.1 GB | 0.3 GB | Hundreds of documents; in-process with no separate server |
| RAG Python process (langchain + orchestration) | 0.3 GB | 0.5 GB | Runtime overhead for orchestration layer |
| **AI analyst total (model loaded)** | **6.25 GB** | **7.4 GB** | — |

**Worst case (all concurrent):** 9.5 + 6.25 = **~15.75 GB** — technically fits at minimum settings with ~250 MB headroom. Any memory spike (GC pressure, PCAP burst) overflows to swap.

### Architecture Decision: Constrained-Heap Malcolm + On-Demand AI

- Malcolm runs persistently at reduced JVM heap: OpenSearch `-Xms6g -Xmx6g`, Logstash `-Xmx1g`
- Foundation-Sec-8B loads on-demand via Ollama with `OLLAMA_KEEP_ALIVE=5m` (unloads after 5 minutes of idle)
- Do NOT run bulk PCAP ingestion simultaneously with AI triage sessions
- Configure swap (at minimum 4GB zram or disk swap) as OOM safety net — not as working memory
- Monitor with `free -m` and watch Logstash GC logs after deployment; tune heap up/down based on observed behavior

**Upgrade path:** If RAM proves insufficient in practice, upgrade N150 to 32GB SO-DIMM (verify DDR5 slot count and max supported RAM for specific board). 32GB makes all of this comfortable.

---

## Recommended Stack

### Core Technologies (New in v2.0)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Malcolm NSM | v26.02.0 (Feb 19, 2026) | Full NSM suite: Zeek, Suricata integration, PCAP capture and replay, OpenSearch Dashboards, Arkime full-packet search | CISA/Idaho National Laboratory maintained (Apache 2.0). Single Docker Compose deployment. Replaces Loki + Alloy + Grafana. Ships OpenSearch 3.5.0, Zeek 8.0.6, Logstash. Pre-built dashboards. Accepts Suricata EVE JSON from IPFire directly via Logstash Beats input. |
| OpenSearch | 3.5.0 | Log indexing, search, and vector store (k-NN plugin) | Bundled inside Malcolm — do not install separately. Malcolm v26.02.0 ships OS 3.5.0. Includes k-NN plugin for future vector search without separate ChromaDB instance. |
| Zeek | 8.0.6 | Deep packet inspection, protocol-level metadata extraction | Bundled inside Malcolm. Generates structured logs: conn.log, dns.log, http.log, ssl.log, files.log, x509.log — far richer than Suricata alerts alone. |
| Ollama | 0.18.2 (current Mar 2026) | Local LLM inference server with OpenAI-compatible API | ~43 MB idle RAM footprint. `OLLAMA_KEEP_ALIVE` unloads model from RAM after configurable idle period. Native GGUF support. OpenAI-compatible `/v1/chat/completions` and `/v1/embeddings` API — any Python client works pointed at `http://localhost:11434`. Simpler ops than raw llama.cpp server. |
| Foundation-Sec-8B Q4_K_M | — (from fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF on HuggingFace) | Cybersecurity-domain AI analyst | Llama 3.1 8B architecture continued-pretrained on CVEs, threat intel reports, exploit write-ups, compliance frameworks. Benchmarks comparable to Llama-3.1-70B on cybersecurity tasks (per authors). Q4_K_M: 4.92 GB on disk, 92% quality retention vs. full precision. Only viable quantization level for 16GB system. |
| ChromaDB | 0.6.x (embedded mode) | Vector store for RAG document corpus | Embedded (in-process), zero network latency, no separate server process. Suitable for corpus of hundreds to low thousands of documents (ADRs, runbooks, CVE summaries, Suricata rule descriptions, control docs). Minimal RAM overhead. |
| sentence-transformers (all-MiniLM-L6-v2) | sentence-transformers 3.x | Text embedding for RAG retrieval | 22M parameter model, 384-dim embeddings, ~90 MB weights, CPU inference in milliseconds per chunk. Standard lightweight English retrieval embedding. Sufficient quality for security document RAG where terminology is precise. |
| Syft | 1.42.0 (Feb 2026) | SBOM generation from filesystem and container images | Anchore open-source (Apache 2.0). Auto-detects Alpine/Debian/RPM/pip/npm/Go/Rust. Generates CycloneDX JSON/XML and SPDX JSON/YAML. Runs fully offline. Integrates into release scripts with single command. |
| Grype | latest stable (Anchore) | Vulnerability scanning against SBOM | Pairs with Syft — pipe Syft output directly via stdin. Cross-references against NVD, GitHub Advisory, Red Hat, Debian, Ubuntu feeds. |
| cosign | v3.x (Sigstore) | Sign release artifacts, SBOM files, and checksum manifests | Keyless signing via Sigstore Fulcio CA + Rekor transparency log. Signs arbitrary blobs with `cosign sign-blob`. v3 requires `--bundle` flag — use from the start to avoid migration. |

### Supporting Libraries (Python RAG Stack)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| langchain | 0.3.x | RAG orchestration — document loading, chunking, retrieval chains, prompt templates | Core orchestration layer connecting ChromaDB, embeddings, and Ollama |
| langchain-community | 0.3.x | Community integrations including OpenSearch vector store loader | Needed for OpenSearch k-NN integration (future migration from ChromaDB) |
| langchain-chroma | 0.1.x | LangChain ChromaDB integration | Stable ChromaDB integration in LangChain 0.3.x ecosystem |
| chromadb | 0.6.x | Vector store Python client | Direct API; embedded mode requires no separate process |
| sentence-transformers | 3.x | Embedding model wrapper providing `.encode()` | Document indexing and query embedding |
| openai | 1.x | OpenAI-compatible client for Ollama API | Point at `http://localhost:11434/v1` — standard Python client works unchanged |
| pypdf | latest | PDF ingestion for runbooks and compliance docs | When corpus includes PDF files |
| markdown-it-py | latest | Markdown parsing for ADRs and runbooks | For `.md` files from the project repo |

### Development and Release Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Syft | SBOM generation | `syft dir:. -o cyclonedx-json > sbom.json` for repo filesystem scan |
| Grype | Vulnerability scan against SBOM | `syft dir:. -o cyclonedx-json \| grype` for direct pipeline |
| cosign v3 | Artifact signing | `cosign sign-blob SHA256SUMS --bundle SHA256SUMS.sigstore.json` |
| sha256sum | Checksum file for release assets | Generate `SHA256SUMS` covering all release files; sign with cosign |
| Docker Compose v2 | Malcolm stack orchestration | Malcolm ships its own `docker-compose.yml` — do not merge with previous Grafana compose. Run as separate project in `/opt/malcolm`. |

---

## Installation

```bash
# --- Malcolm NSM (on supportTAK-server) ---
# Prerequisites: Docker Engine >= 26.x, Docker Compose v2
docker --version && docker compose version

# Clone and install
git clone --depth 1 https://github.com/cisagov/Malcolm.git /opt/malcolm
cd /opt/malcolm
python3 scripts/install.py   # interactive; answer Y to all, configure credentials

# CRITICAL: Edit memory settings for 16GB system BEFORE first start
# In /opt/malcolm/docker-compose.yml (or .env file that configure generates):
#   OPENSEARCH_JAVA_OPTS: "-Xms6g -Xmx6g"
#   LS_JAVA_OPTS: "-Xmx1g -Xms1g"

# Start Malcolm
cd /opt/malcolm && docker compose up -d

# Verify all containers healthy (~2-3 min startup)
docker compose ps

# --- Ollama (on supportTAK-server, native install — NOT in Docker) ---
# Native install avoids Docker networking overhead and allows direct RAM management
curl -fsSL https://ollama.com/install.sh | sh

# Configure keep-alive via systemd override
mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf <<EOF
[Service]
Environment="OLLAMA_KEEP_ALIVE=5m"
Environment="OLLAMA_HOST=127.0.0.1:11434"
EOF
systemctl daemon-reload && systemctl restart ollama

# Pull Foundation-Sec-8B Q4_K_M (~4.92 GB download)
# Official GGUF from fdtn-ai (model authors)
ollama pull hf.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF

# Verify inference works
ollama run hf.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF "Summarize CVE-2024-12345"

# --- Python RAG Stack ---
pip install langchain langchain-community langchain-chroma \
            chromadb sentence-transformers \
            openai pypdf markdown-it-py

# Prefetch embedding model (downloads ~90 MB from HuggingFace)
python3 -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"

# --- SBOM + Signing Tools ---
# Syft
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin
syft version

# Grype
curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin
grype version

# Cosign v3
COSIGN_VERSION=$(curl -s https://api.github.com/repos/sigstore/cosign/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
curl -sSfL "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64" \
     -o /usr/local/bin/cosign
chmod +x /usr/local/bin/cosign
cosign version

# --- Configure swap (OOM safety net) ---
# 4GB zram (fast, compressed, uses CPU not disk)
apt install zram-config || modprobe zram
# OR disk swap if zram not available
fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw,pri=10 0 0' >> /etc/fstab
```

---

## Malcolm Ingestion Path from IPFire Suricata

v1.0 pipeline: `IPFire rsyslog/SCP → Alloy → Loki`

v2.0 pipeline: `IPFire → rsyslog/SCP → Malcolm Logstash (Beats port 5044) → OpenSearch`

Malcolm's Logstash instance accepts multiple input methods:

| Input Method | Malcolm Port | Configuration | Recommended For |
|--------------|-------------|---------------|-----------------|
| Beats protocol | 5044 (TCP) | Configure Alloy on supportTAK-server to use `otelcol.exporter.otlp` or Beats output targeting Malcolm's Logstash | Most reliable structured log ingestion |
| Syslog (UDP) | 514 | IPFire WUI syslog forward → Malcolm nginx → Logstash syslog input | Simpler but less structured |
| PCAP upload | 8443 (HTTPS) | Malcolm web UI or `curl` API upload | For batch PCAP analysis |
| Zeek log forward | via SFTP/SCP | Malcolm has a `zeek-logs` container watching a directory | If running Zeek on sensor separately |

**Migration approach:** During Malcolm standup, keep Alloy running temporarily. Switch Alloy's output from `loki.write` to a Beats output (via `loki.source.syslog` → relabel → `otelcol.exporter.loki` to Malcolm's Beats endpoint). This allows side-by-side validation before decommissioning Loki.

---

## Inference Speed Expectations on N150 (Intel, 4 cores)

No N150-specific LLM benchmarks exist in public sources as of March 2026. These are estimates from comparable Intel iGPU hardware.

| Mode | Quantization | Token Generation | Prompt Processing | Response Time (500 tokens) |
|------|-------------|-----------------|-------------------|---------------------------|
| CPU-only | Q4_K_M | 3–8 t/s | 50–100 t/s | 60–165 seconds |
| iGPU via Vulkan | Q4_K_M | 8–12 t/s | 100–200 t/s | 40–60 seconds |

**Confidence: LOW** — Based on Intel Iris Xe (TGL GT2) Vulkan results showing ~10.58 t/s tg128 for 7B Q4_0 in llama.cpp discussions. N150 has a newer but similar-tier integrated graphics architecture.

**Vulkan availability:** Ollama's iGPU Vulkan support for Intel is available but experimental as of early 2026. Test after deployment with `ollama run --verbose` and check for GPU layer offload in logs. Do not design the triage workflow assuming iGPU acceleration — design for CPU-only speeds, treat iGPU as a bonus.

**Design implication:** At 3–8 t/s, a 500-token triage summary takes 60–165 seconds. Implement triage as an asynchronous job (submit alert → wait → retrieve result), not a synchronous blocking call. Interactive chat mode will feel slow — acceptable for analyst workflows but not for automated alert pipelines.

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|------------------------|
| Malcolm v26.02.0 | Arkime standalone + separate OpenSearch | Only if Malcolm multi-container overhead proves too high. Arkime alone uses ~2-3 GB less RAM but loses Zeek protocol metadata and pre-built Malcolm dashboards. Not worth the loss of capability for this use case. |
| Ollama 0.18.2 | llama.cpp server (direct binary) | If Ollama abstraction causes issues: llama.cpp server is ~90 MB, slightly faster per-request, fully configurable context size via `--ctx-size` flag. Use llama.cpp directly for scripted batch triage pipelines where Ollama's model management overhead is unnecessary. |
| Foundation-Sec-8B Q4_K_M | Q8_0 variant (8.54 GB) | Only if RAM is upgraded to 32GB. Q8_0 has better precision for complex CVE chain reasoning. Not viable on 16GB. |
| Foundation-Sec-8B | Llama-3.1-8B-Instruct (general) | If cyber-domain accuracy proves insufficient. Unlikely to help — Foundation-Sec-8B benchmarks show strong cyber specialization without significant general language degradation. |
| ChromaDB embedded | OpenSearch k-NN plugin (already in Malcolm) | OpenSearch 3.5.0 ships with k-NN plugin supporting HNSW index. Consolidating vector search into existing OpenSearch eliminates ChromaDB and saves ~100-300 MB RAM. Recommended for v2.x iteration after Malcolm is stable. See "Stack Patterns" below. |
| all-MiniLM-L6-v2 | nomic-embed-text via Ollama | nomic-embed-text provides 768-dim embeddings with better retrieval quality. Use if MiniLM retrieval relevance proves insufficient. Requires Ollama loaded simultaneously with Foundation-Sec-8B or as a separate small Ollama instance — adds ~0.5 GB RAM. |
| cosign (Sigstore) | GPG-signed checksums | GPG is well-understood and has no external dependency. Use GPG if offline/air-gapped signing is required and Sigstore transparency log access is unavailable. GPG lacks the transparency log benefits of Sigstore but is simpler for pure local use. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| OpenSearch installed separately from Malcolm | Malcolm bundles and manages its own OpenSearch 3.5.0. Installing a separate instance doubles JVM heap consumption (~12 GB instead of ~6 GB) and creates port 9200 conflicts. | Malcolm's bundled OpenSearch |
| Grafana + Loki + Alloy (retained alongside Malcolm) | v2.0 goal is migration not duplication. Running both adds ~1.5 GB RAM with redundant telemetry storage. Decommission after Malcolm is validated. | Malcolm OpenSearch Dashboards + Arkime |
| vLLM | Requires CUDA GPU. N150 has Intel integrated graphics only. Pure CPU vLLM has no performance advantage over Ollama/llama.cpp and significantly higher Python runtime overhead. | Ollama 0.18.2 |
| Docker for Ollama (on supportTAK-server) | Docker container networking adds latency to inference API calls. Ollama native install on Ubuntu gets direct memory access and ~0.5 GB less overhead than containerized. | `curl -fsSL https://ollama.com/install.sh | sh` |
| Docker on IPFire (N100 host) | Explicitly rejected by IPFire developers. Firewall integrity requires sealed appliance model. | All AI/NSM stack stays on supportTAK-server (192.168.1.22) |
| BF16 Foundation-Sec-8B | Requires ~16 GB for model weights alone — zero RAM left for OS or Malcolm. | Q4_K_M |
| Q8_0 Foundation-Sec-8B on 16GB | 8.54 GB model + Malcolm at 9.5 GB = ~18 GB minimum. OOM on 16GB system. | Q4_K_M until RAM is upgraded |
| OLLAMA_KEEP_ALIVE=-1 (permanent model load) | Keeps ~5.5 GB pinned continuously. Causes OpenSearch GC pressure and potential OOM during Malcolm indexing spikes. | `OLLAMA_KEEP_ALIVE=5m` — load on demand, release after idle |
| Pinned OpenSearch heap above 8GB on 16GB system | Violates JVM pointer compression limit of ~31 GB (not a concern here) but more critically, leaves no RAM for OS + other Malcolm containers + AI. 6-8g is the viable range. | `-Xms6g -Xmx6g` to start; tune up only if RAM permits |
| Logstash heap above 1.5GB on 16GB system | Default Malcolm Logstash allocation is 3-4 GB. Combined with constrained OpenSearch at 6 GB, leaving 1 GB for Logstash is necessary for AI workload coexistence. | `LS_JAVA_OPTS=-Xmx1g -Xms1g` |

---

## Stack Patterns by Variant

**If RAM is upgraded to 32GB (recommended before v2.x feature expansion):**
- Increase OpenSearch heap: `-Xms12g -Xmx12g`
- Increase Logstash: `-Xmx3g -Xms3g`
- Switch to Q8_0 GGUF for Foundation-Sec-8B (better reasoning quality on complex CVE chains)
- Set `OLLAMA_KEEP_ALIVE=-1` to keep model permanently resident (eliminates 15-20s cold-start)
- Add nomic-embed-text for improved RAG retrieval quality

**If consolidating RAG vector store into OpenSearch (v2.x iteration):**
- OpenSearch 3.5.0 includes k-NN plugin with HNSW support
- Create an index with `settings: {"knn": true}` and `mappings: {"properties": {"embedding": {"type": "knn_vector", "dimension": 384}}}`
- Eliminates ChromaDB dependency and saves ~100-300 MB RAM
- LangChain has `langchain-community` OpenSearch vector store integration
- Removes separate Python dependency for vector persistence

**If batch triage mode is preferred over interactive (lower latency requirements):**
- Use llama.cpp server directly: `llama-server --model foundation-sec-8b-q4_k_m.gguf --port 8080 --ctx-size 4096 --n-predict 512`
- Bypass Ollama entirely for scripted pipelines
- OpenAI-compatible endpoint available at `http://localhost:8080/v1/chat/completions`
- llama.cpp binary is ~90 MB vs. Ollama's ~4.6 GB total footprint

**If N150 iGPU Vulkan offload becomes stable in Ollama:**
- Test: `OLLAMA_GPU_LAYERS=32 ollama run foundation-sec-8b-q4_k_m`
- Watch logs for "GPU layers" confirmation
- N150 shares system RAM with iGPU — no additional RAM benefit, but shifts compute to GPU cores
- Expected: 2x token generation improvement (8-12 t/s vs. 3-8 t/s CPU-only)
- Memory bandwidth is the binding constraint either way on single-channel LPDDR5

---

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| Malcolm v26.02.0 | Ubuntu 22.04 LTS, 24.04 LTS | Verify Docker Engine >= 26.x on supportTAK-server before install |
| Malcolm v26.02.0 | OpenSearch 3.5.0 (bundled) | Do not upgrade OpenSearch inside Malcolm's compose independently — Malcolm manages its version pins |
| Malcolm v26.02.0 | Suricata 8.0.3 EVE JSON (IPFire) | Malcolm accepts Suricata EVE JSON via Logstash Beats/syslog inputs — confirmed compatible format |
| Ollama 0.18.2 | Foundation-Sec-8B Q4_K_M GGUF | Foundation-Sec-8B is Llama 3.1 8B architecture — compatible with all Ollama versions supporting Llama 3.x |
| langchain 0.3.x | chromadb 0.6.x | Use `langchain-chroma` 0.1.x as the bridge package (separate from langchain-community) |
| sentence-transformers 3.x | all-MiniLM-L6-v2 | Model from 2021, architecture unchanged, fully compatible with current sentence-transformers |
| Syft 1.42.0 | CycloneDX 1.4/1.5, SPDX 2.3 | Both formats stable; CycloneDX JSON recommended for Grype pipeline |
| cosign v3.x | Sigstore Rekor public log | v3 breaking change: `--bundle` flag now required; `--certificate-identity` and `--certificate-oidc-issuer` required for verification. Use v3 from day one. |

---

## Confidence Assessment

| Area | Confidence | Source |
|------|------------|--------|
| Malcolm version (v26.02.0) | HIGH | GitHub releases verified Feb 19, 2026 |
| Malcolm RAM minimum (24GB official) | HIGH | Official documentation at malcolm.fyi/docs/system-requirements.html |
| Malcolm constrained heap (6GB viable) | MEDIUM | Based on OpenSearch heap guidance and GitHub Issue #204; not Malcolm-tested specifically at 6g |
| Malcolm OpenSearch version (3.5.0) | HIGH | Malcolm v26.02.0 release notes |
| Foundation-Sec-8B Q4_K_M file size (4.92 GB) | HIGH | HuggingFace model card from fdtn-ai (official model authors) |
| Q4_K_M 92% quality retention | MEDIUM | Standard GGUF quantization community benchmarks; Foundation-Sec-8B specific not verified |
| Ollama version (0.18.2) | HIGH | March 2026 deployment guide confirms version |
| N150 inference speeds | LOW | Estimated from Intel Iris Xe Vulkan benchmarks (~10.58 t/s tg128, 7B Q4_0); no N150-specific data |
| Syft version (1.42.0) | HIGH | GitHub release page, February 2026 |
| cosign v3 features | HIGH | Official Sigstore documentation |
| RAG stack (ChromaDB + LangChain + MiniLM) | HIGH | Multiple verified sources, current standard pattern |

---

## Sources

- [Malcolm System Requirements](https://malcolm.fyi/docs/system-requirements.html) — 24GB minimum documented
- [Malcolm GitHub Releases — cisagov/Malcolm](https://github.com/cisagov/Malcolm/releases) — v26.02.0, Feb 19, 2026
- [Malcolm Configuration — OPENSEARCH_JAVA_OPTS](https://malcolm.fyi/docs/malcolm-config.html) — heap configuration
- [Malcolm GitHub Issue #204 — low RAM OOM](https://github.com/cisagov/Malcolm/issues/204) — systems below 12GB flagged as problematic; heap guidance
- [OpenSearch Heap Size Best Practices (Opster)](https://opster.com/guides/opensearch/opensearch-basics/opensearch-heap-size-usage-and-jvm-garbage-collection/) — 50% RAM rule, 10g minimum guidance
- [fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF on HuggingFace](https://huggingface.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF) — official GGUF from model authors
- [Mungert/Foundation-Sec-8B-GGUF on HuggingFace](https://huggingface.co/Mungert/Foundation-Sec-8B-GGUF) — full quantization variant details
- [Ollama FAQ](https://docs.ollama.com/faq) — OLLAMA_KEEP_ALIVE and model memory behavior
- [Ollama 0.18.2 Ubuntu March 2026 deployment](https://rafftechnologies.com/learn/tutorials/deploy-open-webui-ollama-ubuntu-24-04) — version confirmation
- [llama.cpp GitHub](https://github.com/ggml-org/llama.cpp) — GGUF format, context size, RAM behavior
- [llama.cpp Vulkan iGPU benchmark discussion #10879](https://github.com/ggml-org/llama.cpp/discussions/10879) — Intel Iris Xe ~10.58 t/s basis for N150 estimate
- [GGUF Memory Calculator](https://ggufloader.github.io/gguf-memory-calculator.html) — Q4_K_M RAM requirements
- [Syft v1.42.0 — anchore/syft](https://github.com/anchore/syft) — February 2026
- [Anchore SBOM Guide — Syft + Grype workflow](https://anchore.com/sbom/how-to-generate-an-sbom-with-free-open-source-tools/)
- [Sigstore cosign v3 documentation](https://docs.sigstore.dev/quickstart/quickstart-cosign/)
- [cosign v3 --bundle requirement changelog](https://github.com/sigstore/cosign/blob/main/CHANGELOG.md)
- [Vector Database Comparison 2026 — ChromaDB vs. Qdrant](https://4xxi.com/articles/vector-database-comparison/)
- [LangChain + ChromaDB + Ollama RAG guide (DEV Community)](https://dev.to/sophyia/how-to-build-a-rag-solution-with-llama-index-chromadb-and-ollama-20lb)
- [sentence-transformers all-MiniLM-L6-v2 hardware requirements (HuggingFace forum)](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/discussions/22)
- [Ollama vs. llama.cpp server comparison (NeuralNet Solutions)](https://neuralnet.solutions/ollama-vs-llama-cpp-which-framework-is-better-for-inference)

---

*Stack research for: Local AI SOC v2.0 — Malcolm NSM + Foundation-Sec-8B + RAG + SBOM on Intel N150 16GB*
*Researched: 2026-03-31*
