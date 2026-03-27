# Phase 2: Core Network Services - Research

**Researched:** 2026-03-22
**Domain:** IPFire DHCP, Unbound DNS (DNSSEC + DNS-over-TLS), NTP on IPFire 2.29 CU200
**Confidence:** HIGH (WUI-driven configuration paths) / MEDIUM (exact file formats for git export)

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SVC-01 | DHCP server on GREEN zone with correct gateway, DNS, and NTP options | DHCP config paths, subnet block format, and NTP/DNS option fields documented below |
| SVC-02 | DHCP static leases capability for known hosts | `fixleases` CSV format and `dhcpd.conf` fixed-address block format documented below |
| SVC-03 | DNS resolver via Unbound with mandatory DNSSEC validation | DNSSEC is on by default since CU80; Unbound replaced dnsmasq in CU106; validation approach documented |
| SVC-04 | DNS-over-TLS enforcement with configured upstream resolvers (Cloudflare/Quad9) | WUI TLS protocol selection, TLS hostname fields, `forward.conf` format documented; ISP DNS disable required |
| SVC-05 | NTP service synchronized to upstream pools and serving clients | WUI "Provide time to local network" setting, DHCP NTP option, `ntpq -p` verification documented |
| SVC-06 | All core services persist and auto-start after reboot | IPFire 2.x uses SysVinit; all core services (dhcpd, unbound, ntpd) auto-start via `/etc/init.d/` without manual enable steps |
</phase_requirements>

---

## Summary

Phase 2 configures the three infrastructure services that every downstream host and every subsequent project phase depends on: DHCP address assignment, DNS resolution, and NTP time synchronization. All three services are native to IPFire 2.29 CU200 — no Pakfire installs are required. The primary configuration path is through the IPFire WUI, which generates config files in `/var/ipfire/`. The git-export challenge is understanding which generated files are safe to commit for reproducibility.

The single most important architectural decision for this phase is **disabling ISP-assigned DNS servers and selecting TLS as the DNS protocol** in the WUI before adding Cloudflare and Quad9 as upstream resolvers with their TLS hostnames. IPFire explicitly states that ISP DNS cannot be used together with TLS — this must be disabled first. Once TLS is selected globally, every configured upstream resolver must have a valid TLS hostname entry or resolution will fail.

DNSSEC validation has been on by default since Core Update 80. It does not require additional configuration — but it does require that upstream resolvers support DNSSEC. Both Cloudflare (1.1.1.1) and Quad9 (9.9.9.9) are DNSSEC-validating resolvers and the standard choice for IPFire DoT deployments.

NTP on IPFire 2.x uses the classic `ntpd` daemon (not chrony or openntpd). The WUI setting "Provide time to local network" enables serving. The DHCP NTP option field should point to the GREEN IP (192.168.1.1) so clients receive it automatically. Auto-start for all three services (dhcpd, unbound, ntpd) is handled by SysVinit at boot with no manual enable step required — it is the default behavior for native IPFire services.

**Primary recommendation:** Configure all three services through the WUI first to generate correct config files, then export the generated files to git. Do not hand-edit `/etc/unbound/forward.conf` or `dhcpd.conf` directly — they are WUI-generated and will be overwritten. Use `/var/ipfire/dhcp/dhcpd.conf.local` for any DHCP customizations beyond WUI capabilities.

---

## Standard Stack

### Core (all native to IPFire CU200 — no install required)

| Component | Version | Purpose | Config Path |
|-----------|---------|---------|------------|
| ISC DHCP (`dhcpd`) | bundled | DHCP server for GREEN (and BLUE) | `/var/ipfire/dhcp/dhcpd.conf` (WUI-generated) |
| Unbound | 1.24.2 | Recursive DNS with DNSSEC + DoT | `/etc/unbound/unbound.conf`, `/etc/unbound/forward.conf` (WUI-generated) |
| NTP daemon (`ntpd`) | 4.2.8p13+ | NTP client + server for LAN | `/var/ipfire/time/settings` (WUI-generated), `/etc/ntp.conf` |

### Supporting

