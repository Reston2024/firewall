# Phase 2 Services Runbook — DHCP, DNS, NTP

Human-executable WUI steps for configuring core network services on IPFire 2.29 CU200.
Complete sections in ORDER — NTP must be enabled before DHCP NTP option is set.

**IPFire WUI:** https://192.168.1.1:444
**IPFire SSH:** ssh root@192.168.1.1 (port 22)

---

## Section 1: NTP — Enable Time Server (Do This First)

WUI path: **Services > Time Server**

NTP must be enabled BEFORE setting the DHCP NTP option. Reversed order causes a
WARNING log: "Local NTP server specified but not enabled."

- [ ] Set **Primary NTP Server**: `0.pool.ntp.org`
- [ ] Set **Secondary NTP Server**: `1.pool.ntp.org`
- [ ] Set **Synchronization**: `Daily`
- [ ] Check **"Provide time to local network"**: YES (this enables ntpd to serve clients)
- [ ] Check **"Force clock setting on boot"**: YES
- [ ] Click **Save**

**Verify NTP is serving:**
```bash
ssh root@192.168.1.1 'ntpq -p'
# Look for a row starting with * (synchronized source)
ssh root@192.168.1.1 'ss -ulnp | grep :123'
# Expected: UNCONN 0 0 *:123
```

---

## Section 2: DHCP — Configure GREEN Zone

WUI path: **Network > DHCP Server**

- [ ] Select interface: **GREEN**
- [ ] Check **"Enable DHCP"**: YES
- [ ] Set **Start address**: `192.168.1.100`
- [ ] Set **End address**: `192.168.1.200`
- [ ] Set **Default lease time**: `86400`
- [ ] Set **Max lease time**: `86400`
- [ ] Set **Primary DNS**: `192.168.1.1`
- [ ] Set **Primary NTP Server**: `192.168.1.1`
- [ ] Set **Default gateway**: `192.168.1.1` (if shown — may auto-populate)
- [ ] Click **Save**

**Verify DHCP options in config:**
```bash
ssh root@192.168.1.1 'grep -E "ntp-servers|domain-name-servers|routers" /var/ipfire/dhcp/dhcpd.conf'
# All three must show 192.168.1.1
```

### Section 2a: Static Leases (Optional — Add Known Hosts)

WUI path: **Network > DHCP Server > Fixed Leases** (scroll down)

For each known host to assign a static IP:

- [ ] Edit `configs/dhcp/fixleases.template` — add real MAC addresses and IPs
      IP addresses must be in range 192.168.1.2 to 192.168.1.99 (outside dynamic pool)
