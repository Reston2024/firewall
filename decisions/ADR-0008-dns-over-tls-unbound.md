# ADR-0008: DNS-over-TLS via Unbound

- **Date:** 2026-03-25
- **Status:** Accepted

## Context

DNS queries to upstream resolvers travel in plaintext by default over port 53, exposing browsing data to the ISP and any network observer on the path. IPFire uses Unbound as its DNS resolver with DNSSEC support built in. IPFire's DNS configuration UI has a TLS protocol option for upstream forwarding, but enabling TLS is mutually exclusive with using ISP-provided DNS servers — the two options cannot coexist in IPFire's configuration model.

## Decision

Enforce DNS-over-TLS (DoT) for all upstream DNS queries using Cloudflare (1.1.1.1) and Quad9 (9.9.9.9) as upstream resolvers. Disable ISP-provided DNS as a prerequisite.

## Rationale

- DoT encrypts all DNS queries to upstream resolvers over port 853, preventing ISP inspection of DNS traffic
- DNSSEC validates response integrity end-to-end, preventing DNS spoofing
- Disabling ISP DNS first is required by IPFire's mutual exclusivity constraint — ISP DNS and TLS protocol cannot both be active
- Cloudflare (1.1.1.1) and Quad9 (9.9.9.9) both support DoT natively and have published privacy-respecting DNS policies
- Quad9 adds a threat-blocking layer (malware/phishing domains) at the resolver level as a secondary benefit
- Configuration is deployed via `/var/ipfire/dns/forward.conf` — verifiable and version-controlled in the repo

## Consequences

- ISP DNS must be disabled first (mutual exclusivity constraint in IPFire WUI) before enabling TLS protocol
- All upstream DNS traffic uses port 853 — verifiable via `tcpdump -i RED0 port 853` on the RED interface
- DNS resolution depends on DoT-capable upstream resolvers being reachable; if Cloudflare and Quad9 are both unreachable, DNS fails
- The forward.conf configuration file is the source of truth for upstream resolver settings in the repo
