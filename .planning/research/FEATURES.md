# Feature Research

**Domain:** Local-first AI SOC — Malcolm NSM + Foundation-Sec-8B + RAG + alert triage + SBOM (v2.0 milestone)
**Researched:** 2026-03-31
**Confidence:** MEDIUM-HIGH (Malcolm and Foundation-Sec-8B verified via official docs and Hugging Face; RAG/triage patterns verified via multiple sources; SBOM toolchain HIGH confidence via OWASP/official docs)

> **Scope note:** v1.0 features (IPFire firewall, Suricata IDS/IPS, Grafana+Loki telemetry pipeline, Git reproducibility) are already built and validated. This document covers ONLY new v2.0 features. The existing `.planning/research/FEATURES.md` from 2026-03-21 covers the v1.0 feature landscape; this supersedes it for v2.0 planning.

---

## v2.0 Feature Landscape

### Table Stakes (v2 Cannot Ship Without These)

Features whose absence means the v2 milestone has not been completed. No credit for having them; immediate failure for missing.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Malcolm NSM deployed and ingesting traffic** | The entire pivot of v2 is replacing Loki with Malcolm/OpenSearch as the telemetry backend; Malcolm is the core deliverable | HIGH | Malcolm requires minimum 8 CPU cores, 24 GB RAM. supportTAK-server (N150, 16 GB) is **below minimum RAM**. Must confirm whether Malcolm runs on 16 GB. Likely requires tuning OpenSearch heap aggressively. Runs as Docker Compose stack — all containers on supportTAK-server. |
| **Suricata EVE JSON flowing into Malcolm** | Malcolm must replace Loki as EVE consumer; existing Suricata alerts must be visible in OpenSearch Dashboards | HIGH | Malcolm accepts EVE JSON via Filebeat forwarding over TLS to Logstash port 5044. The existing SCP-pull pipeline to Loki must be replaced or supplemented. Malcolm's internal Suricata container runs its own Suricata instance — **the existing on-box Suricata must forward to Malcolm, not be replaced**. Custom Filebeat config on supportTAK-server (or on IPFire if Filebeat can be installed via Pakfire) tails `/var/log/suricata/eve.json` and ships to Malcolm's Logstash. |
| **Zeek network metadata layer** | Zeek provides protocol-level session metadata (DNS, HTTP, TLS, conn logs) that Suricata alone does not provide; Malcolm expects both | HIGH | Zeek runs inside Malcolm's containers, capturing traffic on a mirrored interface. Requires a network tap or SPAN port from IPFire to deliver raw packets to the Malcolm host. IPFire must mirror GREEN/RED traffic to supportTAK-server — not trivially configured on IPFire without hardware support. |
| **OpenSearch Dashboards accessible** | Malcolm's visualization layer replaces Grafana for network security data | MEDIUM | Malcolm ships dozens of prebuilt dashboards for Zeek log types and Suricata alerts. Out-of-the-box after deploy. Accessible on Malcolm HTTPS port. Arkime also available for session-level PCAP investigation. |
| **Foundation-Sec-8B running locally via Ollama** | The AI analyst must be deployable and reachable; no value if the model cannot run | MEDIUM | Q4_K_M GGUF (~4.92 GB) runs on N150 16 GB via Ollama. Expected throughput: 2–8 tokens/sec on N150 (low-power CPU, no discrete GPU). Q8_0 (~8.54 GB) is tight on 16 GB with OS overhead — Q4_K_M is the safe choice. Model is cybersecurity-fine-tuned on Llama-3.1-8B; outperforms Llama-3.1-70B on security benchmarks. Apache 2.0 license. |
| **AI analyst can receive alert context and return analysis** | The analyst must accept structured alert input and produce actionable output | MEDIUM | Foundation-Sec-8B-Instruct variant is needed (not just the base model). Instruct model supports chat/instruction format. Integration pattern: pipe alert JSON → prompt template → Ollama API → structured analysis output. No GUI required; CLI or API calls sufficient for v2. |
| **RAG corpus indexed and queryable** | The AI analyst needs access to project-specific knowledge (ADRs, runbooks, validation results, control docs) to give context-aware answers | HIGH | Requires: embedding model (e.g., nomic-embed-text via Ollama), vector DB (ChromaDB for MVP, Qdrant for production), document ingestion pipeline for `.planning/` docs and runbooks. LangChain or LlamaIndex as orchestration layer. All runs on supportTAK-server. |
| **Alert triage mechanism** | Alerts must flow from Malcolm/OpenSearch to a triage queue where the AI can act on them | HIGH | Options: OpenSearch alerting webhooks → triage script → AI analyst; or DFIR-IRIS with API integration. A minimal triage queue can be a structured queue (file/SQLite) with a daemon that pulls new alerts, sends to AI, and writes enriched output. Full case management (DFIR-IRIS) is a differentiator, not table stakes. |
| **SBOM generated for release artifacts** | v2.0 adds signed releases; SBOM is mandatory for supply chain transparency | MEDIUM | Syft generates SBOM from the repo/Docker image. Output format: CycloneDX JSON (preferred for security use cases). Cosign signs the SBOM artifact. Git tag triggers SBOM generation. Syft supports shell scripts, Docker images, and filesystem scanning. |
| **Signed release artifacts** | Git tags must produce signed artifacts proving provenance | MEDIUM | Cosign + Sigstore. Git-tag-triggered shell script runs Syft, signs output with Cosign. Keys stored securely (age-encrypted or hardware key). The release artifact is the tarball of the repo at the tag + the SBOM + the cosign signature. |

