# Pitfalls Research

**Domain:** v2.0 Local AI SOC — Malcolm NSM + Foundation-Sec-8B + RAG + SBOM on existing IPFire/N150 system
**Researched:** 2026-03-31
**Confidence:** HIGH for Malcolm/OpenSearch and CPU inference constraints (official docs + community). MEDIUM for RAG quality pitfalls (2025 research, multiple sources). HIGH for SBOM/shell-script limitations (OpenSSF + Anchore docs).

---

## Critical Pitfalls

### Pitfall 1: Malcolm Requires 24GB RAM Minimum — 16GB Will OOM

**What goes wrong:**
Malcolm's official documentation states the minimum is 8 cores / 24 GB RAM, with 16+ cores / 32+ GB recommended. On the N150 with 16 GB, OpenSearch's JVM heap must be set to 50% of RAM (8 GB) per Malcolm's own instructions. However, Malcolm also notes that 10 GB heap is the minimum for a "pleasant experience." At 8 GB heap on 16 GB total RAM, you have 8 GB left for: Logstash (3-4 GB), Zeek, Suricata, Arkime, Filebeat, Nginx, the OS itself, llama.cpp inference, and the RAG embedding process. These services will compete for the remaining 8 GB.

The JVM also consumes non-heap memory (metaspace, thread stacks, Lucene off-heap buffers) beyond Xmx. A container set to an 8 GB JVM heap can be OOM-killed by the Linux kernel even when heap is below Xmx because total process RSS exceeds the container's memory limit. The kill appears as exit code 137 with no warning.

Additionally, the default Malcolm configuration enables `bootstrap.memory_lock=true` in OpenSearch. In Docker, this forces a 1 GB native memory allocation regardless of Xmx settings, which can cause container startup failure on tight memory budgets.

**Why it happens:**
Malcolm was designed for SOC hardware (32-64 GB RAM). Running it on N150 16 GB is below the documented minimum. The Malcolm setup script asks for heap size and the documentation suggests "half your RAM" — users comply, set 8 GB, and don't notice that the entire remaining stack also needs RAM.

**How to avoid:**
1. Do not run Foundation-Sec-8B inference simultaneously with peak Malcolm indexing. Schedule AI triage jobs during low-traffic windows.
2. Disable or defer PCAP storage entirely during initial deployment — PCAP indexing is the largest RAM amplifier (Arkime). Start with Zeek metadata + Suricata alerts only, no full PCAP, until memory budget is proven.
3. Set `OPENSEARCH_JAVA_OPTS="-Xms6g -Xmx6g"` rather than the default `4g` or the recommended `8g` — this leaves 10 GB for everything else.
4. Set `bootstrap.memory_lock=false` (or `bootstrap.memory_lock: false` in opensearch.yml) to prevent the Docker memory-lock allocation failure.
5. Disable Logstash persistent queues (`queue.type: memory`) to avoid Logstash consuming disk-mapped RAM.
6. Use Malcolm's `hedgehog` run profile if the N150 is sensor-only and another machine aggregates — this skips OpenSearch, Dashboards, and Logstash containers entirely.

**Warning signs:**
- `docker stats` shows OpenSearch container at 90%+ of its memory reservation
- System `free -h` shows swap usage growing during PCAP ingestion
- Malcolm containers restart without error — this is a silent OOM kill (check `dmesg | grep -i oom`)
- OpenSearch cluster status turns RED immediately after startup

**Phase to address:** Malcolm deployment phase — memory budgeting and heap sizing must be validated before enabling PCAP capture or live traffic analysis.

---

### Pitfall 2: OpenSearch Disk Growth Is Unbounded Without Explicit Index Lifecycle Policy

**What goes wrong:**
Malcolm's OpenSearch instance will continuously accumulate indices unless an Index State Management (ISM) policy or environment variable threshold is configured. PCAP files add a second unbounded growth vector via Arkime. The N150's 912 GB NVMe sounds large, but full PCAP on a home network at moderate throughput (50-100 Mbps average) generates 500 MB to 2 GB/hour. At 2 GB/hour, the disk fills in under 19 days at 100% capacity. When OpenSearch runs out of disk space, it transitions the cluster to read-only mode and stops accepting writes — all subsequent network events are silently dropped.

