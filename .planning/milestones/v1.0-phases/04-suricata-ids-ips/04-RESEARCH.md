# Phase 4: Suricata IDS/IPS - Research

**Researched:** 2026-03-22
**Domain:** Suricata 8.0.3 IDS/IPS on IPFire 2.29 CU200 — N100 hardware, EVE JSON, rule management, memcap tuning
**Confidence:** HIGH (core Suricata mechanics, EVE JSON, zone selection); MEDIUM (exact CU200 EVE default state, memcap values); LOW (suricata.yaml overwrite protection — no official IPFire workaround documented)

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| IDS-01 | Suricata enabled with ET Community ruleset at minimum | WUI enables Suricata; ET Community selected via WUI ruleset page; rule reload triggered from WUI Apply button |
| IDS-02 | IPS zone selection configured (monitor RED + GREEN traffic) | WUI zone checkboxes on IPS page; IPFire lead recommends enabling all zones; no double-processing penalty (deduplicated by IPFire) |
| IDS-03 | Automatic rule updates enabled (daily) | WUI toggle for auto-update; fcron.daily runs at 01:25 AM; ET Community pulls from Emerging Threats servers |
| IDS-04 | Monitor-only mode validated before enabling blocking | WUI has Surveillance/Monitor toggle distinct from Drop mode; test with curl testmynids.org before switching to Drop |
| IDS-05 | Memory cap tuned for N100 single-channel RAM constraints | stream.memcap, flow.memcap, defrag.memcap set in /etc/suricata/suricata.yaml; conservative defaults documented |
| IDS-06 | EVE JSON logging active at /var/log/suricata/eve.json | EVE log enabled: yes in suricata.yaml; path confirmed /var/log/suricata/eve.json; verify within 60s of traffic |
| IDS-07 | Rule categories enabled incrementally to prevent self-lockout | emerging-policy documented as self-lockout risk; incremental one-category-per-day strategy from official IPFire docs |
| IDS-08 | Post-Core-Update validation script checks suricata.yaml integrity | sha256sum-based detection; suricata.yaml at /etc/suricata/suricata.yaml overwritten by Core Updates; no official IPFire workaround exists |
</phase_requirements>

---

## Summary

