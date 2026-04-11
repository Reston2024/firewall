---
phase: 15-audit-remediation-v2.0.1
plan: 01
status: complete
started: 2026-04-11
completed: 2026-04-11
duration_minutes: 360
---

# Phase 15 Plan 01 Summary: v2.0.1 Security Audit Remediation

## What Was Built

Response to a debugging-team audit of the 3-machine SOC stack delivered
on 2026-04-11. Scope: only items in the Firewall repo + IPFire + supportTAK
domain. Desktop-SOC-specific findings forwarded to that team separately.

Ground-truth verification against the audit paper analysis uncovered
**two audit false positives**, **several confirmed findings**, and — most
critically — **one audit finding that was understated in impact**. The
understated finding turned out to be a live silent-telemetry-loss incident
plus an active memory leak on IPFire, which was remediated first.

### Critical incidents discovered during audit verification

**1. IPFire mail-queue fork bomb + Suricata OOM kill (not in audit)**

- `/var/spool/dma` had grown to 181,935 queued messages + 717 MB
- 20,557 stuck `dma -q` processes + 31,861 total processes
- 10.5 GB anonymous memory leaked across user processes
- IPFire's Suricata was OOM-killed, stale pidfile at `/var/run/suricata.pid`
- `/var/log/suricata/eve.json` mtime stuck at 05:01 for 7+ hours,
  zero new events since then
- Traced to: IPFire's Suricata IPS alert feature has
  `ENABLE_EMAIL=on` with `sender=recipient=[REDACTED-operator-email]`.
  Every alert generated an outbound email. No outbound SMTP relay
  configured — Gmail rejects residential IPs. DMA retried for 5 days
  then generated bounces BACK to the same sender, creating an
  infinite loop. Started 2026-03-27, discovered 2026-04-11.
- Remediation: preserved 5 mail samples for forensic evidence at
  `/root/incident-2026-04-11-dma-loop/`; renamed `/var/spool/dma` to
  `dma.old.20260411`; `killall -9 dma`; disabled email output in
  both `/var/ipfire/suricata/settings` (`ENABLE_EMAIL=off`) and
  `/var/ipfire/suricata/reporter.conf` (`[email] enabled=false`);
  removed stale pidfile; restarted Suricata.
- Post-recovery state: 145 processes (down from 31,861), 14.5 GB
  free RAM (up from 168 MB), suricata-watcher + Suricata-Main running
  at ~8% CPU, eve.json actively appending.

**2. sync-eve.sh cron had never actually run**

- Audit flagged "scp-eve.sh missing from repo"; reality was worse.
- Cron line: `* * * * * /opt/malcolm/scripts/sync-eve.sh >> /var/log/sync-eve.log 2>&1`
- `/var/log` is `root:syslog` mode 0775; opsadmin (cron owner) is
  not in group syslog
- Bash-redirect at cron shell-start failed with `Permission denied`;
  modern bash refuses to execute the command when its output
  redirect fails, so the script never ran
- Silent failure mode: no log file to inspect (cron can't create
  it either), no indication in /var/log/syslog except cron session
  open/close records
- Consequence: `/opt/malcolm/suricata-logs/suricata-ipfire/eve.json`
  did not exist; all 10,000+ recent Malcolm alerts came from the
  SPAN-captured live Suricata container (`host.name:
  supportTAK-server`), zero from IPFire's own Suricata engine
- Remediation: rewrote `sync-eve.sh` as a self-logging,
  byte-offset incremental-append implementation (see B-1 below).
  Replaced `scp + atomic-mv` (new inode every minute — Filebeat
  would re-read 253 MB per run) with `ssh tail -c +OFFSET`
  piped directly to `>> dest` (same inode, Filebeat tails
  continuously, only new bytes transferred). Self-logs to
  `$HOME/logs/sync-eve.log` instead of `/var/log/sync-eve.log`.

### Ground-truth verification outcomes

**True positives (audit correct — remediated below):**

