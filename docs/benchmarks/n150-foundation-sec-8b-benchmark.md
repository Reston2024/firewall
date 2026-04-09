> **DEPRECATED — ADR-E04:** AI removed from data layer. Model deleted from supportTAK-server.
> All AI inference now runs on the desktop SOC (RTX 5080, qwen3:14b).
> Retained for audit trail only.

# Foundation-Sec-8B Benchmark on Intel N150

**Date:** 2026-04-06
**Hardware:** GMKtec NucBox G3 Plus, Intel N150, 4 cores, 16GB DDR5, Ubuntu 22.04
**Model:** fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF (4.9GB)
**Runtime:** Ollama 0.9.2
**Context Length:** 2048 (OLLAMA_CONTEXT_LENGTH=2048)

## Benchmark Results

### Prompt 1: CVE Analysis (CVE-2024-3094 xz backdoor)

| Metric | Value |
|--------|-------|
| Prompt eval rate | 5.82 tokens/s |
| Generation eval rate | **2.47 tokens/s** |
| Total tokens generated | 2,167 |
| Total duration | 14 min 48 sec |
| Load duration | 7.48 sec |
| Prompt eval (26 tokens) | 4.47 sec |

### Response Quality

The model produced a coherent, technically accurate analysis of CVE-2024-3094 including:
- Correct identification of xz-utils supply chain compromise
- Detection recommendations (commit ID, compilation flags)
- Impact assessment (remote command execution)
- Remediation steps (update, scan, segment, monitor)

## RAM Coexistence

| State | RAM Used | Swap Used |
|-------|----------|-----------|
| Malcolm only (steady state) | ~11.7 GB | ~1.7 GB |
| Malcolm + Ollama loaded | > 16 GB (swap required) | ~4+ GB |
| Ollama only (Malcolm paused) | ~7-8 GB | minimal |

**Conclusion:** Temporal separation is MANDATORY. Malcolm and Foundation-Sec-8B cannot coexist in physical RAM on 16GB. The AI model must be loaded on-demand with Malcolm containers paused, or triage must run during low-traffic periods when Malcolm's working set is reduced.

## Phase 13 Gate Decision

| Criterion | Threshold | Measured | Status |
|-----------|-----------|----------|--------|
| Generation throughput | >= 2 tok/s | 2.47 tok/s | **PASS** |
| Prompt eval throughput | >= 2 tok/s | 5.82 tok/s | **PASS** |
| Model loads without OOM | No OOM kills | None observed | **PASS** |

**Gate verdict: PASS** — Phase 13 triage pipeline can proceed with batch async design.

### Design Implications for Phase 13

- **Batch async only:** At 2.47 tok/s, a 500-token triage response takes ~3.4 minutes. Not viable for interactive/synchronous use.
- **Temporal separation enforced:** Triage script must: (1) pause non-essential Malcolm containers, (2) load model, (3) run batch, (4) unload model, (5) restart Malcolm containers.
- **Max response length:** Cap at 512 tokens (~3.5 min) to keep individual triage under 4 minutes.
- **Batch size:** Process 5-10 alerts per triage run, schedule via systemd timer during off-hours.

---

*Benchmark conducted 2026-04-06 on live supportTAK-server with Malcolm 27-container stack running*