---

### Differentiators (What Separates This from Basic Malcolm + LLM)

Features that go beyond the minimum, providing real analyst workflow value.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **DFIR-IRIS case management** | Formal case tracking, evidence attachment, task assignment, immutable audit trail per incident | HIGH | DFIR-IRIS is fully open-source, Docker-deployable, supports alert ingestion via API. Connects to Malcolm/OpenSearch alerts via webhook or polling. Creates structured case records with analyst notes. The fully-automated pipeline (alert → enrich → AI triage → DFIR-IRIS case) is the v2 gold standard. |
| **AI-enriched alert summaries in triage queue** | Instead of raw JSON alerts, analyst sees: "This alert indicates [X] technique (ATT&CK TID), seen from [IP], correlated with [prior events], confidence [H/M/L]" | HIGH | Requires: alert ingestion from OpenSearch, context lookup via RAG (matching alert to ADRs/runbooks), Foundation-Sec-8B synthesis, structured output writer. High analyst time-savings when working. |
| **MITRE ATT&CK mapping on alerts** | Foundation-Sec-8B maps Suricata alert signatures to ATT&CK techniques automatically | MEDIUM | Foundation-Sec-8B is fine-tuned on ATT&CK data. Prompt template: "Given this Suricata alert: [alert], what ATT&CK technique(s) does this map to? Provide TID and confidence." Output appended to enriched alert record. |
| **RAG over ADRs and runbooks** | Analyst can ask "What is the runbook for this alert type?" and get a project-specific answer, not a generic one | MEDIUM | Indexes `.planning/` directory, all runbooks, validation results, control documentation. Retrieval uses vector similarity over embedded chunks. Embedding model: nomic-embed-text (free, runs via Ollama, 137M params, efficient on CPU). |
| **Broader telemetry ingestion (endpoint, auth, asset inventory)** | Malcolm via Filebeat beats pipeline can accept host logs, auth logs, and other third-party sources beyond IPFire | MEDIUM | Malcolm supports Fluent Bit and Beats for third-party logs (indexed under `malcolm_beats_*`). Endpoint logs from internal hosts, auth logs (SSH, sudo), asset inventory enrichment all ingestible. NetBox in Malcolm supports asset modeling — auto-populates from observed network traffic. |
| **Community-id correlation between Zeek and Suricata** | Zeek conn logs and Suricata alerts share a common community_id field, enabling join queries in OpenSearch | LOW | Suricata `community-id` option must be enabled in `suricata.yaml`. Malcolm normalizes both into the same OpenSearch index. Out-of-the-box correlation becomes possible in Discover/Dashboards. Requires `community-id: true` in existing IPFire Suricata config. |
| **File extraction and malware scanning** | Zeek extracts files from network traffic; Malcolm scans with ClamAV, YARA, and capa | MEDIUM | Built into Malcolm (ClamAV, YARA, capa containers). Out-of-the-box once Malcolm is deployed with live capture. No custom integration required. Alerts surface in OpenSearch when malware is detected in transiting files. |
| **Arkime PCAP investigation interface** | Full packet capture retrieval for incident investigation; session-level drill-down | MEDIUM | Built into Malcolm. Arkime captures PCAP on the live capture interface. Requires sufficient disk (SSD preferred, as much as available). Analyst can pivot from OpenSearch alert → Arkime session → raw packet in one workflow. |

