# Phase 11: Foundation-Sec-8B AI Analyst - Research

**Researched:** 2026-04-06
**Domain:** Ollama native install + Foundation-Sec-8B Q4_K_M inference on Intel N150 CPU, systemd configuration, security hardening
**Confidence:** HIGH for Ollama mechanics and security config. LOW for actual N150 inference throughput (no hardware-specific benchmarks exist; must measure post-deployment).

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| AI-01 | Ollama installed natively (not Docker) on supportTAK-server with Foundation-Sec-8B Q4_K_M model | Ollama native install via `install.sh` confirmed; HF pull syntax `hf.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF` verified; model is 4.92 GB |
| AI-02 | OLLAMA_KEEP_ALIVE=5m configured to unload model after idle periods, preventing permanent 5GB RAM pinning | Systemd override pattern confirmed; `OLLAMA_KEEP_ALIVE=5m` is the correct env var format |
| AI-03 | llama-bench throughput benchmark run and documented to establish actual N150 tokens/second before triage pipeline design | llama-bench is a llama.cpp tool; Ollama's `--verbose` flag and `ollama run --verbose` emit pp/tg stats; no N150 data exists — must measure live |
| AI-04 | AI analyst produces recommendations only — no automated firewall rule changes or response actions | Enforced by ADR-E02 localhost-only binding; validator script must check for absence of response automation |
</phase_requirements>

---

## Summary

Phase 11 installs Ollama natively on supportTAK-server, pulls Foundation-Sec-8B Q4_K_M from HuggingFace, configures the systemd service unit with two mandatory environment variables (`OLLAMA_HOST=127.0.0.1` and `OLLAMA_KEEP_ALIVE=5m`), closes the firewall port, and documents actual inference throughput via benchmarking.

The primary technical work is straightforward: the Ollama install script handles the systemd unit, and the HuggingFace pull URL format is verified. The critical constraint is ADR-E02 (security finding E6-01 CRITICAL): Ollama's default bind is `0.0.0.0:11434` with no authentication. This must be overridden before the model is loaded. The systemd override must come before `ollama pull` to prevent any window where the API is network-accessible.

The critical unknown remains N150 inference throughput. No published benchmarks exist for Foundation-Sec-8B Q4_K_M on Intel N150. The 3-7 t/s estimate from prior research is based on comparable Alder Lake-N architecture with Intel Xe graphics Vulkan benchmarks and single-channel DDR5 memory bandwidth (~38 GB/s theoretical). This phase's primary deliverable beyond installation is a documented `llama-bench` result that gates Phase 13 (alert triage pipeline) design decisions.

**Primary recommendation:** Install Ollama, apply systemd security override before pulling the model, run benchmarks, validate security posture (`ss -tlnp | grep 11434` must show 127.0.0.1), and document tokens/second as a hard artifact. This phase is complete only when the throughput number exists in writing.

---

## Standard Stack

### Core

| Library / Tool | Version | Purpose | Why Standard |
|----------------|---------|---------|--------------|
| Ollama | Current (0.18.2+ as of March 2026) | Local LLM inference server, model management, OpenAI-compatible API | Native systemd service; `OLLAMA_KEEP_ALIVE` and `OLLAMA_HOST` env vars control RAM and binding; ~43 MB idle footprint |
| Foundation-Sec-8B Q4_K_M | From `fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF` on HuggingFace | Cybersecurity-domain 8B LLM (Llama 3.1, continued pretraining on CVEs + ATT&CK + threat intel) | Only viable quantization on 16 GB system; 4.92 GB model file; Q8_0 (8.54 GB) is not viable at 16 GB alongside Malcolm |
| llama-bench (llama.cpp) | Bundled with llama.cpp build | CPU inference throughput benchmarking | The authoritative benchmarking tool for GGUF inference; produces pp (prompt processing) and tg (token generation) t/s numbers |
| ufw | Ubuntu system | Firewall rule to deny external access to port 11434 | Defense-in-depth per ADR-E02; blocks port even if OLLAMA_HOST misconfiguration occurs |

### Supporting

