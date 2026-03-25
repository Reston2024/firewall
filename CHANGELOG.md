# Changelog

All notable changes to the Firewall Appliance project.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project uses milestone-based versioning.

## [0.5.0] - 2026-03-25

### Added
- Telemetry pipeline: Grafana + Loki + Alloy + Prometheus on supportTAK-server
- Suricata EVE JSON dashboard and IPFire firewall drops dashboard
- Syslog path (IPFire → Alloy → Loki) verified live
- EVE JSON rsync path (IPFire → supportTAK-server → Alloy → Loki)
- Phase 5 validation suite (validate-phase5.sh)
- Telemetry deployment runbook
- GitHub Actions CI (YAML lint, shell lint, compose validation, secret scan)
- .gitattributes, .editorconfig, Makefile for repo hygiene
- SECURITY.md, CONTRIBUTING.md
- .pre-commit-config.yaml (gitleaks, shellcheck, yaml/json validation)
- .env.example for telemetry secrets
- ADRs for SSH port, management access, Grafana exposure, telemetry separation

### Changed
- Grafana bound to 127.0.0.1:3000 (was 0.0.0.0 — CIS network exposure fix)
- Management access restricted to 192.168.1.100 only (removed broad GREEN fallback per CIS v8 4.7)
- SSH port standardized to 22 across all docs and configs
- README: corrected credential docs, clone URL, completion language
- Renamed decision-log/ to decisions/

### Fixed
- Port 222 references in deployment-checklist.md and zone-policy-runbook.md corrected to 22
- README admin/admin credential reference replaced with .env instruction

## [0.4.0] - 2026-03-24

### Added
- Suricata IDS/IPS deployment (Phase 4)
- ET Community rules enabled in surveillance mode
- Suricata integrity check script (check-suricata-integrity.sh)
- Phase 4 validation suite (validate-phase4.sh)
- Suricata IDS runbook

## [0.3.0] - 2026-03-23

### Added
- SSH hardening deployment (Phase 3)
- Key-only authentication, password auth disabled
- Guardian brute-force protection with management host whitelist
- ORANGE/BLUE SSH DROP rules in firewall.local
- Phase 3 validation suite (validate-phase3.sh)
- SSH management runbook

## [0.2.0] - 2026-03-22

### Added
- Core network services (Phase 2): DHCP, DNS (Unbound + DNSSEC + DoT), NTP
- Phase 2 validation suite (validate-phase2.sh)
- Services runbook

## [0.1.0] - 2026-03-21

### Added
- Platform foundation (Phase 1)
- NIC persistence via udev rules (30-persistent-network.rules)
- Anti-lockout firewall.local with CUSTOMINPUT rules
- Zone policy configuration (GREEN/RED/BLUE/ORANGE)
- backup-include.user for Core Update survival
- Phase 1 validation suite (validate-phase1.sh, validate-nics.sh, validate-firewall.sh)
- Deployment checklist and zone policy runbook
- NIC map documentation
