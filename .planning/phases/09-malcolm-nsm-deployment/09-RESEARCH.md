# Phase 9: Malcolm NSM Deployment - Research

**Researched:** 2026-04-01
**Domain:** Malcolm NSM Docker Compose deployment with heap tuning, OpenSearch ISM, Arkime disable, on 16GB RAM
**Confidence:** HIGH (deployment mechanics, env vars, ISM policy, pitfalls all sourced from official Malcolm docs and GitHub)

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MAL-01 | Malcolm Docker Compose stack deployed on supportTAK-server with heap-tuned OpenSearch (6GB) and Logstash (1GB) for 16GB RAM constraint | Heap env vars (`OPENSEARCH_JAVA_OPTS`, `LS_JAVA_OPTS`), `bootstrap.memory_lock=false`, `vm.max_map_count=262144`, swap config — all documented below |
| MAL-04 | OpenSearch ISM storage policy configured on first startup (hot→delete, 30-day max age) preventing silent disk exhaustion | ISM policy JSON and OpenSearch Dashboards UI path documented; `OPENSEARCH_INDEX_SIZE_PRUNE_LIMIT` env var documented |
| MAL-05 | Malcolm prebuilt dashboards accessible and displaying live IPFire/Suricata data | Malcolm ships pre-built OpenSearch Dashboards at :5601; nginx reverse proxy at :443 handles TLS; auth configured via `auth_setup` script |
| MAL-06 | Arkime disabled until PCAP mirror hardware is available to prevent idle RAM consumption | `PCAP_ENABLE_NETSNIFF=false`, `PCAP_ENABLE_TCPDUMP=false`, `ZEEK_LIVE_CAPTURE=false`, `SURICATA_LIVE_CAPTURE=false` documented; Arkime container still runs but does zero-capture work |
</phase_requirements>

---

## Summary

Phase 9 deploys Malcolm NSM on supportTAK-server (192.168.1.22) — an Intel N150 with 16GB RAM — which is 8GB below Malcolm's documented 24GB minimum. The deployment is viable only with aggressive heap reduction (OpenSearch at 6GB, Logstash at 1GB), Arkime live capture disabled (no PCAP mirror available), and a 4GB swap safety net. The existing Loki/Alloy/Grafana/Prometheus stack remains running in parallel throughout this phase; decommission is Phase 10.