- D-06: supportTAK UFW inactive; `:9200`, `:8200`, `:5514` all 0.0.0.0
- D-07: Malcolm Filebeat `:5514` UDP accepts from any LAN host
- D-15: No logrotate for Suricata eve.json (253 MB observed)
- D-26: rsyslog `queue.type=LinkedList` (RAM-only, 10K msg cap)

**Audit claim understated (now known to be an active incident):**

- C-04/D-16: "scp-eve.sh not in repo" → reality is worse (see above)

**False positives (audit was wrong — documented, no code change):**

- D-13/C-03: Audit said `/etc/syslog.conf` forwards to `@192.168.1.101`.
  **Live config on IPFire forwards to `@192.168.1.22`** (correct).
  However, the REPO copy at `configs/syslog.conf` was stale — fixed
  in B-2.
- D-03: Audit claimed "RED/GREEN subnet collision on /24". **Live
  state**: `red0 = 162.228.116.144/22` (ISP-assigned public range),
  `green0 = 192.168.1.1/24`. Completely separate networks; perimeter
  segmentation is working. topology.yaml comment corrected in D-3.
- C-02: Audit claimed "normalization server on 192.168.1.22:8080
  unauthenticated". **No process listens on :8080 on supportTAK.**
  If a normalization server runs anywhere, it's on the desktop SOC
  (out of my domain).

## Phase-by-phase changes

### Phase A — IPFire recovery (see critical incident 1 above)

- Archived 5 mail samples to `/root/incident-2026-04-11-dma-loop/`
- Killed suricata-reporter + all dma workers
- Renamed mail spool (O(1) instead of deleting 181,935 files)
- Disabled email output in both settings and reporter.conf
- Removed stale pidfile, restarted Suricata via `/etc/init.d/suricata start`

### Phase B-1 — Fix sync-eve.sh silent failure

New: `telemetry-malcolm/filebeat/sync-eve.sh`. Removed stale
`scp-eve.sh` from the repo (it had diverged from live in name,
destination path, and SSH key).

Design: byte-offset incremental fetch via `ssh tail -c +OFFSET`
piped directly to `>> dest`. Self-logging via
`$HOME/logs/sync-eve.log` + `logger -t sync-eve`. Heartbeat file at
`$HOME/.sync-eve.heartbeat`, failure sentinel at
`$HOME/.sync-eve.failed`. Handles source rotation by detecting
size shrinkage and resetting the cursor. Same-inode append so
Malcolm Filebeat's `fingerprint.enabled: false` tailing works
correctly.

Live verification: heartbeat advances every minute, destination
file actively growing, Filebeat registry shows continuous cursor
advance (252916964 → 253838439 → 253855872 → 253877148 ...), new
IPFire-origin alerts now ingesting into Malcolm.

### Phase B-2 — Fix stale repo syslog.conf

`configs/syslog.conf` changed from `@192.168.1.101` → `@192.168.1.22`
with a comment explaining the historical drift. Live system was
already correct; this is pure DR-safety.

### Phase B-3 — Suricata eve.json logrotate on IPFire

New: `configs/logrotate.d-suricata`, deployed to
`/etc/logrotate.d/suricata`. Policy: rotate when size ≥ 100 MB,
keep 24, `copytruncate` (safe for running Suricata), compress,
delaycompress, missingok, notifempty. Dry-run confirmed the first
rotation would happen at the next fcron.hourly cycle (01 past the
hour) since the current file is already 253 MB.

### Phase B-4/5 — UFW + DOCKER-USER rules on supportTAK

New: `configs/ufw/supporttak-rules.sh` (idempotent initial setup
of UFW + DOCKER-USER for :9200, :443, :5044, :5514).
New: `configs/ufw/supporttak-docker-user-reapply.sh` (minimal
reapply of DOCKER-USER rules only — rerun every 5 minutes via
`/etc/cron.d/malcolm-docker-user` to survive Malcolm docker-compose
restart cycles which wipe the DOCKER-USER chain).