Malcolm versions before v6.2.0 used environment variables for ISM. Current Malcolm removes those variables and expects users to configure ISM through OpenSearch Dashboards UI post-deployment. This is easy to miss during initial setup.

**Why it happens:**
Malcolm ships with permissive defaults that prioritize not losing data over managing storage. There is no out-of-the-box retention limit. Setup documentation mentions ISM but does not configure it automatically.

**How to avoid:**
1. Set `OPENSEARCH_INDEX_SIZE_PRUNE_LIMIT` to a specific GB threshold (e.g., `200GB`) in `opensearch.env` before first startup.
2. Set `ARKIME_FREESPACEG=15%` in `arkime.env` so Arkime begins deleting old PCAPs before the disk fills.
3. Set `MANAGE_PCAP_FILES=true` in `arkime.env` to allow Arkime to auto-delete old PCAPs.
4. After first startup, immediately configure an ISM policy in OpenSearch Dashboards: hot→delete policy with max age (e.g., 30 days) or max index size.
5. Add a monitoring cron on N150 that alerts when NVMe usage exceeds 70%.

**Warning signs:**
- `df -h` on the Malcolm host shows NVMe above 80% with no sign of slowing
- OpenSearch Dashboards shows cluster status YELLOW with "disk watermark" warnings
- Malcolm logs show "cluster_block_exception" for write operations
- No data after a certain date — silent write block looks like a data gap, not an error

**Phase to address:** Malcolm deployment phase — storage policy must be configured on day 1, not after noticing the disk filling.

---

### Pitfall 3: Foundation-Sec-8B on N150 CPU Produces Unusably Slow Inference for Interactive Triage

**What goes wrong:**
The Intel N150 is a 4-core, 6W TDP chip with AVX2 (no AVX-512) and approximately 34-51 GB/s memory bandwidth (LPDDR5, single or dual channel depending on configuration). For CPU-only llama.cpp inference with an 8B parameter model:

- Q4_K_M GGUF (~4.9 GB): estimated 3-7 tokens/second generation rate
- Q8_0 GGUF (~8.5 GB): estimated 2-4 tokens/second generation rate

At 3-5 tokens/second, a 512-token response (typical security analysis paragraph) takes 1.5 to 3 minutes. A triage report for 10 alerts takes 15-30 minutes of CPU-only generation. During inference, all 4 N150 cores may be saturated, degrading other services (Zeek live analysis, Suricata rules engine, Arkime PCAP writes).

Additionally, the default llama-server configuration allocates an 8 GB host-memory KV cache (`--cram 512` default). With a 4.9 GB model loaded, this 8 GB cache consumes nearly all remaining RAM on a 16 GB system that already has Malcolm running.

**Why it happens:**
Foundation-Sec-8B was benchmarked on server-class hardware (A6000 GPU, 64 vCPUs). No published benchmarks exist for N150/N100 class inference. The "8B model on CPU" narrative often cites Apple M-series performance, which has 4-8x higher memory bandwidth than N150. N150 users discover the actual speed after deployment.

**How to avoid:**
1. Use Q4_K_M quantization as the maximum — do not attempt Q8_0 or BF16 on N150.
2. Disable the host-memory KV cache or reduce it aggressively: `--cram 0` or `--cram 64` in llama-server startup.
3. Set `--ctx-size 2048` or smaller — the KV cache scales with context size, and a 16K context on CPU is impractical.
4. Do not run live/interactive triage — batch process alerts during off-peak hours (e.g., nightly cron).
5. Accept that the N150 is a background batch inference node, not an interactive assistant. Design the triage workflow around async enrichment (alert comes in → enriched within 30-60 minutes) rather than on-demand query.
6. Benchmark before building the triage workflow: run `llama-bench -m foundation-sec-8b-Q4_K_M.gguf -p 512 -n 128` and validate actual t/s before designing latency-sensitive features around it.

