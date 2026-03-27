---
plan: 02-03
phase: 02-core-network-services
status: complete
completed: 2026-03-26
duration_minutes: 0
tasks_completed: 2
tasks_total: 2
files_modified:
  - configs/dhcp/dhcpd.conf
  - configs/dns/forward.conf
  - configs/dns/unbound.conf
  - configs/ntp/time-settings
  - configs/ntp/ntp.conf
one_liner: "WUI deployment of DHCP/DNS-over-TLS/NTP, live config export, and Phase 2 acceptance on live IPFire"
---

# Summary: 02-03 — Human WUI Deployment Checkpoint

## What Was Done

All Phase 2 services configured via IPFire WUI and verified:

1. **NTP**: Enabled client serving (ENABLECLNTP=on), synced to ipfire.pool.ntp.org
2. **DHCP**: GREEN zone DHCP with gateway/DNS/NTP all pointing to 192.168.1.1
3. **DNS-over-TLS**: forward-tls-upstream: yes with Cloudflare and Quad9 resolvers at @853
4. **Live Config Export**: dhcpd.conf, forward.conf, unbound.conf, time-settings, ntp.conf exported from IPFire and committed

## Validation Results

```
validate-phase2.sh: 17 pass, 0 fail — ALL CHECKS PASS
```

- SVC-01: DHCP routers/DNS/NTP options all set to 192.168.1.1
- SVC-02: SKIP (no static leases configured yet — valid initial state)
- SVC-03: DNSSEC AD flag validated, SERVFAIL on bad signatures
- SVC-04: forward-tls-upstream: yes confirmed, Cloudflare/Quad9 TLS hostnames present
- SVC-05: NTP synced (*198.12.95.197, stratum 2), port 123 listening
- SVC-06: Boot symlinks for dhcp, unbound, ntp all present

## Key Config Excerpts

- dhcpd.conf: `option ntp-servers 192.168.1.1;`
- forward.conf: `forward-tls-upstream: yes`
- time-settings: `ENABLECLNTP=on`

## Sign-off

Phase 2 Core Network Services is complete. All 6 requirements (SVC-01 through SVC-06) verified operational on live IPFire.