| Tool | Purpose | Notes |
|------|---------|-------|
| `drill` | DNSSEC AD flag verification | Built into IPFire; use `drill -D sigok.verteiltesysteme.net` |
| `tcpdump` | DoT traffic verification on port 853 | Verify RED interface sends to port 853, not 53 |
| `unbound-control` | Unbound service management | `unbound-control status`, `unbound-control reload` |
| `/usr/sbin/dhcpd -t` | DHCP config syntax check | Run before restarting dhcpd after manual edits |
| `ntpq -p` | NTP sync verification | Shows stratum, offset, jitter for active peers |

### No Installation Required

All three services are built into IPFire CU200. No `pakfire install` commands are needed for this phase.

---

## Architecture Patterns

### Recommended File Structure (git-exportable configs)

```
/var/ipfire/dhcp/
├── dhcpd.conf          # WUI-generated — export to git (read-only reference)
├── dhcpd.conf.local    # Hand-editable customizations — primary commit target
└── fixleases           # CSV static lease entries — commit to git

/var/ipfire/time/
└── settings            # WUI-generated NTP settings — export to git

/etc/unbound/
├── unbound.conf        # WUI-generated — export to git (read-only reference)
├── forward.conf        # WUI-generated DNS upstream + TLS config — export to git
└── local.d/            # Drop-in custom config files — safe to hand-edit
    └── custom.conf     # Project-specific Unbound overrides if needed
```

**Commit strategy:** Export WUI-generated files for reproducibility documentation. The authoritative edit path for customizations is `dhcpd.conf.local` (DHCP) and `local.d/` (Unbound). These survive WUI regeneration and Core Updates.

### Pattern 1: DHCP GREEN Zone Configuration (WUI-driven)

**What:** WUI generates a complete `dhcpd.conf` with subnet block for GREEN (192.168.1.0/24). The NTP and DNS options are set in the WUI DHCP page fields.

**When to use:** Always use WUI for initial DHCP configuration. Only touch `dhcpd.conf.local` for options the WUI does not expose (e.g., custom DHCP options, vendor-specific options).

**Generated subnet block example (GREEN):**
```
# Source: WUI-generated /var/ipfire/dhcp/dhcpd.conf
subnet 192.168.1.0 netmask 255.255.255.0 { #GREEN
    range 192.168.1.100 192.168.1.200;
    option subnet-mask 255.255.255.0;
    option routers 192.168.1.1;
    option domain-name-servers 192.168.1.1;
    option ntp-servers 192.168.1.1;
    default-lease-time 86400;
    max-lease-time 86400;
} #GREEN
```

**WUI path:** Network > DHCP Server > GREEN interface settings
- Start address: 192.168.1.100
- End address: 192.168.1.200
- Default lease time: 86400 (24h recommended)
- Primary DNS: 192.168.1.1 (point to IPFire itself)
- Primary NTP: 192.168.1.1 (point to IPFire itself)
- Domain name suffix: (optional, e.g., `lan.local`)

### Pattern 2: DHCP Static Leases (`fixleases` format)

**What:** Static leases are stored as a 7-field CSV in `/var/ipfire/dhcp/fixleases`. The WUI reads this file to populate the "Current fixed leases" table. For the DHCP daemon to honor the lease, the entry must also appear in `dhcpd.conf` — which happens when you toggle Enable in the WUI.

**Critical constraint:** Setting the `enabled` field to `on` in the CSV file alone is NOT sufficient. The WUI must also write the corresponding `host` block to `dhcpd.conf`. The safest workflow when bulk-loading leases is to write the `fixleases` CSV, then toggle each entry in the WUI once to trigger `dhcpd.conf` generation.

**fixleases file format (7 fields, comma-separated):**
```
# Format: MAC,IP,hostname,enabled,nextIP,remark,interface
# Source: community.ipfire.org/t/is-it-possible-to-bulk-load-hosts-and-static-leases/9775
# Field indices: 0=MAC, 1=IP, 2=hostname, 3=enabled(on/blank), 4=nextIP, 5=remark, 6=interface
aa:bb:cc:dd:ee:01,192.168.1.10,server01,on,,,
aa:bb:cc:dd:ee:02,192.168.1.11,nas01,on,,,
```