**Warning signs:**
- llama-server consuming >8 GB RAM while Malcolm is running, triggering swap
- Triage jobs taking 10x longer than expected
- N150 CPU at 100% for minutes at a time, causing Zeek or Suricata packet drops
- OOM kills on Malcolm containers during inference

**Phase to address:** AI analyst phase — inference throughput benchmarking must be done before building the alert triage pipeline. Do not wire triage to real-time alerting until batch latency is validated.

---

### Pitfall 4: PCAP Capture Requires Network Architecture Changes That Risk Production Outage

**What goes wrong:**
Malcolm needs traffic mirrored to its capture interface. On a standard IPFire deployment, traffic passes through the IPFire box (GREEN ↔ RED) but the supportTAK-server (192.168.1.22 on GREEN) does not see that traffic natively. To capture GREEN-side traffic, either:

a) A SPAN/mirror port on a managed switch must feed a dedicated capture NIC on the N150, OR
b) A software tap (daemonlogger/tcpdump) on IPFire must forward packets to the N150, OR
c) Malcolm captures only the traffic it directly observes on GREEN (traffic to/from the N150 itself)

Option (b) requires running additional software on the IPFire box, which is constrained (Pakfire-only, no arbitrary installs), and adds load to the N100. The IPFire community has documented that daemonlogger in soft-tap mirror mode produces "garbage and malformed packets" when mirroring to another interface.

Option (a) requires a managed switch with SPAN capability between IPFire's GREEN port and the N150 — most home/SOHO setups use unmanaged switches and this change means introducing new hardware or reconfiguring the physical network while IPFire is the live gateway.

Any reconfiguration of the physical network layer while IPFire is the active gateway risks a network outage.

**Why it happens:**
Malcolm's documentation assumes the deployment host has a dedicated physical tap or SPAN interface. The IPFire-on-gateway topology was not designed with passive capture in mind. Users discover the capture architecture problem after Malcolm is already installed.

**How to avoid:**
1. Design the capture architecture before deploying Malcolm. Answer: "Where will the SPAN port come from?" before writing a line of config.
2. If a managed switch is not available, Malcolm on N150 can only observe: traffic from the N150 itself, PCAP files manually uploaded, or EVE JSON/Zeek logs forwarded by IPFire via syslog/SCP (the existing pipeline). The last option — retaining the existing SCP-based EVE JSON pipeline and feeding it into Malcolm — is the lowest-disruption path.
3. For phase 1 of Malcolm deployment, skip live PCAP capture entirely. Feed Malcolm via the existing Suricata EVE JSON pipeline (SCP pull or syslog). This gives OpenSearch-backed search and alerting without any network reconfiguration.
4. When a managed switch is eventually added, plan the SPAN port change during a maintenance window with physical access to the switch.

**Warning signs:**
- Malcolm is configured with `PCAP_ENABLE_NETSNIFF=true` but `PCAP_IFACE` points to the N150's management NIC — this captures only N150-local traffic, not the full network
- PCAP files are empty or contain only ARP/broadcast traffic
- Malcolm dashboards show very low event counts compared to what IPFire Suricata logs

**Phase to address:** Malcolm deployment phase — capture architecture must be resolved at the start, before any PCAP-related configuration.

---

### Pitfall 5: Loki-to-Malcolm Migration Causes Telemetry Dark Period During Cutover

**What goes wrong:**
The current pipeline (rsyslog → Alloy → Loki, SCP → Alloy → Loki) is the production telemetry backbone for 112,769+ log entries. If Loki/Alloy/Grafana is stopped to free RAM for Malcolm/OpenSearch, there is a gap in telemetry coverage during the cutover window. Any security events during that window are missed entirely.

Malcolm cannot ingest Loki's existing log data directly — Loki's chunk storage format is fundamentally different from OpenSearch's inverted index. Existing Loki historical data cannot be migrated to Malcolm/OpenSearch without:
1. Exporting raw logs from Loki (via LogQL query export — tedious, incomplete)
2. Reformatting for Logstash ingestion into OpenSearch

