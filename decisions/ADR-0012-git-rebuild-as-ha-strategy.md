# ADR-0012: Git-Based Rebuild as HA Strategy

- **Date:** 2026-03-25
- **Status:** Accepted

## Context

The firewall appliance needs a recovery strategy for hardware failure or configuration corruption. Traditional high-availability approaches include LVM/ZFS snapshots, hot standby with failover, or active-active clustering. IPFire runs on a minimal Linux installation without LVM or ZFS support. Hot standby requires a second identical hardware unit and synchronization mechanism. Clustering adds operational complexity disproportionate to the SOHO scale of this deployment.

## Decision

Git-based rebuild is the high-availability strategy. All configs, scripts, and manifests live in a git repository. A rebuild script (`rebuild.sh`) applies the full configuration to a fresh IPFire installation idempotently. Target RTO: 15 minutes.

## Rationale

- IPFire's minimal environment has no LVM/ZFS snapshot support — traditional filesystem-level recovery is not available
- Hot standby and clustering are explicitly out of scope for a SOHO deployment (operational complexity disproportionate to risk)
- Git provides full version history of every configuration change — enables audit, rollback to any prior state, and root cause analysis after incidents
- Rebuild script is testable and repeatable — can be validated during a planned maintenance window without waiting for an actual hardware failure
- SCP-based deployment (not git clone on IPFire) keeps IPFire itself tool-free — IPFire does not need git, curl, or any extra tooling installed
- 15-minute RTO is achievable for fresh IPFire install + rebuild script execution on N100-class hardware with a pre-staged ISO

## Consequences

- Hardware failure recovery procedure: (1) install fresh IPFire on replacement hardware, (2) provision SSH key and verify WUI certificate, (3) run `rebuild.sh` from the dev machine — full recovery achievable in 15 minutes
- IPFire does not have git installed — the repository lives on the dev machine only; the firewall appliance never touches git directly
- All configuration changes must be committed to git to be reproducible — uncommitted changes are lost on hardware failure
- WUI-managed settings (Guardian thresholds, firewall rules created via WUI, manual Suricata rule toggles) require manual recreation after rebuild — documented in rebuild script output and operational runbook
- The repo itself must be backed up (not just the appliance) — loss of the dev machine and repo simultaneously would require full manual reconfiguration