| Library / Tool | Version | Purpose | When to Use |
|----------------|---------|---------|-------------|
| `ollama run --verbose` | Built-in | Quick in-process throughput check | After install to confirm model loads and show eval rate in terminal output |
| `ollama ps` | Built-in | Show currently loaded models and memory allocation | Verifying model unloads after KEEP_ALIVE window |
| `free -m` | Linux system | RAM usage snapshot | Validating Malcolm + Ollama loaded simultaneously stays under 15.5 GB |
| `ss -tlnp` | Linux system | Verify Ollama socket binding | Security gate: must show 127.0.0.1, never 0.0.0.0 |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Ollama native | llama.cpp server directly | llama.cpp binary is 90 MB vs Ollama's full install; OpenAI-compatible `/v1` endpoint available on both; use llama.cpp directly only if Ollama abstraction causes problems |
| `hf.co/` pull via Ollama | Manual Modelfile with GGUF path | `hf.co/` syntax is the official HuggingFace-Ollama integration; no Modelfile required for standard GGUF repos |
| Foundation-Sec-8B Q4_K_M | Llama-3.1-8B-Instruct general | Foundation-Sec-8B benchmarks show strong cyber-domain specialization; general model is fallback only if cyber accuracy proves insufficient |

**Installation:**
```bash
# Install Ollama natively (creates systemd service automatically)
curl -fsSL https://ollama.com/install.sh | sh

# Apply security override BEFORE pulling model
mkdir -p /etc/systemd/system/ollama.service.d
# write override.conf — see Code Examples section below
systemctl daemon-reload && systemctl restart ollama

# Verify binding before pulling
ss -tlnp | grep 11434  # MUST show 127.0.0.1

# Close firewall port (defense-in-depth per ADR-E02)
ufw deny 11434

# Pull Foundation-Sec-8B Q4_K_M from HuggingFace
# Default quantization when Q4_K_M is present in repo is Q4_K_M
ollama pull hf.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF
```

---

## Architecture Patterns

### Systemd Override Pattern (MANDATORY)

Ollama installs as a systemd service via `install.sh`. The service environment must be overridden via the drop-in directory — shell-exported variables do NOT apply to systemd services.

```
/etc/systemd/system/ollama.service.d/
└── override.conf     # contains OLLAMA_HOST and OLLAMA_KEEP_ALIVE
```

### Ollama + Malcolm Coexistence Model

```
supportTAK-server (192.168.1.22)
├── Malcolm (Docker Compose)       — persistent, 27 containers, ~12.5 GB RSS
│   ├── OpenSearch (6 GB heap)
│   ├── Logstash (1 GB heap)
│   └── ... (25 other containers, ~1.5 GB combined)
├── Ollama systemd service         — persistent, ~43 MB idle
│   └── Foundation-Sec-8B Q4_K_M  — loaded ON DEMAND, ~5.5 GB
│       └── unloads after 5m idle (OLLAMA_KEEP_ALIVE=5m)
└── Ubuntu OS                      — ~1.5-2 GB
```

**RAM budget at worst-case simultaneous load:**
- Malcolm steady-state: ~12.5 GB (measured in Phase 9)
- Foundation-Sec-8B Q4_K_M loaded: ~5.5 GB (model + KV cache)
- Total: ~15.5 GB of 16 GB (per ADR and STATE.md)
- Existing swap: 6 GB pre-existing (adequate safety net)

This is a tight budget. The model MUST unload when idle to allow Malcolm headroom during OpenSearch GC spikes.

### Pattern 1: Two-Variable Systemd Override

**What:** Set both security binding and memory management in a single override file.
**When to use:** Always — this is the mandatory configuration per ADR-E02.

```ini
# Source: ADR-E02 + Ollama FAQ (docs.ollama.com/faq)
# /etc/systemd/system/ollama.service.d/override.conf
[Service]
Environment="OLLAMA_HOST=127.0.0.1"
Environment="OLLAMA_KEEP_ALIVE=5m"
```

Note: `OLLAMA_HOST=127.0.0.1` without a port defaults to port 11434. Explicitly specifying `127.0.0.1:11434` is also valid and equivalent.

### Pattern 2: HuggingFace Direct Pull

**What:** Pull GGUF models directly from HuggingFace via `hf.co/` prefix in Ollama.
**When to use:** When the model has no official Ollama registry entry. Foundation-Sec-8B is not in the official Ollama library as of the research date; the community upload at `FenkoHQ/Foundation-Sec-8B` exists but is not from the model authors. The official GGUF from fdtn-ai is on HuggingFace.

```bash
# Source: HuggingFace Ollama integration docs (huggingface.co/docs/hub/en/ollama)
# Default: selects Q4_K_M when that file is present in the repo
ollama pull hf.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF

# Explicit quantization tag (also valid):
ollama pull hf.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF:Q4_K_M
```