In practice, historical Loki data is abandoned during migration. This is an expected tradeoff but must be a deliberate decision, not an accidental one.

**Why it happens:**
Teams assume a "migration" means data continuity. Loki and OpenSearch are not compatible. Running both simultaneously to eliminate the dark period is possible in theory (Malcolm supports a secondary data store, and Alloy can dual-write) but doubles the already-tight RAM budget on the N150.

**How to avoid:**
1. Accept the historical data break explicitly. Document in a decision log: "Loki historical data (date range) is not migrated to OpenSearch. Loki archive is kept read-only for X days for backward reference."
2. Use Malcolm's `OPENSEARCH_SECONDARY_*` environment variable support to dual-write to both OpenSearch and a lightweight secondary during transition — but only if RAM allows.
3. Keep Loki running in read-only mode alongside Malcolm for the first 2-4 weeks. This requires both stacks to coexist on the N150 — validate RAM budget first. Loki itself runs at ~250 MB; it's the Alloy agents that add overhead.
4. Time the cutover to a low-activity period. Schedule a 30-60 minute maintenance window where network monitoring is paused, Malcolm is started, and the switch is made.
5. Before stopping Loki, export the last 7 days of EVE JSON events to flat files as an archive.

**Warning signs:**
- Planning to "just swap" Loki for Malcolm in a single step with no transition period
- No decision documented about what happens to historical Loki data
- RAM budget not validated for both stacks running simultaneously
- No maintenance window planned for the cutover

**Phase to address:** Malcolm deployment phase — the migration plan must explicitly address the dark period before any stack changes are made.

---

### Pitfall 6: RAG Chunking Strategy Determines Quality More Than Model Choice

**What goes wrong:**
RAG quality on the operating corpus (ADRs, runbooks, validation results, control docs) will silently degrade if chunking is done wrong. 80% of RAG failures originate in the chunking layer, not the model. The most common mistake for a structured-document corpus (Markdown ADRs, shell-script-heavy runbooks) is:

a) Fixed-size chunking that splits across document structure (a chunk ending mid-decision-rationale)
b) No overlap between chunks, losing context at boundaries
c) Chunks so large (2000+ tokens) that embeddings become diffuse and retrieval becomes imprecise
d) Chunks so small (< 100 tokens) that the LLM receives fragmented context without enough information to reason from

For this corpus specifically: ADRs have structured sections (Status, Context, Decision, Consequences) that must not be split across chunks. Runbooks reference each other across sections. A chunk containing "use SCP for EVE JSON" without the chunk explaining why (intel i226-V hardware checksum) will produce confident but incomplete AI responses.

