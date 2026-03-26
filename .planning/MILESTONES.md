# Milestones

## v1.0 Firewall Appliance (Shipped: 2026-03-26)

**Phases completed:** 8 phases, 27 plans, 20 tasks

**Key accomplishments:**

- `scripts/validate-nics.sh`
- One-liner:
- One-liner:
- One-liner:
- One-liner:
- One-liner:
- One-liner:
- Telemetry deployment runbook created and live stack deployed: 5-container Docker Compose stack running on supportTAK-server with rsyslog→file→Alloy→Loki syslog path delivering 112,769 IPFire log entries within 5 minutes of activation
- EVE JSON path fully wired: scp-pull cron every 60s from IPFire to supportTAK-server, Alloy tailing /var/log/ipfire-eve/eve.json, GPL ATTACK_RESPONSE test alert confirmed in Loki within 90 seconds, DASH-04 PASS
- Custom IPFire firewall dashboard (4 panels) deployed to live Grafana, validate-phase5.sh passes 10/10 with 2 permanent skips, Phase 5 telemetry pipeline complete
- CIS-safe sysctl hardening config, 8-file SHA256 integrity monitor, reboot persistence validator, WUI certificate docs, and extended backup scope — all 6 hardening artifacts created for Phase 6 deployment
- validate-phase6.sh covers all 5 HARD checks; validate-all.sh orchestrates 6 phases with SSH-based Phase 5 remote execution and graceful SKIP on connection failure
- 9-section hardening deployment runbook for IPFire, covering sysctl hardening, file permission lockdown, service audit, WUI certificate documentation, integrity baseline, validate-phase6.sh execution, and pre-reboot snapshot capture
- sha256-based full-manifest drift detection script (check-drift.sh) with --verify/--generate modes, placeholder manifest for all 12 managed files, and backup-include.user updated to 8 entries covering all /etc/ and /root/ managed configs
- One-liner:
- rebuild.sh
- Fix 1 — validate-all.sh line 88 (INT-7A, MEDIUM)

---