Suricata 8.0.3 ships natively in IPFire CU200 and is managed almost entirely through the WUI at `Firewall > Intrusion Prevention System`. The WUI controls zone selection (which interfaces to inspect), operating mode (Surveillance/monitor-only vs. Drop/IPS), ruleset provider selection, auto-update schedule, and per-rule enable/disable. The underlying engine configuration lives at `/etc/suricata/suricata.yaml`, which IPFire generates from a template. EVE JSON output is present in the IPFire-managed `suricata.yaml` and should be enabled by default in CU200 (confirmed from IPFire's config diff showing `enabled: yes`); however, this requires on-system verification since older community threads reported it as disabled.

The primary operational risk for Phase 4 is the `suricata.yaml` overwrite pattern. Core Updates regenerate `/etc/suricata/suricata.yaml` from IPFire's internal template, wiping any manual customizations — this was confirmed by a CU194 community report. Since IPFire does not provide an official drop-in override mechanism for this file, the mitigation strategy for IDS-08 is: (1) store a known-good sha256 hash of the deployed suricata.yaml, (2) run a post-update validation script that compares the current hash and alerts on mismatch, and (3) keep the custom EVE JSON configuration changes minimal and documented so they can be re-applied quickly.

The second major risk is rule-induced self-lockout. The `emerging-policy.rules` category explicitly blocks Linux package managers and can disconnect SSH management sessions. The safe deployment pattern is: enable ET Community rules with only the default-enabled subset first, monitor for 24-48 hours in Surveillance mode before switching to Drop mode, then add one category per day.

**Primary recommendation:** Enable Suricata on RED + GREEN zones in Surveillance (monitor-only) mode with ET Community rules (default-enabled subset only). Verify EVE JSON output at `/var/log/suricata/eve.json` using `curl http://testmynids.org/uid/index.html` before transitioning to Drop mode. Set conservative memcap values and store sha256 hash of suricata.yaml for post-update integrity checking.

---

## Standard Stack

### Core (All Native — No Installation Required)

| Component | Version | Purpose | Notes |
|-----------|---------|---------|-------|
| Suricata | 8.0.3 | IDS/IPS engine | Bundled in IPFire since CU131; CU200 ships 8.0.3; managed via WUI |
| IPFire WUI IPS page | CU200 | Zone selection, mode, rulesets, updates | Primary configuration interface; generates suricata.yaml template |
| ET Community rules | Current | Primary free ruleset | No registration; daily updates; broad coverage |
| `/etc/suricata/suricata.yaml` | IPFire-managed | Suricata engine configuration | Template-generated; EVE JSON config lives here |
| `/var/ipfire/suricata/` | IPFire-managed | Sub-configs and rule settings | `oinkmaster.conf`, `suricata-homenet.yaml`, rule enable/disable files |
| `/var/lib/suricata/` | Runtime | Rule files and whitelist | `*.rules` files loaded at runtime; `local.rules` for custom rules |
| `/var/log/suricata/eve.json` | Runtime | EVE JSON alert output | Primary data source for Phase 5 telemetry pipeline |
| `/var/log/suricata/fast.log` | Runtime | Simple one-line alerts | Use for initial verification testing |

### Supporting (Managed via WUI)

| Component | Purpose | Notes |
|-----------|---------|-------|
| IPFire DBL | Domain blocklist as Suricata ruleset | Beta in CU200; DNS/TLS/HTTP/QUIC deep inspection; do NOT enable until stable promotion |
| ThreatFox (abuse.ch) | IOC-based detection | Enable after initial ET Community tuning; higher false positive rate |
| oinkmaster | Rule update mechanism | Called by fcron.daily at 01:25 AM; managed internally by IPFire |
| `/var/lib/suricata/local.rules` | Custom test rules | For writing local test signatures; use SIDs 1000000-1999999 |

### Do NOT Install

| Package | Reason |
|---------|--------|
| Snort | Not available in Pakfire for IPFire 2.x; replaced by Suricata since CU131 |
| Zeek | Not in Pakfire; requires manual compilation against IPFire buildroot; unsupported |
| suricata-update (standalone) | IPFire uses oinkmaster internally; suricata-update is for non-IPFire deployments |
| OISF Traffic ID ruleset | Unmaintained since 2018; do not enable |
| ET Pro ($600/yr) | Overkill for SOHO; ET Community is the correct choice |

---

## Architecture Patterns

### WUI Configuration Flow

```
IPFire WUI: Firewall > Intrusion Prevention System
    ├── Enable IPS checkbox
    ├── Zone selection checkboxes (RED, GREEN, BLUE, ORANGE)
    ├── Mode toggle: Surveillance (monitor) | Drop (IPS)
    ├── Ruleset providers (checkboxes per provider)
    │   ├── ET Community (enabled)
    │   └── ... other providers
    ├── Per-provider: Automatic Update toggle
    └── Apply button → triggers oinkmaster rule reload + Suricata restart
```

### Configuration File Hierarchy

```
/etc/suricata/suricata.yaml          ← Primary config (IPFire template-managed)
    includes:
        /var/ipfire/suricata/suricata-homenet.yaml
        /var/ipfire/suricata/suricata-dns-servers.yaml
        /var/ipfire/suricata/suricata-http-ports.yaml
        /var/ipfire/suricata/suricata-used-rulefiles.yaml   ← "Autogenerated, changes overwritten"

/var/lib/suricata/local.rules        ← Custom rules (NOT overwritten by Core Updates)
/var/lib/suricata/*.rules            ← Downloaded ruleset files (regenerated on update)

/var/log/suricata/eve.json           ← EVE JSON output (continuous write)
/var/log/suricata/suricata.log       ← Engine start/stop/errors only
/var/log/suricata/fast.log           ← Simple one-line alert log
```

### Packet Processing Position

```
Inbound packet (red0)
    → nfqueue (kernel)
    → Suricata IPS (userspace, inline inspection)
        ↓ PASS (alert logged) or DROP (packet discarded)
    → iptables PREROUTING
    → iptables FORWARD (zone policies)
    → green0 / destination zone
```

Suricata sits BEFORE iptables zone policies. A packet dropped by Suricata never reaches the firewall rules. This means emerging-policy rules that block traffic operate independently of firewall ACCEPT rules.

### Pattern 1: Monitor-First Deployment

**What:** Enable IPS in Surveillance mode on RED + GREEN. Run for 24-48 hours minimum. Review IPS Log Viewer for false positives. Tune (whitelist or disable offending rules) before switching to Drop mode.

**When to use:** Always — never deploy Drop mode on day one.

**Steps:**
```
1. WUI: Enable IPS, select RED + GREEN zones
2. WUI: Mode = Surveillance (monitor-only)
3. WUI: Enable ET Community rules (default-enabled subset only)
4. WUI: Apply — verify Suricata restarts cleanly
5. SSH: tail -f /var/log/suricata/eve.json | jq '.event_type'
6. SSH: curl http://testmynids.org/uid/index.html  (from IPFire itself)
7. WUI: Check IPS Log Viewer for SID 2100498 alert
8. Wait 24-48 hours, review false positive rate
9. WUI: Switch to Drop mode only after baselining
```

### Pattern 2: Incremental Rule Category Expansion

**What:** Enable one rule category per day. Check IPS Log Viewer after each addition before enabling the next.

**Safe starting categories (ET Community):**
1. `emerging-malware.rules` — C2 and malware communication (HIGH value, LOW false positive rate)
2. `emerging-exploit.rules` — Known exploit patterns (HIGH value)
3. `emerging-scan.rules` — Port/host scanning (HIGH value for perimeter)
4. `emerging-dns.rules` — DNS-based threats

**Add after initial tuning:**
5. `emerging-botnet.rules`
6. `emerging-trojan.rules`

**Never enable without extensive prior tuning:**
- `emerging-policy.rules` — Blocks Linux package managers, can disconnect SSH sessions
- `ciarmy.rules` / `dshield.rules` — IP blocklists that generate false positives from routine internet scanning

### Pattern 3: EVE JSON Integrity Baseline

**What:** Before any Core Update, capture sha256 of deployed suricata.yaml. Post-update, compare and alert on mismatch.

```bash
# Baseline (run before Core Updates):
sha256sum /etc/suricata/suricata.yaml > /root/suricata-yaml.sha256

# Post-update check script (IDS-08):
#!/bin/bash
YAML="/etc/suricata/suricata.yaml"
BASELINE="/root/suricata-yaml.sha256"

if [ ! -f "$BASELINE" ]; then
    echo "FAIL: No baseline found at $BASELINE"
    exit 1
fi

sha256sum -c "$BASELINE" --quiet
if [ $? -ne 0 ]; then
    echo "WARN: suricata.yaml has changed since baseline."
    echo "Expected EVE JSON config may have been lost."
    echo "Review /etc/suricata/suricata.yaml and restore if needed."
    echo "Re-run: sha256sum $YAML > $BASELINE after restoring"
    exit 2
fi
echo "OK: suricata.yaml matches baseline"
```

### Anti-Patterns to Avoid

- **Enable all ET rules at once in Drop mode:** Guaranteed false positives; `emerging-policy.rules` will block package managers and potentially SSH sessions.
- **Use UDP syslog for EVE alerts:** EVE JSON never enters syslog on IPFire; only engine start/stop meta events go to syslog. All alert data is only in `/var/log/suricata/eve.json`.
- **Edit `/var/ipfire/suricata/suricata-used-rulefiles.yaml` directly:** The file header explicitly states "Autogenerated file. Any custom changes will be overwritten!" Use WUI for rule file selection.
- **Manually edit `/etc/suricata/suricata.yaml` without tracking the hash:** Core Updates will overwrite it. If manual edits are made (e.g., memcap tuning), document them in git AND create/update the sha256 baseline after each edit.
- **Enable IPFire DBL before beta-to-stable promotion:** DBL is beta as of CU200; premature activation may generate false positives against legitimate traffic.
- **Inspect all 6 interfaces:** Only select zones with actual traffic (RED for WAN, GREEN for LAN). BLUE and ORANGE only if those zones are actively used.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Rule downloading and update | Custom wget/curl script | IPFire WUI auto-update (oinkmaster via fcron.daily) | IPFire already has oinkmaster-based update; custom script would conflict with WUI rule tracking |
| Inline IPS nfqueue setup | Manual iptables -j NFQUEUE rules | IPFire WUI IPS enable | IPFire manages nfqueue chains; duplicating them corrupts the chain |
| Rule enable/disable per category | Editing rule files directly | WUI IPS Customize Ruleset page | IPFire tracks enabled SIDs in `/var/ipfire/suricata/oinkmaster-enabled-sids.conf`; direct edits are overwritten |
| Whitelist management | Editing suricata.yaml directly | WUI Whitelist section | IPFire renders the whitelist into Suricata-native pass rules |
| EVE JSON parsing | Custom parser | jq (available or installable) | Standard UNIX tool; Suricata EVE format is well-specified JSON |

**Key insight:** IPFire wraps Suricata tightly. Nearly every operational action goes through the WUI, which translates to internal config files. Bypassing the WUI means owning all the glue code IPFire provides for free — and having it overwritten on the next Core Update.

---

## Memcap Tuning for N100 16GB DDR5 Single-Channel

### Context

The N100 has 16GB single-channel DDR5. Single-channel DDR5 provides ~50 GB/s bandwidth (vs ~100 GB/s dual-channel). The memory bandwidth bottleneck is the primary constraint for Suricata on this hardware, not raw capacity. The N100's 4 efficiency cores are also the limiting factor for CPU-intensive rule categories (TLS/HTTP deep inspection).

### Conservative Starting Values (Recommended for Phase 4)

These values are conservative relative to available RAM, giving Suricata reasonable headroom without pushing single-channel memory bandwidth.

```yaml
# In /etc/suricata/suricata.yaml (manual edit required; add to sha256 baseline after)

defrag:
  memcap: 64mb              # Default: 32mb — doubled for SOHO; fragmentation uncommon
  hash-size: 65536
  trackers: 65535
  max-frags: 65535

flow:
  memcap: 128mb             # Default: ~32mb — 4x for SOHO traffic volume
  hash-size: 65536
  prealloc: 30000           # Default: 10000 — 3x for burst connections

stream:
  memcap: 256mb             # Default: 64mb — 4x; tracks TCP state
  checksum-validation: yes
  reassembly:
    memcap: 512mb           # Default: 256mb — 2x; keep modest on single-channel
    depth: 1mb              # Per-connection reassembly limit
```

**Total Suricata footprint estimate (home SOHO, these settings):**
- Base overhead: ~200MB (rules compiled, engine running)
- memcap allocation: ~960MB maximum (if all pools fill)
- Practical steady-state: 400-600MB total
- 16GB total: leaves 14.4GB+ for kernel, IPFire services, and headroom

### Verification After 30 Minutes

```bash
# Check actual Suricata memory usage:
cat /proc/$(pgrep -o suricata)/status | grep VmRSS

# Check Suricata stats for memcap events:
tail -100 /var/log/suricata/eve.json | jq 'select(.event_type=="stats") | .stats.flow.memuse'

# Check if flow engine hit emergency mode:
grep -i "emergency" /var/log/suricata/suricata.log
```

If memcap events appear in stats, increase the relevant memcap. If RSS exceeds 2GB steadily, reduce memcaps or disable heavy rule categories.

### Important Note on Suricata 8 Exception Policies

Suricata 8 introduced exception policies — when a memcap is hit, the engine decides what to do with the packet (pass, drop, bypass, ignore). The IPFire default is `ignore` for defrag and `bypass` for flow. In Drop (IPS) mode, this means a memcap hit causes packets to bypass Suricata rather than being dropped — which is appropriate for a SOHO device (avoiding DoS on yourself).

---

## Common Pitfalls

### Pitfall 1: Core Update Overwrites suricata.yaml

**What goes wrong:** A Core Update regenerates `/etc/suricata/suricata.yaml` from IPFire's internal template, resetting EVE JSON configuration, memcap values, and any other manual customizations. The engine restarts with default settings — EVE JSON output may be disabled, and memcap values revert to defaults.

**Why it happens:** IPFire owns `/etc/suricata/suricata.yaml` as a package-managed file. Core Updates regenerate it from `suricata.yaml.in` with substituted variables. There is no official IPFire-supported drop-in override mechanism for this file.

**How to avoid:**
1. After deploying Phase 4 configuration, run `sha256sum /etc/suricata/suricata.yaml > /root/suricata-yaml.sha256`
2. Commit the sha256 and a copy of the deployed suricata.yaml to git
3. Include `/root/suricata-yaml.sha256` and the deployed suricata.yaml backup in `/var/ipfire/backup/include.user`
4. Run post-update check script (IDS-08) after every Core Update
5. If mismatch detected: re-apply memcap values, verify EVE JSON enabled, update baseline

**Warning signs:** EVE JSON stops receiving entries; `/var/log/suricata/eve.json` goes stale; `grep "eve-log" /etc/suricata/suricata.yaml` shows `enabled: no`.

### Pitfall 2: emerging-policy Self-Lockout

**What goes wrong:** Enabling `emerging-policy.rules` in Drop mode blocks legitimate Linux package management traffic (APT, YUM patterns). This includes IPFire's own Pakfire update checks. In some cases it blocks HTTP patterns used by management tools, potentially disrupting WUI access.

**Why it happens:** `emerging-policy.rules` is designed for corporate environments with restrictive internet policies. Home/SOHO traffic patterns are indistinguishable from "policy violations" by these rules. Example: `ET POLICY PE EXE or DLL Windows file download HTTP` fires on any Windows update.

**How to avoid:**
- Never enable `emerging-policy.rules` until all other categories have been tuned
- If enabled, do so in Surveillance mode first for at least one week
- Add your management host IP (192.168.1.100) and GREEN subnet (192.168.1.0/24) to the WUI whitelist before enabling any aggressive rule categories

**Warning signs:** Network connectivity drops after IPS mode switch; `grep emerging-policy /var/log/suricata/fast.log | wc -l` shows unusually high hit count.

### Pitfall 3: EVE JSON Not Enabled or Not Receiving Entries

**What goes wrong:** `/var/log/suricata/eve.json` either doesn't exist or receives no entries after traffic passes. Phase 5 telemetry pipeline has nothing to ingest.

**Why it happens:** Older IPFire versions had `enabled: no` as the EVE log default. CU200 appears to enable it by default, but this must be verified on the live system. Additionally, if no zones are selected or no rules are enabled, Suricata will not generate alerts.

**How to avoid:**
- After enabling IPS via WUI, immediately verify: `ls -la /var/log/suricata/eve.json`
- Run test: `curl http://testmynids.org/uid/index.html` from IPFire SSH
- Within 60 seconds, check: `tail -5 /var/log/suricata/eve.json | jq '.event_type'`
- Should see `"alert"` events; also `"dns"`, `"flow"` events during normal traffic
- If no file or empty file: manually verify `grep -A3 "eve-log:" /etc/suricata/suricata.yaml`

**Warning signs:** File is absent; file exists but is not updated (check mtime); file has only `{"event_type":"stats"}` entries but no `"alert"` entries despite test traffic.

### Pitfall 4: Suricata Logs Only Meta-Information to Syslog

**What goes wrong:** Expecting Suricata alerts to appear in `/var/log/messages` or via UDP syslog forwarding to the telemetry host.

**Why it happens:** IPFire's Suricata only writes engine start/stop events to syslog. EVE alert events are never in syslog on IPFire — this is a confirmed IPFire-specific behavior, not upstream Suricata default.

**How to avoid:** Never configure Phase 5 telemetry to rely on syslog for Suricata alert data. The EVE JSON file at `/var/log/suricata/eve.json` is the only source. Phase 5 must use file-read path (NFS or rsync), not syslog, for IDS alerts.

### Pitfall 5: flowbit Warnings Are Not Errors

**What goes wrong:** After enabling ET Community rules, `/var/log/suricata/suricata.log` fills with `"flowbit 'XXX' is checked but not set"` warnings. User incorrectly diagnoses Suricata as broken.

**Why it happens:** ET Community rulesets ship with some rules commented out (selectively enabled). Rules that check flowbits set by disabled rules will produce these warnings. This is expected and normal — Suricata still loads and runs correctly.

**How to avoid:** Confirm with: `grep "rules loaded" /var/log/suricata/suricata.log` — if rule count is > 10,000 and `"0 rules failed"` appears, Suricata is working. Verify via `curl http://testmynids.org/uid/index.html` test.

### Pitfall 6: Checksum Validation False Positives from i226-V

**What goes wrong:** Suricata logs `SURICATA ICMPv4 invalid checksum` alerts flooding the IPS log. This is caused by hardware checksum offloading on the Intel i226-V NIC.

**Why it happens:** The i226-V performs TCP/IP checksum calculations in hardware. When Suricata inspects packets before the NIC finalizes the checksum, it sees unfinished checksum values as invalid.

**How to avoid:** In suricata.yaml, set:
```yaml
stream:
  checksum-validation: no
```
Or disable NIC checksum offloading (not recommended on i226-V — may reduce throughput).

---

## Code Examples

### Test Signature Verification (SID 2100498)

```bash
# Source: IPFire community thread (community.ipfire.org/t/suricata-problems/15532)
# Run from IPFire SSH session or from a GREEN zone host

# From IPFire host itself:
curl http://testmynids.org/uid/index.html

# Expected response content triggers GPL ATTACK_RESPONSE rule:
# "uid=0(root) gid=0(root) groups=0(root)"

# Verify alert appeared:
tail -5 /var/log/suricata/fast.log
# Expected: [1:2100498:7] GPL ATTACK_RESPONSE id check returned root

# Verify in EVE JSON:
tail -20 /var/log/suricata/eve.json | jq 'select(.event_type=="alert") | {sig: .alert.signature, sid: .alert.signature_id}'
```

### Custom Local Test Rule

```bash
# Source: Suricata documentation / IPFire community guidance
# Write to /var/lib/suricata/local.rules (NOT overwritten by Core Updates)

# Add test rule:
echo 'alert http any any -> any any (msg:"LOCAL TEST RULE HTTP"; http.user_agent; content:"curl"; nocase; sid:1000001; rev:1;)' >> /var/lib/suricata/local.rules

# Reload Suricata rules (via WUI Apply or):
/usr/lib/suricata/suricatasc -c reload-rules

# Verify rule loaded:
grep "1000001" /var/log/suricata/suricata.log

# Trigger from IPFire host:
curl -A "curl-test" http://detectportal.firefox.com/

# Verify alert:
tail -5 /var/log/suricata/fast.log | grep "LOCAL TEST"
```

### EVE JSON Status Check

```bash
# Source: Suricata EVE JSON documentation
# Verify EVE JSON is receiving events

# Check file exists and is recent (should update within seconds of any network traffic):
ls -la /var/log/suricata/eve.json
stat /var/log/suricata/eve.json

# Show last 5 event types:
tail -10 /var/log/suricata/eve.json | jq '.event_type'
# Expected output includes: "dns", "flow", "alert" (if rules are enabled)

# Count alerts in last hour:
awk -v d="$(date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M')" '$0 >= d' /var/log/suricata/eve.json | \
  jq 'select(.event_type=="alert") | .alert.signature' | wc -l
```

### EVE JSON Configuration Block (suricata.yaml)

```yaml
# Source: IPFire config diff (nopaste.ipfire.org/view/mKfhrhSu) + Suricata docs
# Verify this block is present and enabled in /etc/suricata/suricata.yaml

outputs:
  - eve-log:
      enabled: yes
      filetype: regular
      filename: eve.json
      types:
        - alert:
            payload: yes
            payload-buffer-size: 4kb
            payload-printable: yes
            packet: yes
            metadata: yes
        - http:
            extended: yes
        - dns:
            version: 3        # Suricata 8 default
        - tls:
            extended: yes
        - flow
```

### Rule Update Verification

```bash
# Source: IPFire community thread on auto-update timing
# Update runs daily at 01:25 AM via fcron.daily

# Check last update timestamp (oinkmaster log):
ls -la /var/log/suricata/

# Manual trigger (if needed — use carefully, restarts Suricata):
# The WUI Apply button triggers the same update process

# Verify current rule count after update:
grep "rules loaded" /var/log/suricata/suricata.log | tail -3
```

### Post-Core-Update Integrity Check Script (IDS-08)

```bash
#!/bin/bash
# Source: Project-specific, based on sha256sum standard tooling
# Path: /usr/local/bin/check-suricata-integrity.sh
# Run after every Core Update

YAML="/etc/suricata/suricata.yaml"
BASELINE="/root/suricata-yaml.sha256"
EVE_ENABLED_PATTERN="eve-log"
EVE_ENABLED_VALUE="enabled: yes"

echo "=== Suricata Config Integrity Check ==="

# Check 1: File exists
if [ ! -f "$YAML" ]; then
    echo "FAIL: $YAML does not exist"
    exit 1
fi

# Check 2: sha256 baseline comparison
if [ -f "$BASELINE" ]; then
    if sha256sum -c "$BASELINE" --quiet 2>/dev/null; then
        echo "PASS: suricata.yaml matches baseline hash"
    else
        echo "WARN: suricata.yaml has changed since baseline"
        echo "      Core Update may have overwritten custom configuration"
        echo "      Review EVE JSON settings and memcap values"
        echo "      If config looks correct, update baseline:"
        echo "        sha256sum $YAML > $BASELINE"
    fi
else
    echo "INFO: No baseline found. Creating baseline now."
    sha256sum "$YAML" > "$BASELINE"
    echo "      Baseline stored at: $BASELINE"
fi

# Check 3: EVE JSON enabled
if grep -q "eve-log:" "$YAML"; then
    if grep -A2 "eve-log:" "$YAML" | grep -q "enabled: yes"; then
        echo "PASS: EVE JSON output is enabled"
    else
        echo "WARN: EVE JSON output may be disabled in $YAML"
        echo "      Check: grep -A5 'eve-log:' $YAML"
    fi
else
    echo "WARN: No eve-log section found in $YAML"
fi

echo "=== Check complete ==="
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|-----------------|--------------|--------|
| Snort as IPFire IPS | Suricata (nfqueue inline) | CU131 (2019) | Better multi-thread, protocol support |
| Suricata 6.x | Suricata 8.0.3 | CU198 (2024) | Cached rule compilation, faster startup, Suricata 8 exception policies |
| IPS alert emails not available | IPS email alerts + PDF reports | CU198 (2024) | Native alerting, no 3rd-party SIEM required for basic notifications |
| Promtail for log shipping | Grafana Alloy 1.14.1 | EOL Feb 28, 2026 | Alloy is mandatory replacement; has loki.source.file for eve.json |
| EVE JSON disabled by default (old CU) | EVE JSON enabled by default (CU200) | ~CU190+ (unconfirmed, requires on-system verify) | Phase 5 pipeline works without manual yaml edit if confirmed |
| OISF Traffic ID ruleset | Abandoned (last update 2018) | 2018 | Do not enable; use ET Community instead |

**Deprecated/outdated:**
- Promtail: EOL February 28, 2026. Phase 5 must use Grafana Alloy.
- OISF Traffic ID: Last updated 2018. Dead project. Not in WUI as of recent CUs.
- Suricata-update (standalone): Not used by IPFire. IPFire uses oinkmaster.

---

## Open Questions

1. **EVE JSON default state in CU200**
   - What we know: CU200 config diff shows `enabled: yes` in the template. Older forum posts (CU176-178) showed `enabled: no`.
   - What's unclear: Whether the current CU200 `suricata.yaml.in` template has EVE enabled by default without any manual intervention.
   - Recommendation: First task in Phase 4 Wave 1 should be: SSH to IPFire, check `grep -A3 "eve-log:" /etc/suricata/suricata.yaml`. If `enabled: no`, document and update to `yes`, add to baseline. This is a Day 1 verification step.

2. **WUI EVE JSON toggle vs manual yaml edit**
   - What we know: Older community posts and forum.ipfire.org (2019) stated WUI has no EVE JSON toggle. CU198 added email reporting which may have added WUI controls for EVE output.
   - What's unclear: Whether CU200 WUI exposes an EVE JSON enable toggle.
   - Recommendation: Check IPS page WUI on live system. If toggle exists, use WUI (avoids direct yaml edit). If no toggle, edit yaml and track with sha256 baseline.

3. **Specific memcap values for N100 single-channel DDR5 workloads**
   - What we know: Defaults (stream 64MB, reassembly 256MB, flow 32MB, defrag 32MB) are conservative. 16GB RAM gives headroom. Single-channel bottleneck is memory bandwidth, not capacity.
   - What's unclear: Empirical steady-state memory usage under actual SOHO traffic on this specific hardware. No community benchmarks found for N100 + IPFire + ET Community.
   - Recommendation: Deploy with the conservative values documented above. After 30 minutes of normal traffic, check `cat /proc/$(pgrep -o suricata)/status | grep VmRSS`. If well under 1GB, consider whether increases are even necessary. Increase only if stats.log shows memcap events.

4. **suricata.yaml drop-in override mechanism**
   - What we know: No official IPFire-supported drop-in mechanism exists. The file is owned by the Suricata package. `/var/ipfire/suricata/` sub-configs are also regenerated by WUI.
   - What's unclear: Whether CU200 introduced any formal include mechanism for user-customizable sections (no community evidence found).
   - Recommendation: Treat direct yaml edits as the only mechanism. Mitigate overwrite risk via sha256 baseline + post-update check script (IDS-08). Do not attempt to replace the file with a symlink to a git-controlled copy — IPFire's init scripts write to it directly.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | bash shell scripts (SysVinit environment; no test framework available) |
| Config file | none — standalone scripts in `/scripts/` |
| Quick run command | `bash /scripts/validate-phase4.sh` |
| Full suite command | `bash /scripts/validate-phase4.sh --full` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | Notes |
|--------|----------|-----------|-------------------|-------|
| IDS-01 | ET Community rules loaded, rule count > 1000 | smoke | `grep "rules loaded" /var/log/suricata/suricata.log \| tail -1 \| awk '{print $NF}'` | FAIL if < 1000 |
| IDS-02 | Suricata active on RED and GREEN zones | smoke | `grep -E "red0\|green0" /var/log/suricata/suricata.log \| grep -i "running"` | WUI-configured; verify from log |
| IDS-03 | Auto-update enabled; last update recent | smoke | `ls -la /var/lib/suricata/*.rules \| head -1` — check mtime | SKIP if < 24h since install |
| IDS-04 | Monitor mode active (not Drop mode) | manual | WUI verification — check mode toggle on IPS page | Cannot automate from CLI reliably |
| IDS-05 | Suricata RSS within acceptable range | smoke | `cat /proc/$(pgrep -o suricata)/status \| grep VmRSS` | WARN if > 2GB after 30min |
| IDS-06 | EVE JSON receiving entries within 60s | smoke | `curl http://testmynids.org/uid/index.html; sleep 5; tail -5 /var/log/suricata/eve.json \| jq '.event_type'` | FAIL if no alert entry |
| IDS-07 | No emerging-policy rules enabled (safe baseline) | smoke | `grep "emerging-policy" /var/ipfire/suricata/suricata-used-rulefiles.yaml` | PASS if not listed |
| IDS-08 | Post-update script detects sha256 change | integration | `bash /usr/local/bin/check-suricata-integrity.sh` | FAIL if no baseline; WARN on hash mismatch |

### Sampling Rate

- **Per task commit:** Run quick smoke: `bash /scripts/validate-phase4.sh`
- **Per wave merge:** Full suite including EVE JSON entry test and integrity check
- **Phase gate:** Full suite green before moving to Phase 5

### Wave 0 Gaps (Test Infrastructure Needed)

- [ ] `/scripts/validate-phase4.sh` — covers IDS-01 through IDS-08 automated checks
- [ ] `/usr/local/bin/check-suricata-integrity.sh` — covers IDS-08 specifically

---

## Sources

### Primary (HIGH confidence)

- [IPFire IPS Documentation](https://www.ipfire.org/docs/configuration/firewall/ips) — Zone selection, monitor vs drop mode, WUI controls
- [IPFire IPS Rulesets Documentation](https://www.ipfire.org/docs/configuration/firewall/ips/rulesets) — Ruleset recommendations, ThreatFox advisory, ET Community as baseline
- [IPFire IPS Rule Selection](https://www.ipfire.org/docs/configuration/firewall/ips/rule-selection) — emerging-policy self-lockout warning; incremental enable approach; one-category-per-day strategy
- [IPFire 2.29 CU200 Release Notes](https://www.ipfire.org/blog/ipfire-2-29-core-update-200-released) — Suricata 8.0.3, signature cache cleanup, DNS/HTTP/TLS/QUIC alert metadata enhancement, DBL beta
- [IPFire 2.29 CU198 Release Notes (via Linuxiac)](https://linuxiac.com/ipfire-2-29-released-with-suricata-8-and-real-time-ips-email-reporting/) — IPS email alerts, PDF reports, syslog forwarding feature, Suricata 8.0.1 upgrade
- [Suricata EVE JSON Output Documentation](https://docs.suricata.io/en/latest/output/eve/eve-json-output.html) — EVE JSON format, configuration, file path, event types
- [Suricata suricata.yaml Configuration Reference](https://docs.suricata.io/en/latest/configuration/suricata-yaml.html) — Memcap defaults, stream/flow/defrag configuration, exception policies

### Secondary (MEDIUM confidence)

- [IPFire Community: Should I enable IPS on RED and GREEN?](https://community.ipfire.org/t/should-i-enable-the-intrusion-prevention-system-on-both-red-and-green-zones/15548) — Michael Tremer (lead dev) recommendation to enable all zones; no double-processing confirmed
- [IPFire Community: IPS Ruleset Update Timing](https://community.ipfire.org/t/ips-ruleset-automatic-update-how-to-set-time/7082) — fcron.daily at 01:25 AM; curl testmynids.org test method confirmed
- [IPFire Community: Suricata Problems CU199-200](https://community.ipfire.org/t/suricata-problems/15532) — flowbit warnings are not errors; curl testmynids.org for verification; 20,742 rules with ET Community confirmed
- [IPFire Nopaste CU suricata.yaml diff](https://nopaste.ipfire.org/view/mKfhrhSu) — EVE JSON `enabled: yes` in IPFire's managed template; config file structure
- [IPFire Community: IPS suricata does not log into syslog](https://community.ipfire.org/t/ips-suricata-does-not-log-into-syslog/9302) — Confirmed: EVE alerts never in syslog on IPFire; file-read is mandatory for Phase 5
- [IPFire Backup Documentation](https://www.ipfire.org/docs/configuration/system/backup) — `/var/ipfire/backup/include.user` mechanism for custom file backup

### Tertiary (LOW confidence — require live system verification)

- [IPFire Community: CU194 overwrote suricata.yaml](https://community.ipfire.org/t/ipfire-2-29-core-update-194-overwrote-suricata-yaml/14133) — Confirms overwrite behavior; no official workaround; user noted `include:` mechanism also gets overwritten
- Suricata memcap values for N100 + single-channel DDR5: No community benchmarks found; values in this document are derived from Suricata default documentation + general SOHO sizing guidance
- CU200 EVE JSON default state (enabled/disabled): Conflicting older evidence; requires `grep -A3 "eve-log:" /etc/suricata/suricata.yaml` on live CU200 system to confirm

---

## Metadata

**Confidence breakdown:**
- Standard stack (Suricata 8.0.3, WUI controls, EVE path): HIGH — confirmed from official IPFire docs and CU200 release notes
- Architecture (nfqueue inline, zone selection, rule file paths): HIGH — confirmed from multiple official sources and community developer posts
- memcap values: MEDIUM — derived from Suricata documentation defaults; no IPFire+N100 empirical data found
- EVE JSON default state in CU200: MEDIUM — config diff suggests enabled; live verification required
- Core Update overwrite protection: LOW — no official workaround exists; sha256 approach is project-invented

**Research date:** 2026-03-22
**Valid until:** 2026-04-22 (30 days for stable; IPFire CU201 may change suricata.yaml behavior)