**Rules:**
- IP must be OUTSIDE the dynamic range (e.g., 192.168.1.10-99 for statics, 192.168.1.100-200 for dynamic)
- No blank lines or comments in the file
- Hostname (field 2) becomes a DNS entry automatically
- After writing the file, visit WUI and confirm each entry shows enabled

**Corresponding dhcpd.conf host block (WUI-generated):**
```
host server01 {
    hardware ethernet aa:bb:cc:dd:ee:01;
    fixed-address 192.168.1.10;
}
```

### Pattern 3: DNS-over-TLS Configuration (WUI-driven)

**What:** The WUI `Network > DNS Servers` page controls the upstream resolver list and protocol. Selecting "TLS" as the protocol causes Unbound to use `forward-tls-upstream: yes` with `@853#hostname` entries in `forward.conf`.

**Critical sequence:**
1. **Disable ISP DNS servers first** — ISP DNS and TLS are mutually exclusive in IPFire. Checkbox is on the DNS Servers page.
2. **Add Cloudflare:** IP=1.1.1.1, TLS Hostname=`1dot1dot1dot1.cloudflare-dns.com`
3. **Add Cloudflare secondary:** IP=1.0.0.1, TLS Hostname=`1dot1dot1dot1.cloudflare-dns.com`
4. **Add Quad9:** IP=9.9.9.9, TLS Hostname=`dns.quad9.net`
5. **Add Quad9 secondary:** IP=149.112.112.112, TLS Hostname=`dns.quad9.net`
6. **Select Protocol: TLS** (applies globally to all configured upstream resolvers)
7. Click "Check DNS Servers" — all entries must show Status: OK before proceeding

**Generated `/etc/unbound/forward.conf` (WUI-generated, do not hand-edit):**
```
# Source: Verified from community.ipfire.org/t/indicator-that-dot-is-active-is-missing/10084
forward-zone:
    name: "."
    forward-tls-upstream: yes
    forward-addr: 1.1.1.1@853#1dot1dot1dot1.cloudflare-dns.com
    forward-addr: 1.0.0.1@853#1dot1dot1dot1.cloudflare-dns.com
    forward-addr: 9.9.9.9@853#dns.quad9.net
    forward-addr: 149.112.112.112@853#dns.quad9.net
```

**DNSSEC:** Enabled by default since CU80. The `val-permissive-mode` setting in `unbound.conf` controls whether DNSSEC failures return SERVFAIL (strict, default) or are logged-only (permissive). Keep default (strict) for production.

### Pattern 4: NTP Configuration (WUI-driven)

**What:** WUI `Services > Time Server` controls upstream pool servers and the "Provide time to local network" toggle. The DHCP NTP option passes IPFire's GREEN IP to clients automatically.

**WUI settings:**
- Primary NTP: `0.pool.ntp.org`
- Secondary NTP: `1.pool.ntp.org`
- Synchronization: Daily (recommended, not Manual)
- Enable "Provide time to local network": YES
- Enable "Force clock setting on boot": YES (recommended)

**DHCP NTP linkage:** In the DHCP Server WUI, set "Primary NTP Server" to `192.168.1.1` so all GREEN clients receive IPFire as their NTP source via DHCP option 42.

**Config files:**
- `/var/ipfire/time/settings` — WUI-generated settings store (commit to git)
- `/etc/ntp.conf` — Runtime ntpd config generated from settings file

**Service control:**
```bash
/etc/init.d/ntp stop
/etc/init.d/ntp start
```

### Pattern 5: Service Auto-Start (SVC-06)

**What:** IPFire 2.x uses SysVinit. All native services (dhcpd, unbound, ntpd) are registered at boot automatically. No `systemctl enable` equivalent is needed — boot persistence is the default for IPFire core services.

**Verification of auto-start registration:**
```bash
ls /etc/rc.d/rc3.d/ | grep -E "dhcp|unbound|ntp"
# Expected: S??dhcp, S??unbound, S??ntp (S prefix = start at runlevel 3)
```