---

### Anti-Features (Deliberately NOT Building)

Features that are tempting but create problems for a local-first, constrained-hardware SOC.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Real-time LLM alert analysis on every event** | Automatic AI triage on every Suricata alert sounds powerful | N150 at 2–8 tokens/sec cannot process a burst of 100 alerts in real time without queue saturation. Creates backpressure, drops alerts, or exhausts RAM. At 5 tokens/sec and ~200 tokens per analysis, one alert takes ~40 seconds. | Batch triage: run AI analysis on queued alerts every N minutes or on analyst request. Prioritize by severity (critical first). Rate-limit AI calls. |
| **Cloud LLM APIs as fallback** | OpenAI/Anthropic API is faster and more capable | Defeats the entire "local-first, no cloud dependencies" core value. Sends potentially sensitive alert data (internal IPs, hostnames, network topology) to third parties. | Accept the performance limitations of local inference. Foundation-Sec-8B Q4_K_M is fit for purpose on batch security tasks. |
| **Malcolm on IPFire host** | Co-locating NSM with the firewall seems efficient | Malcolm minimum is 8 cores/24 GB RAM. IPFire N100 has 4 cores, 16 GB. Docker is rejected by IPFire developers. Running Malcolm on the firewall would destabilize the data plane. | Malcolm runs on supportTAK-server (N150, 16 GB). IPFire forwards EVE JSON via Filebeat. |
| **Replacing on-box Suricata with Malcolm's internal Suricata** | Malcolm ships its own Suricata container; redundancy seems wasteful | On-box Suricata in IPS mode can DROP packets (inline mode). Malcolm's Suricata runs off-box on mirrored traffic — it is detection-only, cannot block. The on-box Suricata must stay for prevention capability. | Keep IPFire's on-box Suricata for IPS. Use Malcolm's Suricata for NSM visibility on mirrored traffic. Accept the redundancy — they serve different functions. |
| **OpenSearch with default JVM heap** | Simpler to deploy with defaults | Default OpenSearch heap is 1 GB minimum, often set to 50% of RAM = 8 GB on a 16 GB host. This leaves 8 GB for everything else (Zeek, Arkime, Logstash, Filebeat, OS). Malcolm will OOM or swap. | Tune OpenSearch heap to 4–6 GB on a 16 GB host. Set explicit `OPENSEARCH_JAVA_OPTS=-Xms4g -Xmx4g` in Malcolm's environment. Accept reduced indexing throughput. |
| **Full DFIR-IRIS in v2 MVP** | Case management is the right end state | DFIR-IRIS adds another Docker service, integration complexity, and requires workflow discipline to use correctly. If not used consistently, it becomes stale data. | Build the minimal triage queue first (alert → AI enrichment → structured output file). Add DFIR-IRIS as a differentiator once the AI enrichment pipeline is proven. |
| **LLM-generated automated response actions** | AI could automatically block IPs, adjust firewall rules | LLM hallucinations in an automated response pipeline can block legitimate traffic, create outages, or be exploited via prompt injection. No human-in-the-loop = catastrophic failure mode. | AI analyst produces recommendations only. Human approves and executes. Alert triage queue shows AI recommendation + confidence; analyst clicks "accept" or "reject." |
| **Agentic multi-LLM orchestration** | Five-agent SOC (Triage, Detect, Hunt, Respond, Coordinate) is the research state-of-the-art | Each additional agent multiplies: RAM usage, inference time, prompt complexity, hallucination surface, and debugging difficulty. N150 cannot sustain multiple concurrent LLM inference processes. | Single Foundation-Sec-8B instance handling triage queries sequentially. Multi-agent is v3+ if hardware improves. |
| **SBOM vulnerability scanning pipeline (Grype/Dependency-Track)** | Full SBOM workflow includes CVE enrichment | Grype + Dependency-Track adds significant operational complexity (another Docker service, vulnerability database sync, ticket integration). The project has no software dependencies in the traditional sense — it is shell scripts and config files. | Generate SBOM with Syft, sign with Cosign, store in repo. CVE scanning of the SBOM is out of scope for v2; the SBOM itself is the deliverable. |

---

## What Malcolm Provides Out-of-the-Box vs. What Needs Custom Integration

