# DNS Configuration

IPFire uses Unbound 1.24.2 for DNS resolution with DNSSEC enabled by default since Core Update 80.

## File Roles

| File | Role | Deploy to IPFire? |
|------|------|-------------------|
| `/etc/unbound/unbound.conf` | Main Unbound config (WUI-generated) | No — export only |
| `/etc/unbound/forward.conf` | Upstream resolver list + DoT config (WUI-generated) | No — export only |
| `/etc/unbound/local.d/*.conf` | Drop-in custom config (hand-editable) | Yes — safe to deploy |

## DNS-over-TLS Setup (WUI)

WUI path: Network > DNS Servers

Critical ordering (wrong order breaks DNS):
1. **Disable ISP DNS servers** — checkbox on DNS Servers page (MUST be first)
2. Add Cloudflare: IP=1.1.1.1, TLS Hostname=`1dot1dot1dot1.cloudflare-dns.com`
3. Add Cloudflare secondary: IP=1.0.0.1, TLS Hostname=`1dot1dot1dot1.cloudflare-dns.com`
4. Add Quad9: IP=9.9.9.9, TLS Hostname=`dns.quad9.net`
5. Add Quad9 secondary: IP=149.112.112.112, TLS Hostname=`dns.quad9.net`
6. Select Protocol: **TLS**
7. Click **Check DNS Servers** — all entries must show Status: OK

## Verification Commands (run on IPFire)

```bash
# Verify DoT config in forward.conf
grep "forward-tls-upstream: yes" /etc/unbound/forward.conf
grep "@853#" /etc/unbound/forward.conf

# Verify DNSSEC validation (AD flag must be present)
drill -D sigok.verteiltesysteme.net
# Look for: flags: qr rd ra ad

# Verify DNSSEC enforcement (SERVFAIL for invalid DNSSEC)
drill -D sigfail.verteiltesysteme.net
# Look for: status: SERVFAIL

# Verify DoT wire traffic (run on IPFire, trigger a DNS lookup first)
tcpdump -i red0 -n port 853 -c 5      # Should show packets
tcpdump -i red0 -n port 53 -c 5       # Should show NO packets to upstream
```

## Export After WUI Configuration

```bash
scp root@192.168.1.1:/etc/unbound/forward.conf configs/dns/forward.conf
scp root@192.168.1.1:/etc/unbound/unbound.conf configs/dns/unbound.conf
git add configs/dns/forward.conf configs/dns/unbound.conf
git commit -m "chore(02): export DNS configs after WUI setup"
```

## Phase 6 Note

If Phase 6 enables outgoing firewall blocking, add an explicit allow rule for TCP port 853
from IPFire's RED interface. Otherwise DNS-over-TLS will be silently blocked.
