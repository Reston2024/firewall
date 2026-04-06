---
phase: 10-telemetry-migration-to-malcolm
plan: 01
status: complete
started: 2026-04-03
completed: 2026-04-05
duration_minutes: 240
---

# Plan 10-01 Summary: Wire EVE JSON + Syslog into Malcolm

## What Was Built

Both IPFire data paths (Suricata EVE JSON and syslog) now flow into Malcolm OpenSearch. Parallel validation with Loki stack confirmed active.

## Key Outcomes

- **EVE JSON path:** SCP cron (sync-eve.sh) pulls from IPFire every 60s → /opt/malcolm/suricata-logs/suricata-ipfire/eve.json → Malcolm internal Filebeat (tag: _filebeat_suricata_malcolm_upload) → Logstash suricata pipeline → arkime_sessions3-* indices (225K+ docs)
- **Syslog path:** IPFire syslog.conf → UDP :514 → rsyslog on SOC host → omfwd relay → Malcolm Filebeat syslog :5514 → Logstash beats pipeline → malcolm_beats_syslog_* indices (557K+ docs)
- **Parallel validation (MIG-01):** Both Malcolm AND Loki stacks running simultaneously, both receiving data
- **Logstash heap:** Bumped from 1GB to 2GB to handle EVE JSON volume without OOM
- **IPFire syslog target:** Updated from 192.168.1.101 to 192.168.1.22
- **EVE rsync key restored:** IPFire authorized_keys re-populated after crash (both management + eve_rsync keys)
- **Security fixes applied during execution:** E3-01 (StrictHostKeyChecking=yes), E2-01 (sshd hardened), E3-02 (rebuild.sh pinned known_hosts), E7-02 (Guardian config exported)

## Decisions

- External system Filebeat abandoned — Malcolm's Logstash pipeline routes on internal tags (_filebeat_suricata_malcolm_upload) that external Filebeat cannot replicate
- EVE JSON delivered via Malcolm's suricata-logs/suricata-* glob pattern, not via external Beats :5044
- Logstash heap increased to 2GB (was 1GB) — 1GB caused OOM under full EVE JSON volume
- IPFire host key stored in repo (configs/ssh/known_hosts) for crash recovery

## Files Modified

| File | Location | Change |
|------|----------|--------|
| telemetry-malcolm/filebeat/filebeat.yml | Local repo | Documentation of Malcolm-native EVE path |
| telemetry-malcolm/rsyslog/20-malcolm-forward.conf | Local repo | rsyslog omfwd relay to Malcolm :5514 |
| telemetry-malcolm/filebeat/scp-eve.sh | Local repo | SCP pull with StrictHostKeyChecking=yes |
| /opt/malcolm/scripts/sync-eve.sh | supportTAK-server | Live EVE sync to Malcolm watched dir |
| /opt/malcolm/config/filebeat.env | supportTAK-server | FILEBEAT_SYSLOG_UDP_LISTEN=true, port 5514 |
| /opt/malcolm/config/logstash.env | supportTAK-server | Heap bumped to -Xmx2g -Xms2g |
| /opt/malcolm/docker-compose.yml | supportTAK-server | Logstash :5044 and Filebeat :5514/udp exposed |
| /etc/rsyslog.d/20-malcolm-forward.conf | supportTAK-server | omfwd relay to 127.0.0.1:5514 |
| /etc/syslog.conf | IPFire | Target updated to 192.168.1.22 |