### Anti-Patterns to Avoid

- **Hand-editing `/etc/unbound/forward.conf` directly:** WUI overwrites it when DNS settings are saved. Use WUI for upstream resolver config.
- **Hand-editing `/var/ipfire/dhcp/dhcpd.conf` directly:** Same issue. Use `dhcpd.conf.local` for custom options.
- **Setting fixleases `enabled` field to `on` without WUI toggle:** The lease will appear enabled in WUI but no `host` block will be in `dhcpd.conf`. Clients won't get the fixed address.
- **Adding ISP DNS servers with TLS enabled:** IPFire blocks this combination. ISP DNS must be disabled before TLS protocol is selected.
- **Using `ntpq -p` to verify NTP when openntpd is running:** IPFire uses classic `ntpd`, so `ntpq -p` is the correct tool. If queries time out, check that `ntpd` is running (not openntpd).
- **Setting DHCP NTP option without enabling "Provide time to local network":** IPFire WUI will show a WARNING about this inconsistency. Enable the NTP server before advertising it via DHCP.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| DNSSEC validation | Custom validation scripts | Unbound native (default since CU80) | Unbound handles DNSSEC chain-of-trust natively; it's already on |
| DNS-over-TLS | Manual Unbound config edit | WUI Protocol: TLS selection | WUI generates correct `forward-tls-upstream: yes` with hostname pinning |
| DHCP static leases | Custom dhcpd.conf host blocks | WUI fixed leases + `fixleases` CSV | WUI maintains two-file consistency; manual edits create invisible inconsistencies |
| NTP client-serving | Custom ntpd configuration | WUI "Provide time to local network" | Single toggle handles all required ntpd config changes |
| Service restart after config | Custom systemd units | `/etc/init.d/{dhcp,unbound,ntp}` | IPFire is SysVinit; these scripts are the correct management interface |

**Key insight:** All three services are fully managed by the WUI. The value of this phase is in the verification and git-export steps, not in manual configuration. Let IPFire generate the files, then capture them.

---

## Common Pitfalls

### Pitfall 1: ISP DNS + TLS Conflict
**What goes wrong:** User adds Cloudflare with TLS hostname and selects TLS protocol, but ISP DNS is still enabled. DNS resolution breaks silently or the Check DNS Servers button shows errors.
**Why it happens:** IPFire enforces mutual exclusivity — ISP-assigned DNS (from PPP/DHCP) and TLS protocol cannot coexist.
**How to avoid:** Explicitly disable ISP DNS servers in the DNS Servers WUI page BEFORE selecting TLS as the protocol.
**Warning signs:** DNS Status shows "Broken" after enabling TLS. `unbound-control status` shows configuration errors.

### Pitfall 2: fixleases CSV Without dhcpd.conf Host Block
**What goes wrong:** Static leases written to `/var/ipfire/dhcp/fixleases` with `enabled=on` do not take effect. Clients continue to get dynamic IPs.
**Why it happens:** IPFire uses two files: `fixleases` (UI data store) and `dhcpd.conf` (daemon config). Writing `fixleases` only updates the display, not the daemon. IPFire does NOT validate consistency between the two files.
**How to avoid:** After writing `fixleases`, open the WUI DHCP page and toggle each entry off then on. This forces WUI to write the `host` block to `dhcpd.conf`.
**Warning signs:** Client appears in the WUI fixed leases table with "enabled" checked, but still gets a dynamic IP. Check `dhcpd.conf` for the `host` block — if it's absent, the WUI sync didn't happen.

### Pitfall 3: DHCP NTP Warning Without NTP Server Enabled
**What goes wrong:** IPFire WUI shows `WARNING DHCP on GREEN/BLUE: Local NTP server specified but not enabled` in system logs. DHCP still works, but the NTP option advertised to clients points to an IPFire address that isn't listening on port 123.
**Why it happens:** The DHCP NTP field and the NTP "Provide time to local network" toggle are independent. Setting the DHCP field without enabling the NTP server creates an inconsistency.
**How to avoid:** Enable "Provide time to local network" in Services > Time Server BEFORE setting the DHCP NTP option.
**Warning signs:** Warning message in WUI or `/var/log/messages`. Clients receive NTP option via DHCP but can't sync (port 123 refused).

