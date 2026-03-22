# Firewall Appliance Repo

IPFire 2.29 CU200 — N100 6-NIC appliance configuration, scripts, and validation artifacts.

**Core value:** Rebuild the appliance from scratch in under 15 minutes.

## Directory Structure

| Directory | Purpose |
|-----------|---------|
| configs/udev/ | udev NIC persistence rules |
| configs/ethernet/ | IPFire ethernet/settings export |
| configs/firewall/ | firewall.local and zone policy docs |
| scripts/ | Validation and automation scripts |
| docs/ | Architecture decisions, runbooks, NIC map |
| services/ | DHCP, DNS, NTP configs (Phase 2+) |
| validation/ | Test artifacts (Phase 6) |
| rollback/ | Rollback procedures (Phase 7) |
| manifests/ | Pakfire addon manifest (Phase 7) |
| decision-log/ | ADR index (Phase 7) |

## Quick Commands

```bash
# Validate NIC-to-zone mapping (run on IPFire)
bash /root/firewall-repo/scripts/validate-nics.sh

# Run full Phase 1 validation suite (run on IPFire)
bash /root/firewall-repo/scripts/validate-phase1.sh
```

## Hardware

- Platform: N100 6-NIC mini-PC
- NICs: 6x Intel i226-V (igc driver)
- OS: IPFire 2.29 Core Update 200
- Kernel: 6.18.7 LTS

See docs/nic-map.md for physical port to zone mapping.
