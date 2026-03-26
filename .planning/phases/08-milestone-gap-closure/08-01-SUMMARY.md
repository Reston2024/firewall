---
phase: 08-milestone-gap-closure
plan: "01"
subsystem: infra
tags: [gap-closure, suricata, syslog, backup, config-export]

provides:
  - Live suricata.yaml with N100 memcap tuning exported from IPFire (1753 lines)
  - Live syslog.conf with UDP forwarding to 192.168.1.101:514 exported (26 lines)
  - /etc/unbound/forward.conf added to backup-include.user (9 entries total)

key-files:
  created:
    - configs/suricata/suricata.yaml
    - configs/syslog.conf
  modified:
    - configs/firewall/backup-include.user

deviations: []

self-check:
  status: PASSED
  evidence:
    - configs/suricata/suricata.yaml is 1753 lines (not a reference/stub)
    - configs/syslog.conf is 26 lines with remote syslog config
    - backup-include.user contains /etc/unbound/forward.conf
---

## Summary

Exported live suricata.yaml and syslog.conf from IPFire to close the disaster recovery gaps (INT-1A, INT-ORF-1). Added /etc/unbound/forward.conf to backup-include.user (INT-6A). deploy-phase4.sh and deploy-phase5.sh can now deploy real configs on rebuild.