**Why it happens:**
Default chunking implementations (LangChain's RecursiveCharacterTextSplitter with chunk_size=1000) are reasonable general-purpose starting points but ignore document structure. Markdown-aware chunking (splitting on headers) is a 5-line change but is not the default.

**How to avoid:**
1. Use structure-aware chunking for Markdown documents: split on `##` and `###` headers first, then recursively split on paragraphs if a section exceeds the token limit.
2. Target 400-600 tokens per chunk with 10-15% overlap (40-80 tokens). This is the sweet spot confirmed by the Vectara NAACL 2025 study.
3. Add contextual headers to each chunk before embedding: prepend the document title and section path (e.g., "ADR-007: SCP for EVE JSON > Decision:") so chunks are self-contained when retrieved.
4. For runbooks that cross-reference other documents, include a brief summary of the cross-referenced content in the chunk rather than relying on retrieval to fetch both.
5. Evaluate chunking quality before building the full pipeline: manually test 10 representative queries against the chunked corpus and inspect which chunks are retrieved.

**Warning signs:**
- AI responses that are confidently wrong about system specifics (e.g., wrong port numbers, wrong file paths)
- Responses that reference "the decision" without stating what the decision was
- High retrieval similarity scores but poor answer quality — the retrieved chunk contains the right words but wrong context
- Long latency at query time — embeddings are too large, similarity search is slow

**Phase to address:** RAG pipeline phase — chunking strategy must be designed before ingesting the corpus, not tuned after complaints about answer quality.

---

### Pitfall 7: SBOM Generation Is Misleading for a Shell-Script-Heavy Repository

**What goes wrong:**
Syft (the standard SBOM generator) analyzes package manifests (package.json, go.mod, requirements.txt, Gemfile) and container image layers. For a repository that is primarily shell scripts (`~3,045 LOC`), YAML configs, and Markdown documentation:

- Syft will generate an SBOM with zero or minimal software components detected, because bash scripts have no package manifest
- The SBOM accurately represents the installed toolchain (if run against the host filesystem) but does not capture the runtime dependencies that the scripts install or configure via Pakfire
- Scripts that call `pakfire install guardian` or reference `suricata.yaml` are invoking external software that syft will not see unless the system is analyzed post-install

The result is an SBOM that is technically valid but practically incomplete. Vulnerability scanners (Grype, Trivy) run against this SBOM will report clean, which is accurate for the repo itself but misleading about the deployed system's attack surface.

**Why it happens:**
SBOM tooling was designed for software packages (libraries, binaries, containers) not for infrastructure-as-code repositories. The industry expectation is that an SBOM captures "what is this software made of" — for a firewall config repo, the answer is "it's not made of libraries, it orchestrates external software."

**How to avoid:**
1. Generate two separate SBOM artifacts: (a) a repository SBOM from syft against the git repo itself (captures any scripts with embedded version references), and (b) a deployed system SBOM from syft against the live IPFire filesystem post-install (captures installed Pakfire packages, Suricata binary, etc.).
2. For the system-level SBOM, run `syft packages / --exclude '/proc' --exclude '/sys'` on the IPFire box and copy the result off-box for signing.
3. Document explicitly in the SBOM README that the repo SBOM covers source artifacts only, and the system SBOM covers the deployed state at a point in time.
4. Use cosign or sigstore to sign both SBOMs so their provenance is verifiable even if the content is incomplete.
5. Accept and document known gaps: Pakfire-installed packages may not have version metadata that syft can parse correctly.

**Warning signs:**
- SBOM shows 0-5 components for a repo that manages a full firewall stack — this is technically possible but warrants explicit documentation that it reflects source code only
- Vulnerability scan on the repo SBOM reports clean without analyzing the deployed system packages
- No distinction between "repo SBOM" and "deployed system SBOM" in the release artifacts

**Phase to address:** SBOM/release phase — SBOM scope must be defined before generation, with explicit documentation of what is and is not captured.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Skip live PCAP capture, feed Malcolm only via EVE JSON | Avoids network reconfiguration, zero outage risk | Full network visibility not achieved; encrypted traffic analysis impossible; no session-level PCAP for forensics | Acceptable for Phase 1 Malcolm deployment; revisit when managed switch is available |
| Run Malcolm and llama.cpp simultaneously without RAM budgeting | Simpler deployment script | OOM kills on Malcolm containers during inference; network monitoring drops during AI triage | Never — always validate RAM budget with both running |
| Default Malcolm heap (4g) on 16 GB | Works initially | Heap too small for meaningful workloads; OpenSearch GC thrashing under load | Never — set heap explicitly at deployment |
| Use Q8_0 GGUF instead of Q4_K_M | Better model accuracy | ~8.5 GB model vs ~4.9 GB; leaves less headroom on 16 GB alongside Malcolm | Only if Malcolm PCAP capture is disabled and only metadata indexing is active |
| Skip ISM policy, rely on disk being "big enough" | No configuration effort | Disk fills in 2-3 weeks with PCAP enabled; silent write block causes event loss | Never |
| Single SBOM from `syft .` on the repo | Easy CI integration | Misleading completeness — missing all Pakfire/system dependencies | Acceptable only if documented as "source artifact SBOM only, not deployed system SBOM" |
| Fixed-size 1000-token chunks, no overlap | Works with default LangChain settings | Chunking splits ADR rationale; AI gives confidently incomplete answers | Never for structured Markdown documents — always use header-aware chunking |
| Keep Loki and Malcolm running simultaneously indefinitely | No dark period during migration | Combined RAM usage (Malcolm ~12-14 GB + Loki ~500 MB + Alloy) will saturate 16 GB | Acceptable for a 2-4 week transition window only |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Malcolm + existing SCP/Alloy/Loki pipeline | Stopping Loki before Malcolm is validated | Run both in parallel for 2-4 weeks; validate Malcolm is receiving and indexing before cutting over |
| Malcolm OpenSearch + Docker memory limits | Setting container memory limit equal to Xmx | Container limit must be Xmx + 25-30% for JVM non-heap; at 6 GB Xmx, set container limit to 8-9 GB |
| Malcolm PCAP capture + IPFire network | Pointing PCAP_IFACE at N150's management NIC | Management NIC only sees N150-local traffic; requires SPAN port or software tap for full network visibility |
| llama-server + Malcolm simultaneously | Running with default --cram 512 (8 GB KV cache) | Set --cram 0 or --cram 64 to avoid consuming all remaining RAM; Malcolm takes priority |
| RAG corpus + cross-referencing documents | Chunking each document independently | Use contextual headers that include source doc + section path; add brief summaries of cross-referenced decisions |
| Syft SBOM + IPFire Pakfire packages | Running syft against the git repo only | Run syft against both the repo and the live system filesystem; sign both artifacts separately |
| Malcolm + `bootstrap.memory_lock=true` in Docker | Default Malcolm opensearch.yml setting | Set `bootstrap.memory_lock=false` in Docker deployments; memory locking in containers causes 1 GB forced allocation failure |
| Foundation-Sec-8B + long context window | Using default --ctx-size 8192 or 16384 | KV cache is proportional to context size; on N150 use --ctx-size 2048 maximum to fit within RAM budget |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| OpenSearch + Malcolm full stack on 16 GB RAM | Constant container restarts, swap usage, OOM kills | Heap at 6 GB, no PCAP initially, batch inference only | Immediately under any sustained load if heap is misconfigured |
| PCAP capture at line rate on home network | NVMe fills in 2-3 weeks; OpenSearch write-blocks | Set MANAGE_PCAP_FILES=true, ARKIME_FREESPACEG=15%, ISM policy from day 1 | At 50-100 Mbps average sustained, 912 GB fills in under 2 weeks |
| CPU inference during Malcolm live indexing | All 4 N150 cores saturated; Zeek/Suricata packet drops | Schedule inference during low-traffic windows; never run concurrently with peak indexing | Any time both are active simultaneously |
| Large RAG context window | llama-server KV cache exhausts RAM during inference | Cap --ctx-size at 2048; use RAG to retrieve targeted chunks not entire documents | With context > 4096 and Malcolm also running |
| OpenSearch GC pressure during bulk PCAP ingestion | Dashboards become unresponsive; indexing lag grows | Disable bulk PCAP upload during business hours; tune Logstash pipeline workers to 1-2 on N150 | During any large PCAP batch upload |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Malcolm web UI exposed to full GREEN subnet | Anyone on LAN can access Arkime PCAP viewer with full packet capture | Restrict Malcolm ports (443, 488) to management subnet via IPFire CUSTOMINPUT rules |
| llama-server API exposed without authentication | Any GREEN host can query the AI analyst and exfiltrate system context from RAG | Bind llama-server to 127.0.0.1 only; use a local reverse proxy with authentication if remote access is needed |
| SBOM signed with a key stored in the repo | Release artifacts appear signed but key is exposed | Store cosign private key outside the repo; use a hardware token or secrets manager |
| Malcolm OpenSearch dashboard accessible without TLS | Network session metadata (internal IPs, hostnames, ports) transmitted in plaintext on GREEN | Malcolm configures HTTPS by default; verify certs and do not disable TLS for "simplicity" |
| RAG corpus includes sensitive runbooks with credentials | AI analyst responses may echo credential context from RAG chunks | Scrub credential placeholders and API keys from documents before ingesting into the RAG corpus |
| Malcolm running as root in Docker containers | Container escape = root on N150 host | Validate Malcolm containers run as non-root; check `docker inspect` for User field |

---

## "Looks Done But Isn't" Checklist

- [ ] **Malcolm memory budget:** Malcolm containers are running — verify with `docker stats` that no container is consuming more than its allocation; check `free -h` for swap usage; confirm OOM kill is not occurring silently (`dmesg | grep -i oom`).
- [ ] **OpenSearch ISM policy:** OpenSearch Dashboards loads — verify an ISM policy is configured and assigned to Malcolm's indices; confirm PCAP file deletion is enabled in `arkime.env`; confirm `OPENSEARCH_INDEX_SIZE_PRUNE_LIMIT` is set.
- [ ] **PCAP capture scope:** Malcolm shows network events — verify which interface is being captured; confirm it is seeing the correct traffic by checking that known external connections appear in Arkime/Dashboards, not just N150-local traffic.
- [ ] **Loki migration decision:** Malcolm is receiving events — confirm the decision about historical Loki data is documented; confirm Loki is in read-only or stopped state intentionally, not accidentally.
- [ ] **Inference throughput:** Foundation-Sec-8B is loaded — run `llama-bench` and document actual tokens/second; confirm the triage workflow is designed around batch latency, not interactive latency.
- [ ] **RAG chunk quality:** RAG pipeline is returning results — manually test 10 queries that span multiple ADRs; confirm retrieved chunks contain the rationale, not just keywords; confirm no chunk splits mid-decision.
- [ ] **SBOM completeness:** SBOM artifact exists — confirm whether it covers the repo, the deployed system, or both; confirm the artifact is documented with its scope limitations; confirm cosign signature is valid.
- [ ] **Malcolm dark period:** Cutover plan exists — confirm there is a documented maintenance window; confirm the fallback plan if Malcolm fails to start; confirm Loki data is archived before stopping.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Malcolm OOM kills during initial deployment | LOW-MEDIUM | `docker compose down`; reduce OpenSearch heap in `docker-compose.yml`; disable PCAP capture; restart with `docker compose up -d`; monitor `docker stats` |
| OpenSearch disk full, write-blocked | MEDIUM | Stop Malcolm ingestion (`docker compose stop logstash filebeat`); delete old indices via OpenSearch Dashboards; configure ISM policy; restart ingestion; do not restart OpenSearch during disk-full state |
| N150 CPU saturated from concurrent inference + Malcolm | LOW | Kill llama-server process; reschedule inference as off-hours cron; configure systemd resource limits for llama-server |
| PCAP capture showing wrong/no traffic | MEDIUM | Verify PCAP_IFACE in pcap-capture.env; verify interface is in promiscuous mode; verify the capture NIC is connected to SPAN port (not management); tcpdump on the interface to confirm traffic |
| Loki dark period during migration | MEDIUM | If Malcolm is not yet stable: restart Alloy/Loki stack; confirm EVE JSON is flowing to Loki again; treat Malcolm as pre-production until validated |
| RAG producing wrong answers | MEDIUM | Re-chunk corpus with header-aware strategy; re-embed; test with a validation query set before re-deploying |
| SBOM signed with compromised key | HIGH | Revoke the key; regenerate SBOM; re-sign with new key; publish a security advisory noting the affected release range |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Malcolm OOM on 16 GB RAM | Malcolm deployment — memory pre-planning | `docker stats` shows no OOM kills after 24h; `free -h` shows <90% RAM used during peak indexing |
| OpenSearch unbounded disk growth | Malcolm deployment — storage policy day 1 | ISM policy assigned to indices; Arkime PCAP deletion enabled; disk at <70% after 7 days PCAP capture |
| Foundation-Sec-8B CPU inference too slow | AI analyst phase — benchmark before building | `llama-bench` result documented; triage workflow designed for batch latency, not interactive |
| PCAP capture architecture gap | Malcolm deployment — capture design first | Confirm traffic source (SPAN or EVE JSON); validate Malcolm shows representative event counts from network |
| Loki-to-Malcolm migration dark period | Migration phase — explicit cutover plan | Maintenance window documented; Loki data archived; fallback procedure written |
| RAG chunking degrades quality | RAG pipeline phase — chunking strategy before ingestion | 10-query manual validation passes before corpus is declared production-ready |
| SBOM misleading for shell-script repo | SBOM/release phase — scope definition | Both repo SBOM and system SBOM exist with documented scope; limitations noted in release notes |
| Malcolm API/UI exposed on GREEN | Malcolm deployment — network access control | IPFire CUSTOMINPUT rules restrict Malcolm ports to management subnet; confirmed from non-management GREEN host |

---

## Sources

- Malcolm NSM System Requirements: https://malcolm.fyi/docs/system-requirements.html (minimum 24 GB RAM)
- Malcolm NSM Configuration: https://malcolm.fyi/docs/malcolm-config.html (OpenSearch heap sizing guidance)
- Malcolm NSM Capabilities and Limitations: https://malcolm.fyi/docs/capabilities-and-limitations.html
- Malcolm NSM Index Management: https://cisagov.github.io/Malcolm/docs/index-management.html (ISM policy, pruning thresholds)
- Malcolm NSM Live Analysis: https://cisagov.github.io/Malcolm/docs/live-analysis.html (PCAP capture env vars, PCAP_IFACE_TWEAK)
- Malcolm NSM OpenSearch Instances: https://cisagov.github.io/Malcolm/docs/opensearch-instances.html (secondary data store)
- OpenSearch JVM heap sizing (Opster): https://opster.com/guides/opensearch/opensearch-basics/opensearch-heap-size-usage-and-jvm-garbage-collection/
- OpenSearch bootstrap.memory_lock Docker bug: https://github.com/opensearch-project/OpenSearch/issues/5865
- OpenSearch JVM heap bug (huge usage): https://github.com/opensearch-project/OpenSearch/issues/13927
- llama.cpp server memory / KV cache: https://github.com/ggml-org/llama.cpp/discussions/18488
- llama.cpp host-memory prompt caching: https://github.com/ggml-org/llama.cpp/discussions/20574
- Foundation-Sec-8B model page: https://huggingface.co/fdtn-ai/Foundation-Sec-8B
- Foundation-Sec-8B Q4_K_M GGUF: https://huggingface.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF
- Foundation-Sec-8B Q8_0 GGUF: https://huggingface.co/fdtn-ai/Foundation-Sec-8B-Q8_0-GGUF
- Cisco Foundation-Sec-8B blog: https://blogs.cisco.com/security/foundation-sec-cisco-foundation-ai-first-open-source-security-model
- RAG chunking strategies 2025 (Vectara NAACL): https://blog.premai.io/rag-chunking-strategies-the-2026-benchmark-guide/
- RAG lessons 2025 (TrueState): https://www.truestate.io/blog/lessons-from-rag
- Weaviate RAG chunking: https://weaviate.io/blog/chunking-strategies-for-rag
- SBOM generation tools (OpenSSF): https://openssf.org/blog/2025/06/05/choosing-an-sbom-generation-tool/
- Syft SBOM generator (Anchore): https://github.com/anchore/syft
- IPFire daemonlogger / PCAP capture forum: https://forum.ipfire.org/viewtopic.php?t=2493
- AWS PCAP Malcolm on EKS (architectural reference): https://aws.amazon.com/blogs/publicsector/the-key-components-of-cisas-malcolm-on-amazon-eks/
- Malcolm from PCAP to intelligence (Medium, March 2026): https://medium.com/@sansalnuray/from-pcap-to-intelligence-a-practical-look-at-malcolm-tool-f37a0f889e79

---
*Pitfalls research for: v2.0 Local AI SOC — Malcolm NSM + Foundation-Sec-8B + RAG + SBOM additions to production IPFire/N150 system*
*Researched: 2026-03-31*