This distinction is critical for phase planning. Malcolm does a lot automatically — do not rebuild what it provides.

### Malcolm Out-of-the-Box (Zero Custom Code)

| Capability | Malcolm Component | Notes |
|------------|-------------------|-------|
| Network protocol metadata (DNS, HTTP, TLS, SSH, conn, etc.) | Zeek (containerized) | 40+ Zeek log types, all indexed into OpenSearch |
| Suricata IDS alerts with rule updates | Suricata (containerized) | Suricata rule updates enabled by default; supports ET Community, OISF, etc. |
| PCAP storage and retrieval | Arkime (containerized) | Full packet capture on live interfaces; session search UI |
| OpenSearch indexing and querying | OpenSearch + Logstash | Logstash enrichment pipeline normalizes all log types |
| Visualization dashboards (dozens prebuilt) | OpenSearch Dashboards | Protocol-specific dashboards for all Zeek log types + Suricata |
| GeoIP enrichment | Logstash pipeline | Auto-enriches source/dest IPs with country, org, coordinates |
| MAC OUI manufacturer lookup | Logstash pipeline | Hardware vendor from MAC address, auto-populated |
| JA4/JA3 TLS fingerprinting | Zeek/Logstash | Identifies TLS client/server fingerprints for threat hunting |
| File extraction and scanning | ClamAV + YARA + capa containers | Triggered automatically on Zeek-extracted file transfers |
| Asset inventory (NetBox) | NetBox container | Auto-populates from observed traffic; manual enrichment supported |
| MITRE ATT&CK mapping for ICS (BZAR/ACID) | Zeek scripts | Primarily for OT/ICS environments; enabled by default |
| Filebeat forwarder support | Logstash pipeline | Remote sensors ship logs via Filebeat over TLS to port 5044 |
| Email/webhook alerting | OpenSearch alerting plugin | Threshold-based alerts configurable in Dashboards UI |
| REST API | Malcolm API + OpenSearch API | Programmatic access to all data; needed for AI analyst integration |

### Requires Custom Integration

| Capability | What Needs Building | Complexity |
|------------|---------------------|------------|
| IPFire EVE JSON → Malcolm | Filebeat config on supportTAK-server (or remote forwarder on IPFire) tailing `/var/log/suricata/eve.json`, shipping to Malcolm Logstash:5044 with TLS certs | MEDIUM |
| Network tap / SPAN for live Zeek capture | IPFire must mirror traffic to a second NIC on supportTAK-server. Requires either: hardware tap, managed switch SPAN port, or IPFire `tc` mirror rule. None are trivial on the current hardware setup. | HIGH |
| Foundation-Sec-8B Ollama install | Install Ollama on supportTAK-server, pull `fdtn-ai/Foundation-Sec-8B-Instruct-Q4_K_M-GGUF`, configure as service | LOW |
| Prompt template for alert triage | Shell or Python wrapper: ingest alert JSON → format prompt → call Ollama API → parse response | MEDIUM |
| RAG corpus ingestion pipeline | Python script using LangChain/LlamaIndex: chunk `.planning/` docs → embed with nomic-embed-text → store in ChromaDB | MEDIUM |
| RAG retrieval integration | At query time: embed query → retrieve top-K chunks from ChromaDB → inject into Foundation-Sec-8B context | MEDIUM |
| Alert queue daemon | Polling loop: query OpenSearch for new critical alerts → deduplicate → queue for AI analysis → write enriched output | MEDIUM |
| SBOM generation script | `syft dir:. -o cyclonedx-json > sbom.json` triggered on git tag; part of release script | LOW |
| Cosign signing | `cosign sign-blob sbom.json --key cosign.key` integrated into release process | LOW |
| community-id in IPFire Suricata | Add `community-id: true` to IPFire's `suricata.yaml` (via backup-included config) | LOW |

---

## Feature Dependencies