- [ ] Remove the comment header lines (lines starting with #) to create the real `fixleases` file
- [ ] Deploy the file:
      ```bash
      scp configs/dhcp/fixleases root@192.168.1.1:/var/ipfire/dhcp/fixleases
      ssh root@192.168.1.1 'sed -i "s/\r$//" /var/ipfire/dhcp/fixleases'
      ```
- [ ] Refresh the WUI DHCP page — static lease entries should appear in the Fixed Leases table
- [ ] For EACH entry in the table: toggle **Enable** off, then back on
      This forces WUI to write the `host` block to `dhcpd.conf` — the daemon will NOT
      assign static IPs without this step.
- [ ] Restart DHCP: `ssh root@192.168.1.1 '/etc/init.d/dhcp restart'`
- [ ] Verify host blocks exist:
      ```bash
      ssh root@192.168.1.1 'grep "hardware ethernet" /var/ipfire/dhcp/dhcpd.conf'
      # Must show one host block per static lease
      ```

---

## Section 3: DNS — Configure DNS-over-TLS

WUI path: **Network > DNS Servers**

**CRITICAL ORDER:** Steps 1-2 MUST happen before Step 3. Adding TLS while ISP DNS is
still active will cause DNS resolution to break.

- [ ] **Step 1 — Disable ISP DNS servers:** Uncheck "Use ISP-assigned DNS servers"
      (or equivalent checkbox labeled "Use DNS servers assigned by DHCP/PPP")
- [ ] **Step 2 — Remove any existing ISP DNS entries** from the server list

- [ ] **Step 3 — Add Cloudflare primary:**
      - IP: `1.1.1.1`
      - TLS Hostname: `1dot1dot1dot1.cloudflare-dns.com`

- [ ] **Add Cloudflare secondary:**
      - IP: `1.0.0.1`
      - TLS Hostname: `1dot1dot1dot1.cloudflare-dns.com`

- [ ] **Add Quad9 primary:**
      - IP: `9.9.9.9`
      - TLS Hostname: `dns.quad9.net`

- [ ] **Add Quad9 secondary:**
      - IP: `149.112.112.112`
      - TLS Hostname: `dns.quad9.net`

- [ ] **Select Protocol: TLS** (applies globally to all configured upstream resolvers)

- [ ] Click **"Check DNS Servers"** — ALL entries must show **Status: OK**
      If any show an error, TLS is NOT working for that resolver. Do not proceed until all pass.

- [ ] Click **Save**

**Verify DoT is active:**
```bash
# Confirm TLS config in forward.conf
ssh root@192.168.1.1 'grep "forward-tls-upstream: yes" /etc/unbound/forward.conf'
ssh root@192.168.1.1 'grep "@853#" /etc/unbound/forward.conf'
# Compare to configs/dns/forward.conf.template — should match

# Confirm DNSSEC validation (AD flag)
ssh root@192.168.1.1 'drill -D sigok.verteiltesysteme.net | grep "flags"'
# Must include 'ad' in flags

# Confirm DNSSEC enforcement (SERVFAIL on bad DNSSEC)
ssh root@192.168.1.1 'drill -D sigfail.verteiltesysteme.net | grep "status"'
# Must show SERVFAIL

# Confirm no plaintext DNS to upstream (run after triggering a DNS lookup)
ssh root@192.168.1.1 'tcpdump -i red0 -n port 53 -c 10 -W 5 2>&1 | tail -3'
# Should capture 0 packets to upstream resolvers on port 53
```

---

## Section 4: Export Configs to Git

Run after all three services are verified. These exports make the config reproducible.

```bash
# Run on IPFire
REPO=/root/firewall-repo

# DHCP
cp /var/ipfire/dhcp/dhcpd.conf "$REPO/configs/dhcp/dhcpd.conf"
cp /var/ipfire/dhcp/fixleases "$REPO/configs/dhcp/fixleases" 2>/dev/null || true

# DNS
cp /etc/unbound/forward.conf "$REPO/configs/dns/forward.conf"
cp /etc/unbound/unbound.conf "$REPO/configs/dns/unbound.conf"

# NTP
cp /var/ipfire/time/settings "$REPO/configs/ntp/time-settings"
cp /etc/ntp.conf "$REPO/configs/ntp/ntp.conf"
```

Then on the dev machine:
```bash
# Pull the exported configs to the local repo
scp root@192.168.1.1:/root/firewall-repo/configs/dhcp/dhcpd.conf configs/dhcp/dhcpd.conf
scp root@192.168.1.1:/root/firewall-repo/configs/dns/forward.conf configs/dns/forward.conf
scp root@192.168.1.1:/root/firewall-repo/configs/dns/unbound.conf configs/dns/unbound.conf
scp root@192.168.1.1:/root/firewall-repo/configs/ntp/time-settings configs/ntp/time-settings
scp root@192.168.1.1:/root/firewall-repo/configs/ntp/ntp.conf configs/ntp/ntp.conf
git add configs/dhcp/ configs/dns/ configs/ntp/
git commit -m "chore(02): export live configs after Phase 2 WUI setup"
```

---

## Section 5: Run Phase 2 Validation Suite

Run on IPFire after completing all WUI steps:
```bash
ssh root@192.168.1.1 'bash /root/firewall-repo/scripts/validate-phase2.sh'
```

All automated checks must pass. SKIP lines are expected for manual wire-level checks.

---

## Section 6: Reboot Persistence Test

```bash
ssh root@192.168.1.1 'reboot'
# Wait 60 seconds
ssh root@192.168.1.1 'bash /root/firewall-repo/scripts/validate-phase2.sh'
```

All checks must pass after reboot. This confirms SVC-06 (auto-start).

---

## Sign-Off Criteria

Phase 2 is complete when ALL of the following are true:

- [ ] GREEN client receives IP in 192.168.1.100-200, gateway=192.168.1.1, DNS=192.168.1.1, NTP=192.168.1.1
- [ ] `drill -D sigok.verteiltesysteme.net` shows `ad` flag (DNSSEC active)
- [ ] `grep "forward-tls-upstream: yes" /etc/unbound/forward.conf` returns a match (DoT active)
- [ ] `ntpq -p` shows `*` prefix on a row (NTP synchronized)
- [ ] `ss -ulnp | grep :123` shows NTP listening (serving clients)
- [ ] `bash /root/firewall-repo/scripts/validate-phase2.sh` returns ALL CHECKS PASS
- [ ] All three services running after clean reboot
- [ ] Live configs exported and committed to git