Two-layer posture:
- UFW on host for :22 (SSH), :514 UDP (syslog from IPFire), :8200
  (ChromaDB python host process)
- DOCKER-USER chain for Malcolm-published ports (:9200 OpenSearch,
  :443 dashboard, :5044 logstash-beats, :5514 Filebeat syslog).
  These bypass UFW because Docker inserts ACCEPTs into the FORWARD
  chain before UFW's filter rules run.

Trust list: `192.168.1.100` (laptop), `192.168.1.102` (desktop SOC),
`127.0.0.1` (loopback), `192.168.1.1` (IPFire for syslog only).

### Phase C-1 — rsyslog disk-backed queue

`configs/rsyslog.d-20-malcolm-forward.conf`: added
`queue.saveOnShutdown="on"`, `queue.filename="malcolm-forward"`,
`queue.maxDiskSpace="100m"`, `queue.spoolDirectory="/var/spool/rsyslog"`.
Previously the queue was RAM-only — a rsyslog restart during high
traffic could drop up to 10K buffered messages.

### Phase C-2 — WireGuard VPN CUSTOMFORWARD restrictions

`configs/firewall/firewall.local` updated. Previously
`-A FORWARD -i wg0 -j ACCEPT` blanket allowed VPN clients to reach
any host on GREEN /24. Replaced with `CUSTOMFORWARD` rules:

1. `-i wg0 -d 192.168.1.1 -j ACCEPT` (VPN → IPFire for DNS/routing)
2. `-i wg0 -d 192.168.1.22 -p tcp --dport 443 -j ACCEPT`
3. `-i wg0 -d 192.168.1.22 -p tcp --dport 9200 -j ACCEPT`
4. `-i wg0 -d 192.168.1.22 -p tcp --dport 8200 -j ACCEPT`
5. `-i wg0 -d 192.168.1.0/24 -j DROP` (everything else GREEN denied)
6. Non-GREEN destinations fall through to POLICYFWD's existing
   `wg+ *` ACCEPT (internet path preserved)