```
[Malcolm NSM deployed]
    └──requires──> [supportTAK-server Docker Compose]
    └──requires──> [EVE JSON forwarding from IPFire]
                       └──requires──> [Filebeat config with Malcolm TLS certs]
                       └──requires──> [Existing on-box Suricata EVE JSON output]
    └──requires──> [Network tap/SPAN for Zeek live capture] (differentiator, not MVP)
    └──provides──> [OpenSearch Dashboards]
    └──provides──> [Arkime PCAP investigation]
    └──provides──> [REST API for AI analyst integration]

[Foundation-Sec-8B (Ollama)]
    └──requires──> [Ollama installed on supportTAK-server]
    └──requires──> [Q4_K_M GGUF model pulled]
    └──provides──> [AI analyst inference endpoint]

[RAG corpus]
    └──requires──> [Foundation-Sec-8B (Ollama)] (embedding model: nomic-embed-text)
    └──requires──> [ChromaDB or Qdrant running locally]
    └──requires──> [Document ingestion pipeline (.planning/ + runbooks)]
    └──enhances──> [Alert triage] (provides project-specific context)

[Alert triage queue]
    └──requires──> [Malcolm NSM deployed] (OpenSearch as alert source)
    └──requires──> [Foundation-Sec-8B (Ollama)] (AI enrichment)
    └──enhances──> [RAG corpus] (better answers with retrieval)
    └──feeds──> [DFIR-IRIS] (optional; case management differentiator)

[DFIR-IRIS case management]
    └──requires──> [Alert triage queue]
    └──requires──> [Docker Compose on supportTAK-server]

[SBOM + signed releases]
    └──requires──> [Syft installed]
    └──requires──> [Cosign installed + key generated]
    └──independent-of──> [Malcolm NSM] (supply chain feature, not SOC feature)
    └──independent-of──> [Foundation-Sec-8B]

[community-id correlation]
    └──requires──> [On-box Suricata config update]
    └──enhances──> [Malcolm NSM] (enables Zeek+Suricata join queries)
```

### Dependency Notes

- **Network tap is the hardest Malcolm dependency:** Malcolm's Zeek live capture needs raw packets mirrored from IPFire's interfaces. Without a SPAN port or hardware tap, Zeek can only analyze traffic already on the supportTAK-server's own NIC (management traffic only — not the firewall data plane). If no SPAN is available, Malcolm operates in "upload mode" only (PCAP file upload, Filebeat log forwarding) without live Zeek metadata. This is a significant capability gap.
- **16 GB RAM is below Malcolm's minimum:** Malcolm recommends 32+ GB, minimum 24 GB. supportTAK-server has 16 GB. This is the single biggest risk to the Malcolm deployment. Mitigation: aggressive OpenSearch heap tuning (4–6 GB), disable unused Malcolm containers, reduce Arkime PCAP threads.
- **Foundation-Sec-8B + Malcolm on the same 16 GB host:** Malcolm under memory pressure + Ollama loading a 4.92 GB model = likely OOM without careful resource allocation. The LLM should be loaded on-demand (not persistent daemon) or given a strict memory ceiling via Docker/systemd resource limits.
- **SBOM is independent:** Syft + Cosign does not depend on Malcolm or Foundation-Sec-8B. It can be implemented in any phase without blocking SOC features.
- **Loki decommission must be planned:** The existing Loki/Alloy/Grafana stack on supportTAK-server must be kept running until Malcolm is confirmed stable as a replacement. RAM on the 16 GB host cannot support both stacks simultaneously at full capacity.

---

## MVP Definition for v2.0

### Launch With (v2.0 — Local AI SOC)

The v2.0 milestone is complete when the telemetry backend has migrated to Malcolm and an AI analyst can triage alerts using project knowledge.

- [ ] **Malcolm deployed on supportTAK-server** — Docker Compose stack running with OpenSearch heap tuned for 16 GB host
- [ ] **IPFire EVE JSON flowing into Malcolm via Filebeat** — Suricata alerts visible in Malcolm OpenSearch Dashboards
- [ ] **Foundation-Sec-8B-Instruct Q4_K_M running via Ollama** — Model responds to security-domain queries via API
- [ ] **RAG corpus indexed** — ADRs, runbooks, validation results embedded and stored in ChromaDB
- [ ] **Alert triage script operational** — New critical Suricata alerts enriched by AI analyst with ATT&CK mapping and summary
- [ ] **SBOM generated and signed on git tag** — Syft + Cosign producing CycloneDX SBOM as part of release process
- [ ] **Loki stack decommissioned or confirmed redundant** — Clean handoff; no duplicate pipelines consuming RAM

### Add After Validation (v2.x)