### Pattern 3: Benchmark Before Building

**What:** Run throughput benchmarks and document results before Phase 13 triage design.
**When to use:** Phase 11 gate — throughput must be documented before the triage pipeline can be designed for a specific latency budget.

Ollama provides `--verbose` flag showing eval rate in terminal. For a more rigorous benchmark, llama-bench from llama.cpp provides pp (prompt processing) and tg (token generation) numbers:

```bash
# Quick throughput check via Ollama verbose run
ollama run hf.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF --verbose \
  "Describe CVE-2024-1234 and its ATT&CK mapping."
# Look for: "eval rate" in the output (tokens/s)

# Rigorous benchmark via llama-bench (requires llama.cpp build)
# Install llama.cpp build tools:
apt install -y build-essential cmake
git clone --depth 1 https://github.com/ggml-org/llama.cpp /tmp/llama.cpp
cd /tmp/llama.cpp && cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build --target llama-bench -j4

# Find the model GGUF (Ollama stores models in ~/.ollama/models/blobs/)
GGUF_PATH=$(find ~/.ollama/models/blobs -name "*.gguf" | head -1)

# Run benchmark (pp=prompt processing at 512 tokens, tg=token generation at 128 tokens)
./build/bin/llama-bench -m "$GGUF_PATH" -p 512 -n 128 -r 3
```

### Anti-Patterns to Avoid