### Pitfall 4: DoT Not Actually Active Despite TLS Selected in WUI
**What goes wrong:** WUI shows TLS selected and DNS resolves, but `tcpdump` on RED shows port 53 traffic instead of port 853.
**Why it happens:** If TLS hostname is missing or wrong for a configured server, Unbound may fall back to UDP/TCP. If the Check DNS Servers button shows an error, TLS for that server is not working.
**How to avoid:** Use `tcpdump -i red0 -n port 53` to confirm NO upstream traffic on port 53 after enabling TLS. Also run `tcpdump -i red0 -n port 853` to confirm encrypted traffic IS flowing.
**Warning signs:** `kdig -d @9.9.9.9 +tls-ca=/etc/ssl/certs/ca-bundle.crt +tls-host=dns.quad9.net example.com` returns SSL error. `/etc/unbound/forward.conf` lacks the `#hostname` suffix on forward-addr entries.

### Pitfall 5: Outgoing Firewall Policy Blocking NTP (Port 123) or DoT (Port 853)
**What goes wrong:** After enabling "Outgoing Blocked" or strict outgoing firewall rules in a later phase, NTP sync stops working and DoT fails. IPFire's own services are subject to the outgoing firewall policy.
**Why it happens:** IPFire applies outgoing firewall rules to traffic originating from the firewall itself, not just traffic transiting through it. NTP (UDP 123) and DNS-over-TLS (TCP 853) must be explicitly allowed if outgoing is blocked.
**How to avoid:** This phase does NOT enable "Outgoing Blocked" — that is a later hardening step. Document that Phase 6 hardening must add explicit allow rules for port 123/UDP and 853/TCP from IPFire's RED interface before enabling outbound blocking.
**Warning signs:** This pitfall is latent in Phase 2. It becomes visible in Phase 6 when outgoing rules are tightened.

### Pitfall 6: DHCP Dynamic Range Overlap With Static IPs
**What goes wrong:** A static lease IP falls within the dynamic range. DHCP may hand out the static IP to a different client, causing IP conflicts.
**Why it happens:** IPFire does not validate that static lease IPs are outside the dynamic range.
**How to avoid:** Design ranges deliberately: reserve 192.168.1.2-99 for static assignments, use 192.168.1.100-200 for dynamic pool.
**Warning signs:** Two devices claim the same IP. `arp -n` shows duplicate MACs for one IP. DHCP log shows `DHCPNAK` responses.

---

## Code Examples

### Verify DNSSEC AD Flag

```bash
# Source: community.ipfire.org/t/test-for-dnssec-and-dns-over-tls-dot-via-command-line/1500
# Run on IPFire console or from a GREEN host

# Test DNSSEC validation working (expect 'ad' flag in response)
drill -D sigok.verteiltesysteme.net
# Look for: flags: qr rd ra ad

# Test DNSSEC enforcement (expect SERVFAIL if properly enforced)
drill -D sigfail.verteiltesysteme.net
# Look for: status: SERVFAIL
```

### Verify DNS-over-TLS Traffic on RED Interface

```bash
# Source: community.ipfire.org/t/indicator-that-dot-is-active-is-missing-in-dns-configuration/10084
# Run on IPFire console as root

# Confirm DoT traffic IS flowing on port 853
tcpdump -i red0 -n port 853

# Confirm NO plaintext DNS on port 53 to upstream resolvers
tcpdump -i red0 -n port 53

# Manual kdig verification (IPFire has kdig via unbound-utils)
kdig -d @9.9.9.9 +dnssec +tls-ca=/etc/ssl/certs/ca-bundle.crt +tls-host=dns.quad9.net example.com
```

### Verify forward.conf Reflects TLS Configuration

```bash
# Source: /etc/unbound/forward.conf (WUI-generated)
# After saving TLS settings in WUI, confirm format:
cat /etc/unbound/forward.conf
# Expected output includes entries like:
#   forward-tls-upstream: yes
#   forward-addr: 1.1.1.1@853#1dot1dot1dot1.cloudflare-dns.com
#   forward-addr: 9.9.9.9@853#dns.quad9.net
# If @853#hostname suffix is absent, TLS is NOT configured correctly
```

