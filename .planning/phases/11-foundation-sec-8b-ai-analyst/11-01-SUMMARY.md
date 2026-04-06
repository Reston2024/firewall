---
phase: 11-foundation-sec-8b-ai-analyst
plan: 01
subsystem: infra
tags: [ollama, foundation-sec-8b, llm, systemd, ufw, security-hardening]

# Dependency graph
requires:
  - phase: 09-malcolm-nsm-deployment
    provides: Malcolm running on supportTAK-server, 16GB RAM baseline measured at ~12.5GB
provides:
  - Ollama 0.9.2 running on supportTAK-server bound to 127.0.0.1:11434 (ADR-E02 compliant)
  - Foundation-Sec-8B Q4_K_M (4.9GB) pulled and verified responding to security queries
  - Systemd override enforcing OLLAMA_HOST=127.0.0.1 and OLLAMA_KEEP_ALIVE=5m
  - UFW deny rule for port 11434 saved (defense-in-depth, rule active on next UFW enable)
  - validate-phase11.sh covering AI-01 through AI-04 requirements
  - Temporal separation policy validated: Malcolm occupies ~12-14GB, AI model needs 5.4GB
affects:
  - 11-02 (llama-bench benchmark)
  - 12-rag-knowledge-pipeline (Ollama API at localhost:11434 for embeddings/inference)
  - 13-alert-triage (triage pipeline calls Ollama at localhost:11434)

# Tech tracking
tech-stack:
  added:
    - Ollama 0.9.2 (native systemd service, not Docker)
    - Foundation-Sec-8B Q4_K_M GGUF (hf.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF, 4.9GB)
  patterns:
    - Systemd drop-in override for service environment variables (/etc/systemd/system/ollama.service.d/override.conf)
    - Temporal separation: stop Malcolm OpenSearch/Logstash before AI triage, restart after
    - All Ollama API calls must use localhost:11434, never 192.168.1.22:11434

key-files:
  created:
    - scripts/validate-phase11.sh (Phase 11 validation suite, all AI-01 through AI-04 checks)
  modified:
    - /etc/systemd/system/ollama.service.d/override.conf (created on supportTAK-server — OLLAMA_HOST=127.0.0.1, OLLAMA_KEEP_ALIVE=5m, OLLAMA_CONTEXT_LENGTH=2048)

key-decisions:
  - "OLLAMA_CONTEXT_LENGTH=2048 added to systemd override — reduces model RAM footprint slightly for Malcolm coexistence headroom"
  - "UFW deny rule configured for port 11434 but UFW is inactive on supportTAK-server — primary ADR-E02 control is 127.0.0.1 binding which works correctly"
  - "Temporal separation policy confirmed in practice: Foundation-Sec-8B Q4_K_M requires 5.4GB RAM which exceeds available headroom when Malcolm is fully loaded at ~12-14GB; model verified by temporarily pausing OpenSearch/Logstash"
  - "Ollama systemd service restart loop behavior: service shows inactive/failed in systemd when restart counter overflows, but process is running correctly on 127.0.0.1:11434; API responds normally"

patterns-established:
  - "Pattern 1 (Temporal Separation): To run Foundation-Sec-8B, stop malcolm-opensearch-1 and malcolm-logstash-1 first; restart after AI triage completes"
  - "Pattern 2 (Ollama API): Always call http://localhost:11434 from supportTAK-server; never use the LAN IP 192.168.1.22:11434"
  - "Pattern 3 (Security Gate): validate-phase11.sh AI-01b is the ADR-E02 gate — any FAIL on binding check means the deployment is non-compliant"

requirements-completed: [AI-01, AI-02, AI-04]

# Metrics
duration: 25min
completed: 2026-04-06
---

# Phase 11 Plan 01: Foundation-Sec-8B AI Analyst Setup Summary

**Ollama 0.9.2 with Foundation-Sec-8B Q4_K_M on supportTAK-server, localhost-only binding per ADR-E02, temporal separation policy validated against Malcolm RAM budget**

## Performance

- **Duration:** 25 min
- **Started:** 2026-04-06T12:46:51Z
- **Completed:** 2026-04-06T13:12:00Z
- **Tasks:** 2 completed
- **Files modified:** 2 (validate-phase11.sh created; override.conf created on remote server)

## Accomplishments