- [ ] **Network tap / SPAN for Zeek live capture** — Requires hardware investigation; adds protocol-level visibility. Trigger: managed switch available or hardware tap sourced.
- [ ] **DFIR-IRIS case management** — Formal case tracking. Trigger: alert triage pipeline proven stable and producing quality output.
- [ ] **community-id correlation** — Enables Zeek+Suricata join queries in OpenSearch. Trigger: both Zeek and Suricata data flowing into Malcolm.
- [ ] **Broader telemetry ingestion** — Endpoint logs, auth logs, asset inventory via NetBox. Trigger: Malcolm stable with core IPFire telemetry.
- [ ] **Foundation-sec-8b-reasoning model** — Enhanced reasoning capabilities. Trigger: hardware upgrade (32+ GB RAM) or GPU acceleration added.

### Future Consideration (v3+)

- [ ] **Dedicated GPU acceleration for LLM inference** — Moves from 2–8 tok/sec to 40–80+ tok/sec. Trigger: budget and hardware upgrade.
- [ ] **DFIR-IRIS + n8n SOAR automation** — Full automated pipeline with human approval gates. Trigger: v2 alert triage proven reliable.
- [ ] **Qdrant replacing ChromaDB** — Production-grade vector DB with RBAC and hybrid search. Trigger: RAG corpus exceeds 100K vectors or access control becomes needed.
- [ ] **Multi-source threat intelligence RAG** — Ingest MITRE ATT&CK STIX data, NVD CVE feeds, ThreatFox IOC feeds into RAG corpus. Trigger: v2 RAG operational and valuable.

---

## Feature Prioritization Matrix

| Feature | Analyst Value | Implementation Cost | Priority |
|---------|--------------|---------------------|----------|
| Malcolm deployed + EVE JSON ingest | HIGH | HIGH | P1 |
| Foundation-Sec-8B via Ollama | HIGH | MEDIUM | P1 |
| Alert triage script (AI enrichment) | HIGH | MEDIUM | P1 |
| RAG corpus (ADRs + runbooks) | HIGH | MEDIUM | P1 |
| SBOM + signed releases | MEDIUM | LOW | P1 |
| OpenSearch Dashboards (Malcolm built-in) | HIGH | LOW (out-of-box) | P1 |
| Arkime PCAP investigation (Malcolm built-in) | HIGH | LOW (out-of-box) | P1 |
| Loki decommission | MEDIUM | MEDIUM | P1 |
| community-id correlation | MEDIUM | LOW | P2 |
| Network tap / Zeek live capture | HIGH | HIGH | P2 |
| DFIR-IRIS case management | MEDIUM | HIGH | P2 |
| File extraction + malware scan (Malcolm built-in) | MEDIUM | LOW (out-of-box) | P2 |
| Broader endpoint telemetry ingest | MEDIUM | MEDIUM | P2 |
| ATT&CK mapping on all alerts | HIGH | MEDIUM | P2 |
| Asset inventory via NetBox (Malcolm built-in) | LOW | LOW (out-of-box) | P3 |
| Foundation-sec-8b-reasoning model | MEDIUM | MEDIUM | P3 |
| Qdrant production vector DB | LOW | MEDIUM | P3 |
| Multi-source threat intel RAG | MEDIUM | HIGH | P3 |

---

## Competitor Feature Analysis

| Feature | Basic Malcolm (no AI) | Security Onion | This Project (v2) |
|---------|-----------------------|----------------|-------------------|
| Zeek NSM | Native | Native | Native (via Malcolm) |
| Suricata IDS | Native (containerized) | Native | On-box IPFire + Malcolm mirror |
| OpenSearch dashboards | Native (dozens prebuilt) | Native (Kibana) | Native (via Malcolm) |
| PCAP investigation | Arkime (native) | Zeek + Stenographer | Arkime (via Malcolm) |
| File extraction + malware scan | Native | Native | Native (via Malcolm) |
| AI alert triage | Not present | Not present | Foundation-Sec-8B (custom) |
| RAG over org knowledge | Not present | Not present | ChromaDB + LlamaIndex (custom) |
| ATT&CK auto-mapping | Not present | Not present | Foundation-Sec-8B (custom) |
| Case management | Not present | TheHive integration | DFIR-IRIS (v2.x) |
| Git-based reproducibility | Not present | Not present | Core project value |
| SBOM + signed releases | Not present | Not present | Syft + Cosign (custom) |
| Hardware requirement | 8C/24GB min | 4C/8GB min | N150 16GB (below Malcolm min) |

---

## Sources