- **0.0.0.0 binding (default):** Ollama defaults to `0.0.0.0:11434`. This exposes Foundation-Sec-8B to every GREEN subnet device with no authentication. OWASP LLM01 (Prompt Injection) — highest risk vector. Always override before pulling.
- **OLLAMA_KEEP_ALIVE=-1 (permanent load):** Keeps ~5.5 GB pinned continuously. Causes OpenSearch GC pressure and potential OOM during Malcolm indexing spikes. Use `5m` — the model cold-starts in 15-20 seconds, which is acceptable for Phase 13 batch triage.
- **Model pull before systemd override:** If the model is pulled and a test run done before the override, there is a window where the API is network-accessible. Apply the override and restart the service before `ollama pull`.
- **Using shell `export` for environment variables:** Variables exported in a shell session do NOT apply to the Ollama systemd service. Only `systemctl edit ollama.service` or the drop-in override file works.
- **`OLLAMA_HOST=0.0.0.0` for remote management access:** Remote management must be done via SSH to supportTAK-server first, then `curl localhost:11434`. Never expose the API on the network — per ADR-E02, there is no authentication mechanism.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Model memory lifecycle | Custom "load/unload" scripts | `OLLAMA_KEEP_ALIVE=5m` in systemd override | Ollama handles idle detection and unload automatically; custom scripts introduce race conditions with in-flight requests |
| Process supervision | Manual screen/tmux session | `systemctl` (Ollama's native systemd unit) | Systemd handles restart-on-failure, boot start, log routing to journald |
| CPU inference throughput | Writing a custom benchmarking harness | `llama-bench` from llama.cpp + `ollama run --verbose` | llama-bench is the canonical tool for GGUF CPU inference benchmarking; produces reproducible pp/tg numbers |
| Port access control | Application-layer auth proxy | `OLLAMA_HOST=127.0.0.1` + `ufw deny 11434` | Binding restriction + firewall rule is the only viable control (Ollama has no auth layer); no proxy needed for localhost-only use |
| Model download and format management | Manual GGUF download + Modelfile | `ollama pull hf.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF` | Ollama handles GGUF download, registry, symlinks, and chat template extraction from GGUF metadata |

**Key insight:** This phase is almost entirely infrastructure configuration, not code. The complexity is in the security posture (binding + firewall) and the benchmark documentation, not in model serving code. Resist the urge to add application logic here — Phase 13 is the triage pipeline.

---

## Common Pitfalls

### Pitfall 1: Installing Ollama Before Applying Security Override

**What goes wrong:** The Ollama installer creates a systemd service that starts immediately after install. The default binding is `0.0.0.0:11434`. If the user runs `ollama pull` or `ollama run` before the systemd override is applied, the API is exposed on the LAN during that window.

**Why it happens:** The install script starts the service immediately. The security override documentation is in the FAQ, not the installer.

**How to avoid:** After `curl -fsSL https://ollama.com/install.sh | sh`, immediately stop the service, create the override file, then restart. Alternatively: apply the override before running the install script (if the override directory already exists, it is respected on first start).

**Warning signs:** `ss -tlnp | grep 11434` shows `0.0.0.0:*` — means the default is active and the override was not applied.

### Pitfall 2: RAM Budget Exceeded During Simultaneous Malcolm + Model Load

**What goes wrong:** Malcolm at Phase 9 steady state consumes ~12.5 GB RSS (higher than the ~11.7 GB budgeted — the 27-container reality exceeded the pre-deployment estimate). Foundation-Sec-8B Q4_K_M loads to ~5.5 GB. Total: ~18 GB, which exceeds 16 GB physical RAM.

**Why it happens:** Malcolm's actual RAM footprint (12.5 GB, measured in Phase 9 summary) is 0.8 GB higher than the pre-deployment estimate. The RAM budget must be re-validated with the actual measured baseline.

**How to avoid:**
- Run `free -m` with Malcolm loaded and stable before starting `ollama run`
- Document the measured simultaneous baseline: `free -m` after first model load
- Reduce context size if needed: `OLLAMA_CONTEXT_LENGTH=2048` in the systemd override limits KV cache size and reduces model RAM footprint by ~0.5-1 GB
- Phase 11 success criteria requires `free -m` showing total < 15.5 GB — if measured higher, add `OLLAMA_CONTEXT_LENGTH=2048` to the override and re-measure

**Warning signs:** `free -m` shows swap usage climbing during model load; `dmesg | grep -i oom` shows Malcolm container kills; `docker stats` shows OpenSearch container restarting.

### Pitfall 3: Ollama Model Registry vs. HuggingFace Pull Confusion

**What goes wrong:** The success criteria in the brief says `ollama run fdtn-ai/Foundation-Sec-8B-Q4_K_M`. This is not a valid Ollama registry path. `fdtn-ai` is not a registered Ollama namespace. The model is on HuggingFace; Ollama pulls it via the `hf.co/` prefix.

**Why it happens:** The success criteria was written assuming the model would be in the Ollama library. As of research date, only a community upload exists at `FenkoHQ/Foundation-Sec-8B` (not from the model authors). The official GGUF is from `fdtn-ai` on HuggingFace.

**How to avoid:** Use `ollama pull hf.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF` — the `hf.co/` prefix routes through Ollama's HuggingFace integration, which handles GGUF download and chat template extraction automatically. After pull, the model is addressable locally as `hf.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF` in subsequent `ollama run` commands.

**Warning signs:** `ollama pull fdtn-ai/Foundation-Sec-8B-Q4_K_M` returns "model not found" — this is expected; use `hf.co/` prefix.

### Pitfall 4: llama-bench Not Available Natively — Must Build from Source

**What goes wrong:** `llama-bench` is not installed by Ollama. It is part of the llama.cpp build tools. Running it requires either building llama.cpp from source on the N150 or using a pre-compiled binary. Building on a 4-core N150 takes 5-10 minutes; `cmake` and `build-essential` must be installed.

**Why it happens:** Ollama abstracts away llama.cpp internals. The benchmarking toolchain is separate.

**How to avoid:** For a quick throughput check without building llama.cpp, use `ollama run --verbose` and read the `eval rate` printed at the end of the response. This is sufficient for Phase 11's requirement to document actual tokens/second on N150. Reserve the full `llama-bench` build for when a more rigorous baseline is needed (e.g., comparing CPU vs. Vulkan iGPU offload). The `eval rate` from `ollama run --verbose` is acceptable for the Phase 11 gate.

**Warning signs:** Attempting to run `llama-bench` without building llama.cpp produces "command not found" — expected behavior.

### Pitfall 5: N150 Inference Is Slower Than Expected — 3 t/s Not 7 t/s

**What goes wrong:** The 3-7 t/s estimate is based on Intel Iris Xe (Tiger Lake GT2) Vulkan benchmarks. The N150 uses a newer Twin Lake microarchitecture with 24 execution units of Intel Xe integrated graphics, but the critical constraint is single-channel DDR5 memory bandwidth (~38 GB/s). Foundation-Sec-8B Q4_K_M requires ~23 GB/s to load model weights per inference step. On single-channel DDR5, actual throughput may land at the low end (3-4 t/s) or possibly below if memory is shared with Malcolm's OpenSearch working set.

**Why it happens:** Memory bandwidth is the binding constraint for CPU LLM inference on low-power processors. Single-channel is verified for the Intel N150.

**How to avoid:** Design Phase 13 (triage pipeline) for 2-4 t/s (pessimistic case), not 7 t/s. A 512-token triage response takes 2-4 minutes at 2-4 t/s. This forces an async batch design. The STATE.md gate is explicit: if measured throughput is below 2 t/s, Phase 13 design requires revision before proceeding.

**Warning signs:** `eval rate: 2 tokens/s` or lower in `ollama run --verbose` output — triggers Phase 13 design review gate.

---

## Code Examples

### Override File (Mandatory Security + Memory Configuration)

```ini
# Source: ADR-E02 (decisions/ADR-E02-ollama-localhost-binding.md)
# /etc/systemd/system/ollama.service.d/override.conf

[Service]
Environment="OLLAMA_HOST=127.0.0.1"
Environment="OLLAMA_KEEP_ALIVE=5m"
```

Apply with:
```bash
systemctl daemon-reload
systemctl restart ollama
```

### Verify Security Binding (ADR-E02 Gate)

```bash
# Source: ADR-E02 verification gate
# Must show 127.0.0.1, NOT 0.0.0.0
ss -tlnp | grep 11434

# Must be refused from LAN (run from 192.168.1.100 or another GREEN host)
curl -s http://192.168.1.22:11434/api/tags
# Expected: "curl: (7) Failed to connect to 192.168.1.22 port 11434: Connection refused"
```

### Firewall Closure (ADR-E02 Defense-in-Depth)

```bash
# Source: ADR-E02 decision
ufw deny 11434
ufw status | grep 11434
```

### Quick Throughput Benchmark via Ollama Verbose

```bash
# Source: Ollama FAQ (docs.ollama.com/faq) — --verbose flag
# This is the recommended approach for Phase 11 without building llama.cpp
ollama run hf.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF --verbose \
  "You are a security analyst. Summarize the key risks of CVE-2024-12345 and recommend remediation steps. Include any relevant MITRE ATT&CK techniques."

# Look for these lines in output:
# prompt eval count: NNN token(s)
# prompt eval rate: NNN.NN tokens/s      <-- prompt processing speed (pp)
# eval count: NNN token(s)
# eval rate: NNN.NN tokens/s              <-- token generation speed (tg) — THIS IS THE KEY METRIC
```

### RAM Validation Command

```bash
# Source: Success criteria in Phase 11 brief
# Run AFTER Malcolm is loaded and stable AND after at least one ollama run (model loaded)
free -m
# Interpret: "used" column should be < 15500 MB
# Also check:
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}" | head -30
ollama ps  # confirm model is loaded and shows "100% CPU"
```

### Validate Model Unload After Idle

```bash
# After running a query, wait 5+ minutes, then check
sleep 360  # 6 minutes
ollama ps   # Should show empty table (model unloaded)
free -m     # RAM should be back to Malcolm-only baseline (~12.5 GB used)
```

### Validation Script Template (scripts/validate-phase11.sh additions)

```bash
# Source: ADR-E02 verification gate — mandatory checks for Phase 11 completion

# Check 1: Binding — must show 127.0.0.1
if ss -tlnp | grep 11434 | grep -q "127.0.0.1"; then
    echo "PASS: Ollama bound to 127.0.0.1"
else
    echo "FAIL: Ollama not bound to 127.0.0.1 — ADR-E02 VIOLATION"
    exit 1
fi

# Check 2: KEEP_ALIVE configured in systemd
if grep -q "OLLAMA_KEEP_ALIVE" /etc/systemd/system/ollama.service.d/override.conf 2>/dev/null; then
    echo "PASS: OLLAMA_KEEP_ALIVE configured in systemd override"
else
    echo "FAIL: OLLAMA_KEEP_ALIVE not found in systemd override"
    exit 1
fi

# Check 3: Model responds
RESPONSE=$(ollama run hf.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF "What is CVE-2024-12345?" 2>/dev/null | head -c 100)
if [ -n "$RESPONSE" ]; then
    echo "PASS: Model responded"
else
    echo "FAIL: Model did not respond"
    exit 1
fi
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual GGUF download + custom llama.cpp server | `ollama pull hf.co/` prefix for HuggingFace models | Ollama ~0.3.x (2024) | No Modelfile required; chat template extracted from GGUF metadata automatically |
| Shell `export OLLAMA_HOST=` | `systemctl edit ollama.service` or drop-in override | Ollama systemd service pattern | Shell exports don't apply to systemd services — only override.conf works |
| `--keep-alive` in llama-server invocation | `OLLAMA_KEEP_ALIVE` env var in systemd override | Ollama abstraction layer | Ollama manages model lifecycle; individual API requests can also pass `keep_alive` parameter to override the default |
| `OLLAMA_HOST=0.0.0.0` for accessibility | `OLLAMA_HOST=127.0.0.1` + explicit firewall deny | ADR-E02 (April 2026, this project) | Unauthenticated API exposure is OWASP LLM01; localhost binding is the only viable control |

**Deprecated/outdated:**
- `ollama run --host` flag — set `OLLAMA_HOST` in environment instead; flag behavior varies by version
- Permanent model load (`OLLAMA_KEEP_ALIVE=-1`) on 16 GB hardware — incompatible with Malcolm coexistence; reserved for 32 GB upgrade path

---

## Runtime State Inventory

> Phase 11 is an installation phase (new software), not a rename/refactor phase. No runtime state migration is required.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — Ollama not yet installed | None |
| Live service config | None — no prior Ollama systemd unit exists | None |
| OS-registered state | Ollama in `ollama` group from prior partial install (noted in additional context) | Verify with `groups opsadmin`; if ollama group exists, Ollama may already be partially installed — run `ollama --version` to check; if installed, proceed to override configuration |
| Secrets/env vars | None — Ollama requires no API keys for local use | None |
| Build artifacts | None | None |

**Partial install note:** The additional context states "user is in `ollama` group per `groups` output from earlier." This suggests Ollama may already be installed (the installer adds the running user to the `ollama` group). The plan must check for an existing install before re-running the installer. If Ollama is already installed, skip to the systemd override configuration step.

---

## Open Questions

1. **Actual N150 inference throughput**
   - What we know: Single-channel DDR5 ~38 GB/s theoretical; Q4_K_M model requires sustained memory bandwidth; Intel Xe iGPU (24 EU) on N150 may offer Vulkan acceleration
   - What's unclear: Whether Ollama's Vulkan backend is active for N150 on Ubuntu 22.04; actual measured t/s for Foundation-Sec-8B Q4_K_M specifically
   - Recommendation: Measure with `ollama run --verbose` immediately after Phase 11 install; document exact t/s as a Phase 11 output artifact before declaring the phase complete

2. **Malcolm + Ollama simultaneous RAM: actual vs. 15.5 GB budget**
   - What we know: Malcolm Phase 9 actual = ~12.5 GB RSS (higher than 11.7 GB budgeted); Foundation-Sec-8B adds ~5.5 GB
   - What's unclear: Whether ~18 GB total is absorbed by the 6 GB swap without OOM events; whether `OLLAMA_CONTEXT_LENGTH=2048` is needed to fit within 16 GB physical RAM
   - Recommendation: Measure `free -m` during simultaneous load as a Phase 11 validation step; add `OLLAMA_CONTEXT_LENGTH=2048` to the override if physical RAM headroom is < 500 MB

3. **Ollama Vulkan iGPU availability on Ubuntu 22.04 + N150**
   - What we know: Ollama supports Vulkan for iGPU offload experimentally; N150 has Intel Xe 24 EU
   - What's unclear: Whether the Ubuntu 22.04 Vulkan drivers are sufficient for Ollama to use iGPU; whether iGPU offload improves t/s meaningfully given shared memory bandwidth
   - Recommendation: Check `ollama run --verbose` output for GPU layer count; if iGPU offload is active it shows "GPU layers: NN"; this is a bonus, not a requirement — design for CPU-only

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Bash validation script (project convention) |
| Config file | `scripts/validate-phase11.sh` (to be created in Wave 1) |
| Quick run command | `bash scripts/validate-phase11.sh` |
| Full suite command | `bash scripts/validate-phase11.sh` (same — no separate unit test framework for shell config) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| AI-01 | `ollama run` responds to a security question | smoke | `ollama run hf.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF "What is CVE-2024-12345?" \| head -c 50` | ❌ Wave 0 |
| AI-02 | Model unloads after 5m idle (`ollama ps` empty) | smoke/manual | `sleep 360 && ollama ps \| grep -c "NAME"` (expect "1" = header only, no model rows) | ❌ Wave 0 |
| AI-03 | Benchmark output documented (t/s value exists) | manual | `ollama run ... --verbose` + capture eval rate; document in phase summary | ❌ Wave 0 |
| AI-04 | No firewall automation; Ollama bound to 127.0.0.1 | security smoke | `ss -tlnp \| grep 11434 \| grep 127.0.0.1` | ❌ Wave 0 |
| AI-04 | ufw blocks port 11434 from LAN | security smoke | `ufw status \| grep 11434` | ❌ Wave 0 |
| AI-04 | `free -m` with Malcolm + Ollama < 15.5 GB | smoke | `free -m \| awk '/Mem:/{print $3}'` (expect < 15500) | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `bash scripts/validate-phase11.sh` (security binding check at minimum)
- **Per wave merge:** Full validation suite including RAM check and model response
- **Phase gate:** All checks green + throughput benchmark documented before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `scripts/validate-phase11.sh` — covers AI-01, AI-02, AI-03, AI-04 with all checks above
- [ ] No framework installation needed — bash scripts only, consistent with project convention (Phase 9 used same pattern)

---

## Sources

### Primary (HIGH confidence)

- [ADR-E02: Ollama Must Bind to Localhost Only](decisions/ADR-E02-ollama-localhost-binding.md) — binding constraint, ufw rule, verification gate
- [Ollama FAQ](https://docs.ollama.com/faq) — `OLLAMA_KEEP_ALIVE` behavior, `ollama ps`, memory management
- [HuggingFace Ollama Integration](https://huggingface.co/docs/hub/en/ollama) — `hf.co/` pull syntax, default Q4_K_M selection, quantization tag format
- [fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF (HuggingFace)](https://huggingface.co/fdtn-ai/Foundation-Sec-8B-Q4_K_M-GGUF) — official GGUF from model authors, 4.92 GB
- [Phase 9 Summary](.planning/phases/09-malcolm-nsm-deployment/09-01-SUMMARY.md) — actual Malcolm RAM baseline: ~12.5 GB RSS (not the budgeted 11.7 GB)
- [STATE.md](.planning/STATE.md) — Phase 11 gate: if throughput < 2 t/s, Phase 13 design requires revision

### Secondary (MEDIUM confidence)

- [Intel N150 Specifications](https://www.intel.com/content/www/us/en/products/sku/241636/intel-processor-n150-6m-cache-up-to-3-60-ghz/specifications.html) — single memory channel confirmed, DDR5 4800 MT/s support
- [Ollama systemd service override PR #5601](https://github.com/ollama/ollama/pull/5601/files) — drop-in override directory pattern
- [llama.cpp Vulkan performance discussion #10879](https://github.com/ggml-org/llama.cpp/discussions/10879) — Intel Xe ~10.58 t/s basis for N150 estimate (different microarchitecture, treat as order-of-magnitude)
- [GitHub Issue: Add Foundation-sec-8b to Ollama #10585](https://github.com/ollama/ollama/issues/10585) — confirms model not in official Ollama library; community uploads exist but official GGUF is via `hf.co/`

### Tertiary (LOW confidence, flagged for live validation)

- N150 inference throughput: NO public benchmark data for Foundation-Sec-8B Q4_K_M on Intel N150 or comparable Twin Lake hardware. The 3-7 t/s range is an estimate from different hardware. Must measure post-deployment.
- Malcolm + Ollama simultaneous RAM: Phase 9 measured 12.5 GB for Malcolm alone; adding 5.5 GB for model may require `OLLAMA_CONTEXT_LENGTH` tuning to stay under 16 GB physical RAM. Unconfirmed until measured.

---

## Metadata

**Confidence breakdown:**
- Standard stack (Ollama install, systemd override): HIGH — official Ollama docs and ADR-E02 are authoritative
- Architecture (RAM budget, temporal separation): MEDIUM — Phase 9 measured 12.5 GB Malcolm RSS, which is 0.8 GB higher than pre-deployment estimate; simultaneous load budget is tighter than planned
- Pitfalls (security binding, RAM, HF pull naming): HIGH — verified from ADR-E02, Ollama FAQ, and HuggingFace docs
- N150 inference throughput: LOW — no hardware-specific benchmarks; must measure

**Research date:** 2026-04-06
**Valid until:** 2026-05-06 (30 days for Ollama; 7 days if major Ollama version release changes default behaviors)