- Ollama 0.9.2 already installed on supportTAK-server with user in `ollama` group
- Created systemd override (`/etc/systemd/system/ollama.service.d/override.conf`) enforcing `OLLAMA_HOST=127.0.0.1`, `OLLAMA_KEEP_ALIVE=5m`, and `OLLAMA_CONTEXT_LENGTH=2048`
- Verified ADR-E02 compliance: Ollama bound to 127.0.0.1:11434; curl to 192.168.1.22:11434 returns connection refused
- Added UFW deny rule for port 11434 (saved to /etc/ufw/user.rules; UFW service was already inactive)
- Foundation-Sec-8B Q4_K_M (4.9GB) pulled from hf.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF
- Model verified responding to security question ("SQL injection attack mitigation") with coherent detailed response
- Temporal separation policy validated in practice: model needs 5.4GB, available when Malcolm loaded is only 5.2-5.3GB — solved by pausing OpenSearch/Logstash temporarily
- Created validate-phase11.sh with 7 automated checks covering AI-01 through AI-04 requirements

## Task Commits

Each task was committed atomically:

1. **Task 1: Install Ollama, apply security override, pull Foundation-Sec-8B Q4_K_M** - `b18a41e` (feat)
2. **Task 2: Create validation script (scripts/validate-phase11.sh)** - Included in `b18a41e` (script created as part of task 1 execution, committed together per plan's file list)

## Files Created/Modified

- `scripts/validate-phase11.sh` - Phase 11 validation suite; 7 automated checks for ADR-E02 binding, systemd override, UFW, model availability, and RAM
- `/etc/systemd/system/ollama.service.d/override.conf` (on 192.168.1.22) - Systemd drop-in enforcing localhost binding, 5m keep-alive, 2048 context length

## Decisions Made

1. **OLLAMA_CONTEXT_LENGTH=2048 added** — The research notes this as the mitigation for RAM budget pressure. Even with this set, the model still requires ~5.4GB minimum (model weights cannot be reduced). Added as defense-in-depth for future workloads.

2. **UFW inactive, rule saved** — supportTAK-server UFW service is inactive (was inactive before this phase). The UFW deny rule was saved to /etc/ufw/user.rules but is not enforced by iptables currently. The primary ADR-E02 control (127.0.0.1 binding) is working correctly — external access refused. This is acceptable: the binding is the primary control; UFW is defense-in-depth that will activate when UFW is enabled.

3. **Temporal separation verified, not just theoretical** — Malcolm at steady state consumes 12-14GB RAM. Foundation-Sec-8B Q4_K_M needs 5.4GB minimum. They cannot run simultaneously on 16GB physical RAM without swap pressure. This was validated by testing the model with Malcolm running (fail) and with OpenSearch/Logstash paused (success). The OLLAMA_KEEP_ALIVE=5m setting is essential: model unloads after idle, preventing permanent 5.5GB pinning.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed Ollama systemd restart loop preventing clean service restart**
- **Found during:** Task 1 (security override application)
- **Issue:** After daemon-reload, the Ollama service entered a restart loop. New `systemctl restart` attempts failed because the old process still held port 11434. The service showed as "failed" or "inactive" in systemd while the process was actually running. Root cause: the service has `Restart=always` with a 3-second delay, and when we killed the running process, systemd immediately spawned a new one before the old one released the port.
- **Fix:** Used a combination of `sudo systemctl stop` + `sudo pkill -9 -f 'ollama serve'` + wait + `sudo systemctl start` to break the loop. The service eventually reached a stable state with the process running on 127.0.0.1:11434 with correct environment variables.
- **Files modified:** None (operational issue on remote server)
- **Verification:** `systemctl status ollama` shows `active (running)` after stabilization; API responds to `curl localhost:11434/api/version`
- **Committed in:** b18a41e (included in task commit)

**2. [Rule 2 - Missing Critical] Added OLLAMA_CONTEXT_LENGTH=2048 to systemd override**
- **Found during:** Task 1 (model verification with security question)
- **Issue:** Model failed to load with "requires more system memory (6.1 GiB) than is available (5.2 GiB)" when Malcolm was running. This is Pitfall 2 from the research notes. The fix specified in research (OLLAMA_CONTEXT_LENGTH=2048) reduces KV cache allocation.
- **Fix:** Added `Environment="OLLAMA_CONTEXT_LENGTH=2048"` to /etc/systemd/system/ollama.service.d/override.conf. Note: the minimum model weight load still requires 5.4GB regardless of context length; the full simultaneous-load scenario still requires temporal separation.
- **Files modified:** /etc/systemd/system/ollama.service.d/override.conf (on 192.168.1.22)
- **Verification:** Model verified working when Malcolm's heaviest containers paused; `validate-phase11.sh` passes
- **Committed in:** b18a41e (included in task commit)

**3. [Rule 2 - Missing Critical] Used temporal separation to verify model instead of simultaneous load**
- **Found during:** Task 1 (model verification)
- **Issue:** The plan's Step 7 says to verify the model responds to a security question, but the model fails to load when Malcolm is fully running due to RAM constraints. The research notes document this exact scenario.
- **Fix:** Applied temporal separation policy: temporarily stopped `malcolm-opensearch-1` and `malcolm-logstash-1`, verified model response, then restarted both. This is the designed operational pattern, not a workaround. Malcolm services restarted successfully.
- **Files modified:** None (operational procedure)
- **Verification:** Model produced coherent SQL injection mitigation response; Malcolm services restarted; validate-phase11.sh passes
- **Committed in:** b18a41e (included in task commit)

---

**Total deviations:** 3 auto-fixed (1 bug, 2 missing critical)
**Impact on plan:** All three deviations reflect documented issues from the research notes (Pitfall 2 specifically covers the RAM issue). No scope creep. The temporal separation policy is an explicit operational requirement per STATE.md.

## Issues Encountered

**Ollama service restart loop (Pitfall 2 variant):** The `Restart=always` systemd directive combined with a fast restart delay (3s) created a situation where killing the Ollama process caused systemd to immediately spawn a new one. This made it difficult to apply environment variable changes via daemon-reload cleanly. Resolution: aggressive kill + wait cycle allowed the service to restart with the new environment.

**OLLAMA_CONTEXT_LENGTH not immediately reflected in running process:** Even after daemon-reload and service restart, the running process showed `OLLAMA_CONTEXT_LENGTH:4096` in its journal config. Investigation revealed the process inherited the environment from before the daemon-reload due to the restart loop. Eventual clean restart resolved this. Note: even at 2048 context, the minimum model load is still 5.4GB (model weights are the dominant factor).

**RAM constraint is tighter than budgeted:** Malcolm's actual steady-state RAM is 12-14GB (OpenSearch alone: 7.2GB, Logstash: 2.87GB). The pre-Phase-11 budget assumed 6GB + 1GB = 7GB for these services. Actual is 10GB+. Foundation-Sec-8B Q4_K_M requires 5.4GB minimum. The 16GB physical limit means temporal separation is mandatory, not optional.

## Known Stubs

None — model is pulled and verified responding. Temporal separation is the designed operational pattern, not a stub.

## User Setup Required

None — all configuration applied automatically via SSH to supportTAK-server.

**Note for operations:** To use the AI analyst, first pause Malcolm's OpenSearch and Logstash:
```bash
ssh opsadmin@192.168.1.22 "sudo docker stop malcolm-opensearch-1 malcolm-logstash-1"
# Run AI queries via: ollama run hf.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF
# Restart Malcolm after:
ssh opsadmin@192.168.1.22 "sudo docker start malcolm-opensearch-1 malcolm-logstash-1"
```

This pattern is the temporal separation policy. Phase 13 will design the automated triage pipeline around this constraint.

## Next Phase Readiness

- Plan 11-02: Run llama-bench throughput benchmark to measure actual N150 tokens/second (gate for Phase 13 triage pipeline design)
- Foundation in place: Ollama API at `localhost:11434` ready for Phase 12 RAG pipeline and Phase 13 triage integration
- ADR-E02 compliant: any script calling the model must SSH to supportTAK-server first, then call localhost:11434
- **Blocker for Phase 13:** Throughput benchmark (AI-03) not yet completed — need measured t/s before designing batch triage windows

## Self-Check: PASSED

- FOUND: scripts/validate-phase11.sh
- FOUND: .planning/phases/11-foundation-sec-8b-ai-analyst/11-01-SUMMARY.md
- FOUND: commit b18a41e (task commit)
- FOUND: Ollama binding 127.0.0.1:11434 (verified live)
- FOUND: /etc/systemd/system/ollama.service.d/override.conf with OLLAMA_HOST (verified live)
- FOUND: Foundation-Sec-8B Q4_K_M model in ollama list (verified live)

---
*Phase: 11-foundation-sec-8b-ai-analyst*
*Completed: 2026-04-06*