- [Malcolm NSM Official Documentation](https://malcolm.fyi/docs/) — HIGH confidence
- [Malcolm System Requirements](https://malcolm.fyi/docs/system-requirements.html) — HIGH confidence (minimum 8C/24GB verified)
- [Malcolm Third-Party Logs / Filebeat Forwarding](https://malcolm.fyi/docs/third-party-logs.html) — HIGH confidence
- [Malcolm Live Analysis Documentation](https://malcolm.fyi/docs/live-analysis.html) — HIGH confidence
- [Malcolm Capabilities and Limitations](https://malcolm.fyi/docs/capabilities-and-limitations.html) — HIGH confidence
- [Malcolm GitHub (cisagov/Malcolm)](https://github.com/cisagov/Malcolm) — HIGH confidence
- [Foundation-Sec-8B Cisco Blog](https://blogs.cisco.com/security/foundation-sec-cisco-foundation-ai-first-open-source-security-model) — HIGH confidence
- [Foundation-Sec-8B-Instruct: Out-of-the-Box Security Copilot](https://blogs.cisco.com/security/foundation-sec-8b-instruct-out-of-the-box-security-copilot) — HIGH confidence
- [Foundation-Sec-8B Q4_K_M GGUF (Hugging Face)](https://huggingface.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF) — HIGH confidence (~4.92 GB)
- [Foundation-Sec-8B Q8_0 GGUF (Hugging Face)](https://huggingface.co/fdtn-ai/Foundation-Sec-8B-Instruct-Q8_0-GGUF) — HIGH confidence (~8.54 GB)
- [Foundation-sec-8b-reasoning (Cisco Blog)](https://blogs.cisco.com/security/foundation-sec-8b-reasoning-worlds-first-security-reasoning-model) — HIGH confidence
- [How to Run Foundation-Sec-8B-Reasoning in Ollama (Feb 2026)](https://ai.plainenglish.io/how-to-run-ciscos-foundation-sec-8b-reasoning-in-ollama-diy-guide-c073c441dc06) — MEDIUM confidence
- [DFIR-IRIS Official Site](https://www.dfir-iris.org/) — HIGH confidence
- [SOC Automation Lab: DFIR-IRIS + n8n + LLM](https://github.com/chalithah/SOC-Automation-Lab) — MEDIUM confidence
- [Syft SBOM Generation Guide (Jan 2026)](https://oneuptime.com/blog/post/2026-01-25-sbom-generation-syft/view) — HIGH confidence
- [Creating SBOM Attestations Using Syft and Sigstore (Anchore)](https://anchore.com/sbom/creating-sbom-attestations-using-syft-and-sigstore/) — HIGH confidence
- [OWASP Dependency Graph SBOM Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Dependency_Graph_SBOM_Cheat_Sheet.html) — HIGH confidence
- [SPDX vs CycloneDX Comparison (CSO Online)](https://www.csoonline.com/article/573291/sbom-formats-spdx-and-cyclonedx-compared.html) — MEDIUM confidence
- [RAG and Agentic AI in Cybersecurity (OpenText)](https://blogs.opentext.com/rag-and-agentic-ai-revolutionizing-cybersecurity-analysis/) — MEDIUM confidence
- [LLM Hallucinations in 2026 (Lakera)](https://www.lakera.ai/blog/guide-to-hallucinations-in-large-language-models) — MEDIUM confidence
- [Context Window Failures in LLMs](https://pr-peri.github.io/llm/2026/02/13/why-hallucination-happens.html) — MEDIUM confidence
- [Chroma DB vs Qdrant Comparison (Airbyte)](https://airbyte.com/data-engineering-resources/chroma-db-vs-qdrant) — MEDIUM confidence
- [Malcolm Network Traffic Analysis (INL PDF)](https://inl.gov/content/uploads/2023/07/Network-Traffic-Analysis-with-Malcolm.pdf) — MEDIUM confidence (2023, architecture still valid)
- [Autonomous AI SOC for Alert Triage (Scribd)](https://www.scribd.com/document/889887906/Design-and-Implementation-of-an-Autonomous-AI-Agent-Security-Operations-Center-SOC-for-Alert-Triag) — MEDIUM confidence

---

*Feature research for: Local-first AI SOC — v2.0 milestone (Malcolm NSM + Foundation-Sec-8B + RAG + triage + SBOM)*
*Researched: 2026-03-31*