### Verify NTP Sync and Client Serving

```bash
# Source: /etc/init.d/ntp, IPFire community forum
# Check ntpd is synchronized
ntpq -p
# Look for: * prefix on a row = synchronized source
# 'stratum' should be 1-3 for good upstream servers

# Verify NTP is listening on port 123 (serving clients)
ss -ulnp | grep :123
# Expected: UNCONN 0 0 *:123 — means ntpd is listening

# Check ntpd service status
/etc/init.d/ntp status

# From a GREEN client, verify NTP sync to IPFire
ntpdate -q 192.168.1.1
# Expected: 'adjust time...' output with small offset (< 1 second)
```

### Validate DHCP Config Syntax Before Restart

```bash
# Source: ipfire.org/docs/configuration/network/dhcp
/usr/sbin/dhcpd -t -cf /var/ipfire/dhcp/dhcpd.conf
# Exit code 0 = valid. Any other output indicates syntax error.
```

### Check Service Auto-Start Registration

```bash
# Source: IPFire SysVinit architecture (init system is SysVinit in 2.x)
ls /etc/rc.d/rc3.d/ | grep -E "S.*dhcp|S.*unbound|S.*ntp"
# Expected: entries like S10unbound, S20dhcp, S30ntp (names may vary)
# Presence of S-prefixed symlinks confirms auto-start at boot
```

### Export Configs to Git Repository

```bash
# After WUI configuration is complete, export generated files to repo
# Run on IPFire console

REPO=/root/firewall-repo  # adjust to actual repo path

# DHCP
cp /var/ipfire/dhcp/dhcpd.conf "$REPO/configs/dhcp/dhcpd.conf"
cp /var/ipfire/dhcp/dhcpd.conf.local "$REPO/configs/dhcp/dhcpd.conf.local"
cp /var/ipfire/dhcp/fixleases "$REPO/configs/dhcp/fixleases"

# DNS
cp /etc/unbound/unbound.conf "$REPO/configs/dns/unbound.conf"
cp /etc/unbound/forward.conf "$REPO/configs/dns/forward.conf"

# NTP
cp /var/ipfire/time/settings "$REPO/configs/ntp/time-settings"
cp /etc/ntp.conf "$REPO/configs/ntp/ntp.conf"
```

---

## What's Pre-Configured on a Fresh IPFire Install vs. What Needs Manual Setup

| Service | Fresh Install State | What Phase 2 Must Do |
|---------|--------------------|--------------------|
| DHCP (GREEN) | Enabled with default range (often 192.168.1.100-200). Gateway and DNS options set to IPFire IP. NTP option may be absent. | Verify range matches project design. Set NTP DHCP option. Define static lease IP range. Add static leases. |
| DHCP (BLUE) | Enabled if BLUE zone was configured. Similar defaults. | Configure if BLUE WiFi zone is used. Set same NTP/DNS options. |
| DNSSEC | **Enabled by default** (since CU80). No configuration needed. | Verify via `drill -D sigok.verteiltesysteme.net`. |
| DNS-over-TLS | **Disabled by default.** ISP DNS is active. Protocol is UDP. | Disable ISP DNS. Add Cloudflare + Quad9 with TLS hostnames. Select TLS protocol. Verify. |
| NTP (sync) | Enabled and syncing to ipfire.pool.ntp.org. | Optionally change to pool.ntp.org or country-specific servers. Verify sync. |
| NTP (serving) | **Disabled by default** — does NOT serve to LAN. | Enable "Provide time to local network" in WUI. Set DHCP NTP option. |
| Service auto-start | **All native services auto-start via SysVinit.** No manual enable needed. | Verify after reboot as acceptance test. |

---

## Validation Architecture