The three highest-risk elements of this phase are: (1) heap misconfiguration causing silent OOM kills (exit code 137, no error log), (2) OpenSearch filling the 912GB NVMe in under 3 weeks if no ISM policy is set before data accumulates, and (3) `bootstrap.memory_lock=true` (Malcolm's default in Docker) triggering a 1GB forced allocation failure at startup. All three are configuration-time problems with known solutions documented in official Malcolm sources and GitHub issues.

Malcolm provides a `scripts/install.py` interactive wizard that generates environment files. The critical discipline is editing those files for heap values **before** running `./scripts/start` for the first time. A JVM heap set at startup becomes the steady-state value; resizing requires a full container restart.

**Primary recommendation:** Clone Malcolm to `/opt/malcolm`, run `install.py` + `auth_setup`, edit `opensearch.env` and `logstash.env` for 6g/1g heaps, set `bootstrap.memory_lock=false`, configure ISM policy within 30 minutes of first startup, verify via `docker stats` + `free -m` at steady state.

---

## Standard Stack

### Core

| Library / Tool | Version | Purpose | Why Standard |
|----------------|---------|---------|--------------|
| Malcolm NSM | v26.02.0 (Feb 19, 2026) | Full NSM suite — OpenSearch, Zeek, Arkime, Logstash, Filebeat, nginx, Dashboards — via Docker Compose | CISA/Idaho National Laboratory maintained (Apache 2.0). Single `docker-compose.yml` deployment. Replaces entire Loki/Alloy/Grafana stack. Ships OpenSearch 3.5.0 + Zeek 8.0.6. |
| Docker Engine | >= 26.x | Container runtime | Required by Malcolm; already installed on supportTAK-server |
| Docker Compose v2 | v2.x | Stack orchestration | Malcolm ships its own `docker-compose.yml`; use `docker compose` (v2), not `docker-compose` (v1) |
| Python 3.9+ | system | Malcolm install.py and configure scripts | Malcolm's setup scripts require Python with `dotenv`, `requests`, `ruamel.yaml` |

### Supporting

| Tool | Purpose | When to Use |
|------|---------|-------------|
| `sysctl vm.max_map_count=262144` | Required OpenSearch kernel param | Set before first Malcolm start; persist in `/etc/sysctl.d/99-malcolm.conf` |
| zram or disk swap (4GB) | OOM safety net | Configure before Malcolm start; prevents kernel panic on GC spikes |
| `docker stats` | Runtime RAM monitoring | Used during 2-4 week observation period post-deployment |
| `dmesg \| grep -i oom` | Silent OOM kill detection | Check after any unexpected container restart (exit code 137) |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Malcolm full stack | Arkime standalone + separate OpenSearch | Saves ~1-2GB RAM but loses Zeek protocol metadata, prebuilt Malcolm dashboards, and integrated management scripts. Not worth the capability loss. |
| Malcolm full stack | `hedgehog` run profile (capture-only, no OpenSearch) | Only appropriate if a separate OpenSearch server exists. On supportTAK-server, Malcolm's OpenSearch is the target — use full Malcolm profile. |

**Installation:**

```bash
# 0. Prerequisites — verify Docker and Python
docker --version && docker compose version
python3 --version   # must be >= 3.9
pip3 install python-dotenv requests ruamel.yaml

# 1. Clone Malcolm
git clone --depth 1 --branch v26.02.0 https://github.com/cisagov/Malcolm.git /opt/malcolm

# 2. Run auth setup FIRST (required before image pull)
cd /opt/malcolm
python3 scripts/auth_setup

# 3. Run interactive install wizard
python3 scripts/install.py
# Answer: run with malcolm profile, accept all defaults except heap (edit after)

# 4. CRITICAL: Edit heap values BEFORE first start
# In /opt/malcolm/config/opensearch.env:
#   OPENSEARCH_JAVA_OPTS=-Xms6g -Xmx6g
#   OPENSEARCH_BOOTSTRAP_MEMORY_LOCK=false
# In /opt/malcolm/config/logstash.env (or equivalent):
#   LS_JAVA_OPTS=-Xms1g -Xmx1g

# 5. Set kernel parameter (persist across reboots)
sysctl -w vm.max_map_count=262144
echo 'vm.max_map_count=262144' > /etc/sysctl.d/99-malcolm.conf

# 6. Configure 4GB swap safety net
fallocate -l 4G /swapfile && chmod 600 /swapfile
mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw,pri=10 0 0' >> /etc/fstab

# 7. Pull images
docker compose --profile malcolm pull

# 8. Start Malcolm
./scripts/start

# 9. Monitor startup (takes 2-5 min)
./scripts/logs
docker compose ps  # wait for all containers healthy
free -m            # verify RAM not exhausted

# 10. Configure ISM policy WITHIN 30 MINUTES (before data accumulates)
# Access OpenSearch Dashboards at https://192.168.1.22:5601
# Navigate: Menu > Index Management > State Management Policies > Create Policy
```

---

## Architecture Patterns

### Recommended Project Structure

```
/opt/malcolm/              # Malcolm install root (git clone target)
├── config/                # Malcolm environment files (.env)
│   ├── opensearch.env     # OPENSEARCH_JAVA_OPTS, bootstrap.memory_lock
│   ├── logstash.env       # LS_JAVA_OPTS
│   ├── pcap-capture.env   # PCAP_ENABLE_NETSNIFF=false, PCAP_ENABLE_TCPDUMP=false
│   ├── arkime.env         # MANAGE_PCAP_FILES, ARKIME_FREESPACEG
│   └── zeek.env           # ZEEK_LIVE_CAPTURE=false
├── scripts/               # Malcolm control scripts (start, stop, logs, wipe)
└── docker-compose.yml     # Malcolm Docker Compose (do not merge with Loki compose)

/opt/telemetry/            # Existing Loki/Grafana stack (stays until Phase 10)
└── docker-compose.yml

/etc/sysctl.d/99-malcolm.conf  # vm.max_map_count=262144 persistence
/swapfile                       # 4GB swap safety net
```

**Parallel stacks:** Malcolm and Loki run as separate Docker Compose projects in separate directories. They do not share a `docker-compose.yml`. Malcolm's nginx uses port 443; Loki's Grafana uses port 3000. No port conflicts if Loki keeps its existing port assignments.

### Pattern 1: Heap Tuning Before First Start

**What:** Set `OPENSEARCH_JAVA_OPTS=-Xms6g -Xmx6g` and `LS_JAVA_OPTS=-Xms1g -Xmx1g` in Malcolm's environment files before running `./scripts/start`. Equal min/max prevents resize pauses. Never change heap values on a running OpenSearch without a full restart.

**When to use:** Required. Default Malcolm heap is "half of system RAM" = 8GB. On 16GB, 8GB leaves insufficient room for Logstash + other Malcolm containers + OS.

**Example (opensearch.env):**
```bash
# Source: Malcolm official config docs — cisagov.github.io/Malcolm/docs/malcolm-config.html
OPENSEARCH_JAVA_OPTS=-Xms6g -Xmx6g
OPENSEARCH_BOOTSTRAP_MEMORY_LOCK=false
```

**Example (logstash.env):**
```bash
# LS_JAVA_OPTS range: "somewhere between 1500m and 4g" per Malcolm docs
LS_JAVA_OPTS=-Xms1g -Xmx1g
```

### Pattern 2: Disable Live Capture (Log-Forward Mode)

**What:** Set four environment variables to prevent Malcolm from attempting live PCAP capture on interfaces that have no mirrored traffic. Malcolm still runs all containers and accepts EVE JSON/syslog via Logstash. Arkime runs but performs no active capture.

**When to use:** Required for Phase 9. No managed switch SPAN port exists. Enabling capture on a management NIC produces misleading data (N150-only traffic) and wastes CPU.

**Example (pcap-capture.env):**
```bash
# Source: cisagov/Malcolm docs/malcolm-config.md
PCAP_ENABLE_NETSNIFF=false
PCAP_ENABLE_TCPDUMP=false
```

**Example (zeek.env):**
```bash
ZEEK_LIVE_CAPTURE=false
ZEEK_ROTATED_PCAP=false
```

**Example (suricata.env):**
```bash
SURICATA_LIVE_CAPTURE=false
```

### Pattern 3: ISM Policy (30-Day Max Age, Hot→Delete)

**What:** An OpenSearch Index State Management policy that automatically deletes `network-*` indices older than 30 days. Configure this immediately after first startup, before any data accumulates.

**When to use:** Required. Malcolm has no out-of-the-box retention limit. OpenSearch transitions to read-only when disk fills; events are silently dropped with no visible error.

**ISM Policy JSON (apply via OpenSearch Dashboards UI):**
```json
{
  "policy": {
    "description": "Malcolm 30-day index retention",
    "default_state": "hot",
    "states": [
      {
        "name": "hot",
        "actions": [],
        "transitions": [
          {
            "state_name": "delete",
            "conditions": { "min_index_age": "30d" }
          }
        ]
      },
      {
        "name": "delete",
        "actions": [
          { "delete": {} }
        ],
        "transitions": []
      }
    ],
    "ism_template": [
      {
        "index_patterns": ["network-*", "arkime_sessions3-*"],
        "priority": 100
      }
    ]
  }
}
```

**UI Path:** OpenSearch Dashboards (https://192.168.1.22:5601) > Menu > Index Management > State Management Policies > Create Policy > JSON editor > paste above > Create.

**Also set in `opensearch.env`:**
```bash
# Prune indices when total OpenSearch data exceeds 200GB
OPENSEARCH_INDEX_SIZE_PRUNE_LIMIT=200g
```

**Also set in `arkime.env`:**
```bash
# Delete oldest PCAPs when free space falls below 15%
MANAGE_PCAP_FILES=true
ARKIME_FREESPACEG=15%
```

### Anti-Patterns to Avoid

- **Default Malcolm heap on 16GB:** Malcolm's `install.py` suggests "half of RAM" = 8GB heap. On 16GB this leaves no room for Logstash + OS + other containers + future AI stack. Always override to 6GB.
- **`bootstrap.memory_lock=true` in Docker:** Malcolm's OpenSearch default enables memory locking. In Docker, this triggers a 1GB native memory pre-allocation that can fail at container startup on tight budgets. Set `OPENSEARCH_BOOTSTRAP_MEMORY_LOCK=false`.
- **Starting Malcolm without ISM policy:** Any delay in configuring the 30-day retention policy allows unbounded index growth. At home SOHO traffic rates, disk fills in 2-3 weeks with even log-only forwarding accumulating over time.
- **Running `./scripts/start` before editing heap files:** The install wizard does not prompt for heap values explicitly. Accept defaults, then **edit config files** before starting. Heap cannot be hot-changed.
- **Pointing PCAP_IFACE at management NIC:** If `PCAP_ENABLE_NETSNIFF` were accidentally set to true, pointing at `eth0` (management NIC) captures only N150-local traffic — gives misleading false-negative dashboards.
- **Merging Malcolm docker-compose.yml with existing Loki compose:** Malcolm manages its own nginx, auth, and volumes. Keep it as a separate project. Port conflicts between Malcolm's :443 and any existing service must be verified before start.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| OpenSearch index retention | Custom cron to delete old indices | OpenSearch ISM plugin (built into Malcolm's OpenSearch 3.5.0) | ISM handles rollover, age-based deletion, size limits; cron misses edge cases (index not yet rolled, write-blocked state, partial deletes) |
| Container health monitoring | Custom watchdog script | `docker compose ps` + Malcolm's built-in healthchecks | Malcolm defines healthcheck for every container; `docker stats` gives live RAM; exit code 137 detection via `dmesg` is sufficient for Phase 9 observation |
| Malcolm install automation | Custom Ansible/shell installer | Malcolm's own `scripts/install.py` + `scripts/auth_setup` | Malcolm's scripts handle OpenSearch cert generation, nginx config, htpasswd auth, and Docker Compose profile selection; hand-rolled install misses these |
| PCAP disk guard | Custom df-check and rm loop | `MANAGE_PCAP_FILES=true` + `ARKIME_FREESPACEG=15%` | Arkime's built-in free-space guard deletes oldest sessions first; naive cron deletes by timestamp and can remove an active index |

**Key insight:** Malcolm's environment file system (`.env` files in `config/`) is the sole configuration surface. Every operational decision (heap, capture, storage) has a documented env variable. Resist templating or wrapping; edit the env files directly.

---

## Common Pitfalls

### Pitfall 1: Silent OOM Kill (Exit Code 137)

**What goes wrong:** Malcolm containers restart with no error message. OpenSearch appears to stop logging entirely. `docker compose ps` shows a container recently restarted.

**Why it happens:** Linux OOM killer terminates the container process. JVM non-heap memory (metaspace, Lucene mmap buffers, thread stacks) causes total RSS to exceed the container's cgroup limit even when heap is below `-Xmx`. Malcolm's default heap (8GB on 16GB system) leaves zero room for this overhead.

**How to avoid:** Set `OPENSEARCH_JAVA_OPTS=-Xms6g -Xmx6g`. Set container memory limit (in docker-compose.yml) to Xmx + 25%: `mem_limit: 8g` for a 6g heap. Verify with `dmesg | grep -i oom` during the first 24 hours.

**Warning signs:** Container restart count increments in `docker compose ps`; `dmesg` shows `oom_kill_process` targeting `java`; OpenSearch Dashboards shows "cluster health: red" immediately after startup.

### Pitfall 2: OpenSearch Read-Only Write Block (Disk Full)

**What goes wrong:** After the disk reaches the high watermark, OpenSearch silently transitions all indices to read-only. Logstash attempts to index new events, receives a `cluster_block_exception`, and drops them. No alert appears in dashboards; data gaps are invisible until manually investigated.

**Why it happens:** Malcolm has no default retention policy. With log-only forwarding at even modest SOHO rates (thousands of events/day), indices accumulate over weeks.

**How to avoid:** Configure ISM policy within 30 minutes of first startup. Set `OPENSEARCH_INDEX_SIZE_PRUNE_LIMIT=200g`. Monitor `df -h /opt/malcolm` weekly. Set a cron alert at 70% NVMe usage.

**Warning signs:** `df -h` shows NVMe above 80%; OpenSearch Dashboards shows cluster health YELLOW with "disk watermark" warning; Logstash logs show `cluster_block_exception`.

### Pitfall 3: `bootstrap.memory_lock` Container Startup Failure

**What goes wrong:** OpenSearch container fails to start with error "Unable to lock JVM Memory". Malcolm setup defaulted `bootstrap.memory_lock=true`. Docker containers cannot call `mlockall()` on the host without `--privileged` or specific capabilities. This causes a 1GB forced allocation that fails.

**Why it happens:** Malcolm's OpenSearch configuration inherits from standard OpenSearch best practices designed for bare-metal, not Docker.

**How to avoid:** Set `OPENSEARCH_BOOTSTRAP_MEMORY_LOCK=false` in `opensearch.env` before first start. This is a known issue documented in Malcolm Issue #204 and OpenSearch GitHub Issue #5865.

**Warning signs:** OpenSearch container exits immediately with "Unable to lock JVM Memory" or fails healthcheck within first 60 seconds of startup.

### Pitfall 4: Arkime "Unhealthy" Container Without PCAP Source

**What goes wrong:** With `PCAP_ENABLE_NETSNIFF=false` and `PCAP_ENABLE_TCPDUMP=false`, the Arkime container may report "unhealthy" because its capture component is idle. This is expected behavior and does not indicate a functional problem with the rest of Malcolm.

**Why it happens:** Arkime's healthcheck may test for active capture processes. An Arkime container in a no-capture state passes Viewer functionality checks but fails capture-process healthchecks.

**How to avoid:** Accept Arkime container as "degraded/unhealthy" in Phase 9. Document this expected state. The MAL-06 success criterion is "Arkime container present but disabled/not consuming RAM" — not "Arkime healthy". Verify Arkime is not consuming significant RAM with `docker stats`.

**Warning signs:** NOT a warning sign — expected. Only escalate if Arkime is consuming >200MB RAM despite capture being disabled, or if Arkime is crashing and restarting in a loop.

### Pitfall 5: Port Conflict Between Malcolm nginx (:443) and Existing Services

**What goes wrong:** Malcolm's nginx binds to :443 and :5601. If any existing Docker service on supportTAK-server already uses :443, Malcolm fails to start.

**Why it happens:** The existing Loki/Alloy/Grafana stack uses :3000 (Grafana), :3100 (Loki), :9090 (Prometheus). No :443 conflict expected. However, if rsyslog or any other service holds :514 UDP, Malcolm's syslog input will fail silently.

**How to avoid:** Before starting Malcolm, run `ss -tlnp` and `ss -ulnp` to confirm :443, :5601, :5044, :9200, :514 are free. Malcolm takes :443, :5601, :9200, :9300, :5044, :8005, :514.

---

## Code Examples

Verified patterns from official sources:

### Malcolm Steady-State Verification

```bash
# Source: Malcolm running.html docs + standard Docker tooling
# Run on supportTAK-server (192.168.1.22)

# 1. All containers healthy
docker compose -f /opt/malcolm/docker-compose.yml ps

# 2. RAM check — OpenSearch heap must be within 6GB boundary
free -m
# Expect: used < 14000 MB at steady state (leaves 2GB headroom before swap)

# 3. Confirm OpenSearch JVM heap is set correctly
docker exec malcolm-opensearch-1 curl -sk -u admin:PASS \
  http://localhost:9200/_nodes/stats/jvm | python3 -m json.tool | grep heap_max_in_bytes

# 4. OOM kill check
dmesg | grep -i oom | tail -20
# Expect: no output (no OOM kills)

# 5. OpenSearch cluster health
docker exec malcolm-opensearch-1 curl -sk -u admin:PASS \
  http://localhost:9200/_cluster/health?pretty
# Expect: "status": "green" or "yellow" (never "red")
```

### ISM Policy Verification

```bash
# Source: OpenSearch ISM API docs — docs.opensearch.org/latest/im-plugin/ism/
# Verify ISM policy exists and is attached to network indices

docker exec malcolm-opensearch-1 curl -sk -u admin:PASS \
  http://localhost:9200/_plugins/_ism/policies/malcolm-retention | python3 -m json.tool

# Verify policy is applied to indices
docker exec malcolm-opensearch-1 curl -sk -u admin:PASS \
  "http://localhost:9200/_plugins/_ism/explain/network-*?pretty"
```

### Capture Disabled Verification

```bash
# Source: Malcolm config docs — PCAP_ENABLE_NETSNIFF, ZEEK_LIVE_CAPTURE env vars
# Confirm no capture processes consuming CPU

# Verify env vars in Malcolm config
grep -E 'PCAP_ENABLE_|ZEEK_LIVE_CAPTURE|SURICATA_LIVE_CAPTURE' /opt/malcolm/config/*.env

# Confirm no tcpdump/netsniff processes in Malcolm containers
docker exec malcolm-pcap-capture-1 ps aux | grep -E 'tcpdump|netsniff' || echo "No capture processes (expected)"

# Arkime container RAM — should be minimal (<200MB) without live capture
docker stats --no-stream malcolm-arkime-1
```

### OpenSearch Dashboards Access Check

```bash
# Dashboards accessible at https://192.168.1.22:5601
# Also via Malcolm's nginx reverse proxy at https://192.168.1.22:443

curl -sk -o /dev/null -w "%{http_code}" https://192.168.1.22:5601/
# Expect: 302 (redirect to login) or 200
```

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Bash validation scripts (project convention from scripts/validate-phase*.sh) |
| Config file | None — standalone shell scripts |
| Quick run command | `bash /opt/malcolm/scripts/validate-malcolm.sh` (to be created in Wave 0) |
| Full suite command | `bash /opt/malcolm/scripts/validate-malcolm.sh --full` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MAL-01 | All Malcolm Docker Compose containers report healthy status | smoke | `docker compose -f /opt/malcolm/docker-compose.yml ps \| grep -v healthy` | ❌ Wave 0 |
| MAL-01 | `free -m` shows OpenSearch JVM within 6GB heap boundary | smoke | `docker exec malcolm-opensearch-1 curl -sk -u admin:PASS http://localhost:9200/_nodes/stats/jvm` | ❌ Wave 0 |
| MAL-04 | OpenSearch ISM policy active on network-* indices | integration | `curl -sk -u admin:PASS http://localhost:9200/_plugins/_ism/policies/` | ❌ Wave 0 |
| MAL-05 | OpenSearch Dashboards returns HTTP 200/302 at :5601 | smoke | `curl -sk -o /dev/null -w "%{http_code}" https://192.168.1.22:5601/` | ❌ Wave 0 |
| MAL-06 | Arkime capture processes absent; RAM consumption minimal | smoke | `docker stats --no-stream \| grep arkime` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** Quick smoke tests (container health + port check) — run time < 30 seconds
- **Per wave merge:** Full suite including ISM verification and RAM check
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `scripts/validate-malcolm.sh` — covers MAL-01, MAL-04, MAL-05, MAL-06 (does not exist; existing pattern is `scripts/validate-phase*.sh`)
- [ ] Validation must run from supportTAK-server SSH session (not local machine) — all Malcolm endpoints are on 192.168.1.22

*(Existing `scripts/validate-phase5.sh` is the reference pattern for the new script. It covers the same SSH-to-host, curl-to-endpoint, docker-check structure.)*

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Malcolm ISM via environment variables | ISM configured via OpenSearch Dashboards UI or API post-startup | Malcolm v6.2.0 | Must configure ISM manually after first start; cannot pre-configure via env vars |
| Malcolm env variable `OPENSEARCH_INDEX_SIZE_PRUNE_LIMIT` | Still supported as env var for size-based pruning (not age-based) | Current | Age-based 30-day retention requires ISM policy via API/UI; size-based threshold still works via env var |
| `docker-compose` v1 CLI | `docker compose` v2 plugin syntax | Malcolm v26.02.0 requires v2 | Use `docker compose` not `docker-compose` in all scripts |
| Malcolm image build from source | Pre-built images pulled from GitHub Container Registry | Recent Malcolm releases | `docker compose --profile malcolm pull` fetches `ghcr.io/cisagov/malcolm/*:v26.02.0` — no local build needed |

**Deprecated/outdated:**

- Old Malcolm env vars for ISM (`OPENSEARCH_ISM_HOT_WARM_DELETE`, etc.) removed in v6.2.0 — use the ISM API or Dashboards UI instead.
- `docker-compose` v1 syntax — Malcolm v26.02.0 requires Docker Compose v2 (`docker compose` subcommand).

---

## Open Questions

1. **Exact env file names and locations for heap configuration**
   - What we know: Malcolm config docs reference `OPENSEARCH_JAVA_OPTS` and `LS_JAVA_OPTS`; Malcolm ships an `install.py` wizard that generates env files
   - What's unclear: Whether the generated files are `opensearch.env`, `logstash.env`, or a single unified `.env`; the exact file path inside `/opt/malcolm/config/` vs `/opt/malcolm/`
   - Recommendation: After `install.py` runs, inspect `ls /opt/malcolm/config/` to identify the correct env files before editing. The task plan should include a step to locate these files post-install.

2. **Arkime container behavior when capture is disabled**
   - What we know: Setting `PCAP_ENABLE_NETSNIFF=false` and `PCAP_ENABLE_TCPDUMP=false` disables netsniff-ng/tcpdump processes; `ZEEK_LIVE_CAPTURE=false` stops Zeek live capture; Arkime Viewer still runs
   - What's unclear: Whether the Arkime container healthcheck passes or reports "unhealthy" when capture is disabled; whether "unhealthy" Arkime counts as a success for MAL-06
   - Recommendation: MAL-06 success criterion should be "Arkime container present AND RAM < 200MB" not "Arkime container healthy". The task plan should document this explicitly.

3. **Coexistence port verification with existing Loki stack**
   - What we know: Loki/Grafana uses :3000, :3100, :9090; Malcolm uses :443, :5601, :9200, :9300, :5044, :514
   - What's unclear: Whether rsyslog currently holds UDP :514 on supportTAK-server (it does per validate-phase5.sh — rsyslog holds :514 for the Loki pipeline); Malcolm also wants :514 for its Logstash syslog input
   - Recommendation: The task plan must include a step to verify :514 conflict resolution. Options: (a) stop rsyslog before Malcolm starts, (b) configure Malcolm's Logstash syslog input to a non-:514 port (e.g., :5514), (c) leave syslog for Phase 10 when rsyslog is decommissioned. Given the constraint that Loki stays running, option (b) or (c) is safer for Phase 9.

---

## Sources

### Primary (HIGH confidence)

- [Malcolm System Requirements](https://malcolm.fyi/docs/system-requirements.html) — 24GB minimum, 32GB recommended
- [Malcolm Configuration — malcolm-config.md (cisagov/Malcolm GitHub)](https://github.com/cisagov/Malcolm/blob/main/docs/malcolm-config.md) — `OPENSEARCH_JAVA_OPTS`, `LS_JAVA_OPTS`, `PCAP_ENABLE_NETSNIFF`, `PCAP_ENABLE_TCPDUMP`, `ZEEK_LIVE_CAPTURE`, `SURICATA_LIVE_CAPTURE`, `MANAGE_PCAP_FILES`, `ARKIME_FREESPACEG`
- [Malcolm Configuration — malcolm-config.html (official docs)](https://cisagov.github.io/Malcolm/docs/malcolm-config.html) — heap sizing guidance ("somewhere between 1500m and 4g" for Logstash)
- [Malcolm Index Management](https://cisagov.github.io/Malcolm/docs/index-management.html) — ISM policy, `OPENSEARCH_INDEX_SIZE_PRUNE_LIMIT`, v6.2.0 breaking change removing env-var ISM config
- [Malcolm Live Analysis](https://cisagov.github.io/Malcolm/docs/live-analysis.html) — `ZEEK_LIVE_CAPTURE`, `SURICATA_LIVE_CAPTURE`, `ZEEK_ROTATED_PCAP`
- [Malcolm Running](https://cisagov.github.io/Malcolm/docs/running.html) — `./scripts/start`, `./scripts/stop`, Docker Compose profiles
- [Malcolm Quick Start (Ubuntu 24.04)](https://cisagov.github.io/Malcolm/docs/quickstart.html) — `auth_setup`, `install.py`, `docker compose --profile malcolm pull`
- [Malcolm GitHub Issue #204](https://github.com/cisagov/Malcolm/issues/204) — RAM/heap OOM guidance; `bootstrap.memory_lock` Docker failure
- [OpenSearch bootstrap.memory_lock Docker Issue #5865](https://github.com/opensearch-project/OpenSearch/issues/5865) — `bootstrap.memory_lock=true` causes 1GB forced allocation failure in Docker
- [OpenSearch ISM Documentation](https://docs.opensearch.org/latest/im-plugin/ism/index/) — ISM policy structure, hot→delete states, `min_index_age` condition
- [OpenSearch ISM Policies](https://docs.opensearch.org/latest/im-plugin/ism/policies/) — ISM policy JSON schema, `ism_template` for auto-attach to index patterns

### Secondary (MEDIUM confidence)

- [OpenSearch ISM Setup Guide (oneuptime.com, Feb 2026)](https://oneuptime.com/blog/post/2026-02-12-opensearch-index-state-management-ism/view) — practical ISM setup walkthrough
- [OpenSearch Heap Size Best Practices (Opster)](https://opster.com/guides/opensearch/opensearch-basics/opensearch-heap-size-usage-and-jvm-garbage-collection/) — 50% RAM rule, 10GB minimum guidance
- [Malcolm Arkime documentation](https://cisagov.github.io/Malcolm/docs/arkime.html) — Arkime runs on Zeek logs alone when PCAP not available
- [Malcolm GitHub releases — v26.02.0](https://github.com/cisagov/Malcolm/releases) — Feb 19, 2026 release confirmation

### Tertiary (LOW confidence, marked for validation)

- Community reports of Malcolm running on 16GB ("possible but painful") — not reproducible configs; real-world stability at exactly this RAM budget requires the 2-4 week observation period specified in the success criteria.

---

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — Malcolm v26.02.0 and all env variable names sourced from official Malcolm GitHub config docs (current)
- Architecture: HIGH — heap math and RAM budget sourced from official docs + GitHub Issue #204; `bootstrap.memory_lock` Docker failure sourced from OpenSearch Issue #5865
- Pitfalls: HIGH — OOM and disk-fill sourced from official Malcolm docs; `bootstrap.memory_lock` from OpenSearch official issue tracker; Arkime healthcheck behavior MEDIUM (no explicit documentation found for disabled-capture healthcheck state)
- ISM policy: HIGH — JSON schema sourced from official OpenSearch ISM documentation; Malcolm-specific env var (`OPENSEARCH_INDEX_SIZE_PRUNE_LIMIT`) from Malcolm index-management docs

**Research date:** 2026-04-01
**Valid until:** 2026-07-01 (Malcolm is actively maintained; check release notes if using after 90 days)
