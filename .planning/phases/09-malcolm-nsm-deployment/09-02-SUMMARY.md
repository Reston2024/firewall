---
phase: 09-malcolm-nsm-deployment
plan: 02
status: complete
started: 2026-04-02
completed: 2026-04-02
duration_minutes: 30
---

# Plan 09-02 Summary: ISM Policy + Dashboard Verification

## What Was Built

OpenSearch ISM retention policy "malcolm-retention" created with 30-day hot-to-delete lifecycle on network-* and arkime_sessions3-* indices. Malcolm prebuilt dashboards confirmed accessible and functional.

## Key Outcomes

- **ISM policy "malcolm-retention"** active in OpenSearch with 30-day max age rule
- **Index patterns**: network-* and arkime_sessions3-* with priority 100
- **Auto-attach**: ISM template will apply to new indices automatically
- **Prebuilt dashboards**: 20+ dashboards confirmed — Overview, Security Overview, Connections, Suricata Alerts, Zeek logs, Threat Intelligence, File Scanning, Asset Interaction, and more
- **Dashboards show "No results found"** — expected since no data is flowing yet (Phase 10)
- **Validation suite**: 9 PASS, 0 FAIL, 1 SKIP (MAL-01b heap parse — cosmetic)

## Decisions

- Malcolm internal service account (malcolm_internal via curlrc) used for OpenSearch API access instead of nginx admin credentials
- Validation script updated to auto-discover internal credentials from dashboards-helper container
- MALCOLM_PASS env var removed from validation script — no longer needed
- Malcolm serves dashboards via nginx at :443, not directly at :5601

## Files Modified

| File | Location | Change |
|------|----------|--------|
| scripts/validate-phase9.sh | Local repo | Fixed to use internal service account, removed MALCOLM_PASS dependency |
| ISM policy malcolm-retention | OpenSearch API (supportTAK-server) | Created 30-day retention policy |

## Human Verification

- Admin confirmed Malcolm dashboards load in browser at https://192.168.1.22
- 20+ prebuilt dashboards visible in Navigation panel
- "No results found" is expected pre-data-flow state