> This section defines the testing approach for Phase 2 requirements.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Bash shell scripts (IPFire has no test runner — validation is operational testing) |
| Config file | `validation/validate-phase2.sh` in project git repo |
| Quick run command | `bash /root/firewall-repo/validation/validate-phase2.sh --quick` |
| Full suite command | `bash /root/firewall-repo/validation/validate-phase2.sh` |

### Phase Requirements to Test Map

| Req ID | Behavior to Verify | Test Type | Automated Command | Manual Step |
|--------|-------------------|-----------|-------------------|-------------|
| SVC-01 | GREEN client gets correct IP, gateway, DNS, NTP via DHCP | operational | Run from GREEN client: `dhclient -v green-iface` and parse output | Verify gateway=192.168.1.1, DNS=192.168.1.1, NTP=192.168.1.1 in lease |
| SVC-02 | Static lease delivers correct IP for known MAC | operational | `grep -c "hardware ethernet" /var/ipfire/dhcp/dhcpd.conf` | Plug in known-MAC device, verify IP matches fixleases entry |
| SVC-03 | DNSSEC AD flag present in responses | automated | `drill -D sigok.verteiltesysteme.net \| grep "flags.*ad"` | Check SERVFAIL for sigfail domain |
| SVC-04 | DoT traffic on port 853, no plaintext DNS to upstream | automated | `tcpdump -i red0 -n port 53 -c 10 2>&1` — zero captures = pass | Confirm `forward.conf` has `@853#hostname` entries |
| SVC-05 | NTP synced, serving clients on port 123 | automated | `ntpq -p \| grep '^\*'` (star = synced) + `ss -ulnp \| grep :123` | From GREEN client: `ntpdate -q 192.168.1.1` |
| SVC-06 | All services restart and come up after reboot | operational | After reboot: `ps aux \| grep -E 'dhcpd\|unbound\|ntpd'` | Verify all three processes running within 60s of boot |

### Wave 0 Gaps

- [ ] `validation/validate-phase2.sh` — covers all SVC-01 through SVC-06 checks above
- [ ] No framework install needed (bash only)

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| dnsmasq for DNS | Unbound 1.24.2 | CU106 (IPFire 2.19) | Full DNSSEC validation without relying on upstream; recursive resolution in fallback mode |
| DNS forwarding only | Recursive fallback if no upstreams available | CU106+ | Unbound falls back to root server queries if all configured upstreams are down |
| DNSSEC opt-in | DNSSEC on by default | CU80 (IPFire 2.15) | No configuration needed; already enforcing |
| TLS not available | DNS-over-TLS via WUI | CU141+ (2020) | Can configure DoT entirely through WUI without touching config files |
| `ntpdate` one-shot | `ntpd` daemon (continuous) | Long-standing | ntpd maintains continuous sync, not just one-shot correction |

**Deprecated/outdated patterns to avoid:**
- Forum posts from before CU106 that reference dnsmasq config — irrelevant, Unbound replaced it
- Manual `/etc/unbound/forward.conf` edits from old forum posts — WUI now manages this file; edits are overwritten
- Setting `forward-ssl-upstream: yes` (old syntax) — current IPFire uses `forward-tls-upstream: yes`

---

## Open Questions

1. **Exact fixleases field 4-7 definitions**
   - What we know: Field 0=MAC, 1=IP, 2=hostname, 3=enabled(on/blank). Community posts suggest 7 fields total.
   - What's unclear: Fields 4-6 purpose (possibly nextIP, remark, interface per community post fragments).
   - Recommendation: After WUI creates the first static lease, inspect the resulting file to confirm all 7 fields. Plan should include this as an exploratory task.

2. **BLUE zone DHCP scope**
   - What we know: BLUE is 192.168.2.1/24. DHCP on BLUE follows same pattern as GREEN.
   - What's unclear: Whether this project has wireless clients on BLUE that need DHCP configured in Phase 2.
   - Recommendation: Plan the BLUE DHCP config identically to GREEN. Add a task to enable if BLUE zone has clients.

