---
phase: 09-malcolm-nsm-deployment
plan: 01
status: complete
started: 2026-04-02
completed: 2026-04-02
duration_minutes: 180
---

# Plan 09-01 Summary: Malcolm NSM Installation

## What Was Built

Malcolm NSM v26.02.0 deployed to supportTAK-server (192.168.1.22) with heap-tuned OpenSearch (6GB) and Logstash (1GB), Arkime live capture disabled, kernel params set, and all 27 containers running healthy.

## Key Outcomes

- **27 Docker containers** running, all healthy (filescan was briefly unhealthy — cosmetic)
- **OpenSearch heap**: 6GB (-Xms6g -Xmx6g) — within 16GB RAM budget
- **Logstash heap**: 1GB (-Xms1g -Xmx1g)
- **OPENSEARCH_BOOTSTRAP_MEMORY_LOCK=false** — prevents Docker startup failure
- **OPENSEARCH_INDEX_SIZE_PRUNE_LIMIT=200g** — storage safety net
- **Live capture disabled**: PCAP_ENABLE_NETSNIFF=false, PCAP_ENABLE_TCPDUMP=false, ZEEK_LIVE_CAPTURE=false, SURICATA_LIVE_CAPTURE=false
- **vm.max_map_count=262144** persisted in /etc/sysctl.d/99-malcolm.conf
- **Swap**: 6GB pre-existing (exceeds 4GB requirement)
- **No OOM kills** detected
- **RAM usage**: ~12.5GB of 16GB at steady state (1.7GB swap used)
- **Web UI**: https://192.168.1.22:443 serving with basic auth (401 without credentials)
- **Validation script**: scripts/validate-phase9.sh created covering MAL-01, MAL-04, MAL-05, MAL-06

## Decisions

- install.py interactive wizard used instead of scripted install — wizard correctly applied heap and capture settings from menu selections
- auth_setup run as non-root (opsadmin) after adding to docker group — root causes permission issues
- Malcolm serves via nginx at :443 (not :5601 directly) — validation script updated accordingly
- UDP :514 conflict with rsyslog confirmed and deferred to Phase 10 per plan

## Files Modified

| File | Location | Change |
|------|----------|--------|
| scripts/validate-phase9.sh | Local repo | Created — Phase 9 validation suite |
| /opt/malcolm/* | supportTAK-server | Malcolm v26.02.0 installed |
| /opt/malcolm/config/opensearch.env | supportTAK-server | Heap 6GB, memory_lock=false, prune=200g |
| /opt/malcolm/config/logstash.env | supportTAK-server | Heap 1GB |
| /opt/malcolm/config/pcap-capture.env | supportTAK-server | Capture disabled |
| /opt/malcolm/config/zeek-live.env | supportTAK-server | Live capture disabled |
| /opt/malcolm/config/suricata-live.env | supportTAK-server | Live capture disabled |
| /etc/sysctl.d/99-malcolm.conf | supportTAK-server | vm.max_map_count=262144 |

## Concerns

- RAM at 12.5GB is higher than budgeted (~8GB expected for Malcolm). 27 containers vs expected ~15. Swap absorbing 1.7GB. Monitor for OOM under load.
- Filescan container showed unhealthy briefly — not critical but worth monitoring.
- install.py and auth_setup are interactive — cannot be fully automated in executor agents.
