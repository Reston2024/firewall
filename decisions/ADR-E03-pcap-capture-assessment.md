# ADR-E03: PCAP Capture Feasibility Assessment

- **Date:** 2026-04-08 (original), 2026-04-09 (superseded — hardware acquired)
- **Status:** Superseded — PCAP capture is NOW ACTIVE
- **References:** PCAP-01, PCAP-02, PCAP-03, PCAP-04

> **UPDATE 2026-04-09:** GS308EP managed switch and USB Ethernet adapter acquired and deployed.
> SPAN mirror active (Port 1 → Port 5). Zeek (2 workers) and Suricata (2 threads)
> capturing live packets on enx6c6e072d459d. Arkime re-enabled. This ADR's "DEFERRED"
> conclusion is no longer current — PCAP capture is operational.

## Context

Malcolm NSM includes Arkime for PCAP capture and analysis. Arkime requires raw packet data delivered via either:
1. A managed switch with SPAN/mirror port capability
2. A hardware network tap
3. A software tap on the IPFire host (documented as unreliable — daemonlogger produces malformed packets on IPFire)

The current network uses an unmanaged LAN switch between the IPFire N100 and all GREEN zone devices.

## Assessment

### Hardware Inventory

| Component | SPAN Capable? | Notes |
|-----------|--------------|-------|
| ISP modem | No | Consumer-grade, no mirror port |
| LAN switch | **No** | Unmanaged — no SPAN capability |
| IPFire N100 | No software tap | daemonlogger produces malformed packets per Malcolm docs |
| supportTAK-server (GMKtec) | One Ethernet NIC (enp3s0) | No spare NIC for dedicated capture |

### Conclusion

**PCAP capture is NOT feasible in the current hardware configuration.**

Requirements:
1. **Managed switch** with SPAN/mirror port capability (e.g., Netgear GS308E, TP-Link TL-SG108E, ~$30-50)
2. **USB Ethernet adapter** or second NIC for supportTAK-server dedicated capture interface
3. Arkime re-enabled in Malcolm with `ARKIME_FREESPACEG=15%` disk guard

## Decision

Defer PCAP capture to v3.0. Document hardware requirements for future implementation. Arkime containers remain disabled in Malcolm docker-compose.yml (Phase 9 decision preserved).

### Required Hardware for v3.0

| Item | Estimated Cost | Purpose |
|------|---------------|---------|
| Managed switch (8-port, SPAN capable) | $30-50 | Mirror all traffic to capture port |
| USB 2.5GbE adapter for GMKtec | $15-25 | Dedicated capture NIC on supportTAK-server |

Total: ~$45-75

## Consequences

- Arkime stays disabled — no RAM consumed for capture
- No PCAP-based investigation capability in v2.0
- Network metadata (Zeek conn.log, Suricata EVE) provides session-level visibility without full packet capture
- v3.0 roadmap should include managed switch procurement as a pre-requisite