3. **NTP outgoing firewall rules in Phase 6**
   - What we know: IPFire's outgoing firewall policy applies to traffic originating from IPFire itself. NTP (UDP 123) and DoT (TCP 853) will be blocked if "Outgoing Blocked" is enabled without exceptions.
   - What's unclear: Whether Phase 6 hardening will enable "Outgoing Blocked."
   - Recommendation: Document this dependency now. Phase 2 creates the services; Phase 6 must add explicit outgoing allow rules for ports 123/UDP and 853/TCP if tightening outgoing policy.

---

## Sources

### Primary (HIGH confidence)

- [IPFire DHCP Server Documentation](https://www.ipfire.org/docs/configuration/network/dhcp) — config file paths, subnet format, NTP/DNS options, static lease workflow, `dhcpd.conf.local` extension pattern
- [IPFire DNS Server Documentation](https://www.ipfire.org/docs/configuration/network/dns-server) — TLS hostname field requirements, DNSSEC by default, protocol selection (UDP/TCP/TLS), ISP DNS + TLS mutual exclusivity
- [IPFire NTP Time Server Documentation](https://www.ipfire.org/docs/configuration/services/ntp) — WUI settings, "Provide time to local network" toggle, upstream pool config
- [IPFire DNSSEC Documentation](https://www.ipfire.org/docs/dns/dnssec) — DNSSEC enabled by default since CU80, Unbound replaced dnsmasq
- [IPFire Community: DoT Indicator Missing](https://community.ipfire.org/t/indicator-that-dot-is-active-is-missing-in-dns-configuration/10084) — `/etc/unbound/forward.conf` format with `forward-tls-upstream: yes` and `@853#hostname` entries; `kdig` verification command

### Secondary (MEDIUM confidence)

- [IPFire Community: Bulk Load Static Leases](https://community.ipfire.org/t/is-it-possible-to-bulk-load-hosts-and-static-leases/9775) — fixleases CSV format, two-file consistency requirement, manual edit caveats
- [IPFire Community: fixleases DHCP Fixed IP](https://forum.ipfire.org/viewtopic.php?t=22850) — confirmed 7-field CSV format, enabled flag behavior
- [IPFire Community: Test DNSSEC and DoT CLI](https://community.ipfire.org/t/test-for-dnssec-and-dns-over-tls-dot-via-command-line/1500) — `drill -D` command, AD flag verification, tcpdump port 853 approach
- [IPFire Community: Force IPFire as Time Server](https://community.ipfire.org/t/force-ipfire-as-time-server/3514) — WUI path for NTP client serving, DHCP NTP field linkage, SNTP client limitation
- [IPFire Community: NTP Update Not Working](https://community.ipfire.org/t/ntp-update-not-working-well/3338) — classic `ntpd` confirmed (not chrony/openntpd in CU200), `ntpq -p` syntax
- [IPFire Community: SysVinit Service Disable](https://community.ipfire.org/t/anyone-know-a-clean-way-to-disable-a-etc-init-d-service/4620) — confirmed SysVinit for IPFire 2.x, `/etc/init.d/` scripts, boot persistence model

### Tertiary (LOW confidence — verify on live system)

- fixleases fields 4-7 exact definition — fragments from community posts suggest nextIP/remark/interface but not authoritatively confirmed; must verify by inspecting file after WUI creates first entry
- `ntpq -p` response format on this specific IPFire install — ntpd confirmed, but actual pool server response and stratum must be observed on the live system

---

## Metadata

**Confidence breakdown:**
- DHCP (SVC-01, SVC-02): HIGH — official docs + confirmed community patterns for file format and WUI workflow
- DNS/DNSSEC (SVC-03): HIGH — DNSSEC-by-default since CU80 is official; Unbound-native validation is well-documented
- DNS-over-TLS (SVC-04): HIGH (WUI flow) / MEDIUM (exact forward.conf verification) — WUI approach confirmed; forward.conf format confirmed from community post with live system output
- NTP (SVC-05): MEDIUM — WUI settings clear; NTP daemon identity (ntpd) confirmed; exact `/var/ipfire/time/settings` file format not publicly documented
- Auto-start (SVC-06): HIGH — SysVinit confirmed for IPFire 2.x; native services auto-start by design

**Research date:** 2026-03-22
**Valid until:** 2026-06-22 (stable IPFire features — 90 days)