Key IPFire-specific detail: rules MUST be in CUSTOMFORWARD (runs at
FORWARD rule #3) not the top-level FORWARD. IPFire's POLICYFWD chain
at FORWARD rule #21 already has `ACCEPT all -- wg+` which would
short-circuit any tail-of-FORWARD rule.

### Phase C-3 — ILM policy coverage expansion

`telemetry-malcolm/opensearch/ism-policy.json`: added `malcolm_beats_*`
to the existing `malcolm-retention` policy's `index_patterns` list.
`malcolm_beats_syslog_*` had been silently growing uncapped at
28 million docs/day, ~4 GB/day. Policy PUT with `if_seq_no` / `if_primary_term`
optimistic concurrency; applied retroactively to 11 existing
`malcolm_beats_*` indices via `_plugins/_ism/add`.

### Phase C-4 — sync-eve watchdog

New: `scripts/validate-sync-eve.sh` with 6 checks (SE-01 heartbeat
freshness, SE-02 failure sentinel absence, SE-03 dest mtime freshness,
SE-04 source mtime freshness, SE-05 log FAIL line absence, SE-06
evidence archive freshness). Wired into `scripts/validate-all.sh`
via new `run_sync_eve()` function. Laptop-role full-suite now
includes this check. The watchdog IS the validator that would have
caught the sync-eve silent failure if it had existed before this
audit.

### Phase D — Medium-priority

- **D-1**: supportTAK NTP confirmed working (systemd-timesyncd active,
  syncing from `ntp.ubuntu.com`, offset ~61 ms). No code change.
- **D-2**: archive health added as SE-06 in validate-sync-eve.sh
  (pass if newest file under `/media/opsadmin/Seagate Portable Drive/firewall-archive`
  is < 90 minutes old).
- **D-3**: `topology.yaml` corrected. `red: "DHCP (currently
  192.168.1.106)"` → `red: "DHCP (verified 2026-04-11: 162.228.116.144/22)"`.
  `subnets.red: "192.168.1.0/24 (modem NAT — same subnet as GREEN)"`
  → accurate description of the real ISP-assigned range. This
  correction is the input the audit team needs so their next pass
  doesn't regenerate the D-03 false positive from repo artifacts.

## Key Outcomes

- IPFire Suricata back online, eve.json actively growing, 14.5 GB RAM free
- sync-eve.sh rewritten and functional; IPFire-origin alerts reaching Malcolm
- Host firewall active on supportTAK: UFW + DOCKER-USER two-layer posture
- rsyslog queue now disk-backed across restart
- WireGuard VPN clients can no longer reach arbitrary GREEN /24 hosts
- `malcolm_beats_*` now covered by 30-day retention policy (previously unbounded)
- New silent-failure watchdog: `validate-sync-eve.sh`, 6 checks, integrated into `validate-all.sh`
- Evidence preserved for forensic review:
  `/root/incident-2026-04-11-dma-loop/` (mail samples),
  `/var/spool/dma.old.20260411/` (full 717 MB spool),
  `settings.bak-20260411`, `reporter.conf.bak-20260411`,
  `20-malcolm-forward.conf.bak-20260411`,
  `/opt/malcolm/scripts/sync-eve.sh.bak-20260411`,
  `/etc/sysconfig/firewall.local.bak-20260411`
- Manifest regenerated on IPFire: 12 files (was 11; +/etc/logrotate.d/suricata)
- `validate-all.sh` laptop role: 6 PASS / 0 FAIL / 8 SKIP (every SKIP documented)

## Decisions

- **Fix root cause before symptoms**: the audit recommended killing
  dma workers as a fast fix; I investigated the mail spool first
  and found the root cause (IPFire IPS alert feature) before touching
  anything. Disabling email alerting at the source prevented the loop
  from regenerating.
- **Two-layer host firewall**: UFW alone doesn't block Docker-published
  ports because Docker inserts filter rules that run before UFW. Used
  `iptables DOCKER-USER` directly for Docker ports + UFW for host
  processes. Both persisted via scripts + cron reapply.
- **Byte-offset append instead of atomic replace** for sync-eve.sh:
  enables same-inode semantics so Malcolm Filebeat can tail
  continuously without duplicating events on every cycle.
- **CUSTOMFORWARD not FORWARD** for WireGuard restrictions: IPFire's
  POLICYFWD chain has a blanket `wg+ *` ACCEPT at FORWARD rule #21,
  so rules in the top-level FORWARD at rule #22+ would never execute.
  CUSTOMFORWARD at rule #3 is the correct insertion point.
- **Preserve evidence before remediation**: the 181,935-message mail
  spool is renamed (O(1)) rather than deleted. Future forensic analysis
  can extract patterns, timestamps, frequency, and the bounce-loop
  chain from the preserved files.
- **Three audit false positives documented, not "fixed"**: the audit's
  D-03, D-13-live, C-02 were wrong when measured against reality. I
  documented the reality in topology.yaml and this summary so the
  next audit pass doesn't repeat them.

## Files Modified

| File | Type | Change |
|---|---|---|
| `telemetry-malcolm/filebeat/sync-eve.sh` | new | byte-offset append, self-logging, heartbeat |
| `telemetry-malcolm/filebeat/scp-eve.sh` | deleted | stale, replaced by sync-eve.sh |
| `configs/syslog.conf` | edit | `@192.168.1.101` → `@192.168.1.22` |
| `configs/logrotate.d-suricata` | new | 100 MB rotation, copytruncate, 24 kept |
| `configs/ufw/supporttak-rules.sh` | new | idempotent UFW + DOCKER-USER setup |
| `configs/ufw/supporttak-docker-user-reapply.sh` | new | DOCKER-USER persistence across docker restart |
| `configs/rsyslog.d-20-malcolm-forward.conf` | new | disk-backed queue |
| `configs/firewall/firewall.local` | edit | CUSTOMFORWARD wg0 rules |
| `telemetry-malcolm/opensearch/ism-policy.json` | new | expanded to cover malcolm_beats_* |
| `scripts/validate-sync-eve.sh` | new | 6-check sync-eve watchdog |
| `scripts/validate-all.sh` | edit | run_sync_eve orchestration |
| `scripts/check-drift.sh` | edit | added /etc/logrotate.d/suricata to MANAGED_FILES |
| `manifests/file-manifest.sha256` | regen | 11 → 12 files |
| `topology.yaml` | edit | RED subnet corrected (was fabricated) |

## Live system changes (deployed + verified)

| Host | Change |
|---|---|
| IPFire | dma workers killed, mail spool archived, /var/spool/dma recreated |
| IPFire | /var/ipfire/suricata/settings: ENABLE_EMAIL=off |
| IPFire | /var/ipfire/suricata/reporter.conf: [email] enabled=false |
| IPFire | Suricata restarted; running as Suricata-Main(20075) under suricata-watcher(20068) |
| IPFire | /etc/sysconfig/firewall.local: CUSTOMFORWARD wg0 rules applied |
| IPFire | /etc/logrotate.d/suricata: new logrotate config installed |
| IPFire | /root/firewall-repo/manifests/file-manifest.sha256: 12 files baselined |
| supportTAK | /opt/malcolm/scripts/sync-eve.sh: rewritten + deployed |
| supportTAK | /opt/malcolm/scripts/supporttak-docker-user-reapply.sh: new |
| supportTAK | /etc/cron.d/malcolm-docker-user: @reboot + */5 reapply cron |
| supportTAK | /etc/rsyslog.d/20-malcolm-forward.conf: disk-backed queue; rsyslog restarted |
| supportTAK | UFW active with 5 rules (ssh/chromadb/syslog from trusted sources) |
| supportTAK | iptables DOCKER-USER: 14 rules for opensearch/dashboard/beats/filebeat |
| supportTAK | OpenSearch ISM policy malcolm-retention: +malcolm_beats_* pattern |
| supportTAK | systemd-timesyncd reconciled (was reporting inactive despite running) |
| opsadmin cron | sync-eve cron line: removed broken `>> /var/log/sync-eve.log 2>&1` redirect |

## Concerns

1. **duplicate systemd-timesyncd process on supportTAK** (pid 632 from
   Apr 7 + my new pid 1851696). Service is active, time is synced, but
   two instances is unusual. Could be a systemd unit tracking glitch.
   Deferred as v2.1 cleanup.

2. **grype critical CVEs from v2.0.0 SBOM**: still 68 High CVEs in
   system SBOM, mostly nodejs 12.22 and libqt5webkit5. Unrelated to
   audit but still tracked from v2.0.0 closure.

3. **Logstash backlog**: syslog ingestion is still catching up on the
   24M-message backlog from the dma loop period. Current rate ~3000
   docs/10min is a mix of historical drain + current events. New events
   (timestamps from now) may be queued behind historical events and
   appear with delay. Rate will return to normal once backlog clears.

4. **DOCKER-USER rule persistence is cron-based** (@reboot + every 5 min).
   A narrow window exists between a Malcolm restart and the next cron
   cycle where the rules are cleared. Max exposure: 5 minutes. v2.1 could
   tighten this with a systemd Restart=on-failure wrapper around the
   reapply script triggered by docker.service state changes.

5. **Mail loop root fix**: email alerting is now DISABLED, not
   RECONFIGURED. If the user wants IPS alerts via email in the future,
   they need a proper outbound SMTP relay (e.g., an SMTP-auth account
   at a mail provider) configured in IPFire. Tracked as v2.1 task,
   not blocker.

## Out of scope (forwarded to desktop SOC team)

All desktop SOC audit findings from the debugging team report:
C-01 (hardcoded password in config.py), C-05 (Sigma backend),
D-17..D-20 (desktop config), D-28..D-33 (detection engineering + IR),
D-34..D-38 (reliability), D-42..D-44 (AI safety), RT-01..RT-05
(red team paths on desktop), D-04 (east-west SPAN blind spot —
hardware decision).
