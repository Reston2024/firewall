# Rollback Procedures — IPFire Firewall Appliance

## Overview

Before any config change, the deploy script copies the current live file to `/root/rollback/{category}-{timestamp}.bak`. Rollback means copying the `.bak` file back to the original location and reloading the service.

**Strategy (per D-07 and D-10):**
- Config-file rollback at full-category granularity — not snapshot-based, not individual-rule-level
- One backup per category per deploy operation
- Backup-before-deploy pattern: backup first, then overwrite
- Scripts are optional automation — this README is sufficient for manual recovery without the scripts

## Prerequisites

- SSH access to IPFire: `ssh -i ~/.ssh/ipfire_ed25519 root@192.168.1.1`
- Backup files must exist in `/root/rollback/` (created automatically by deploy scripts)
- List all available backups: `ls -lt /root/rollback/`

---

## Step-by-Step Manual Recovery Procedures

---

### 1. Firewall Rules

**What it covers:** `/etc/sysconfig/firewall.local`

**Backup location:** `/root/rollback/firewall-YYYYMMDD-HHMMSS.bak`

**Automated rollback (using script):**
```bash
# List available backups
bash /root/firewall-repo/rollback/rollback-firewall.sh

# Restore from specific backup
bash /root/firewall-repo/rollback/rollback-firewall.sh /root/rollback/firewall-YYYYMMDD-HHMMSS.bak
```

**Manual rollback (step-by-step, no script):**
```bash
# Step 1: List available backups
ls -lt /root/rollback/firewall-*.bak

# Step 2: Restore the config
cp /root/rollback/firewall-YYYYMMDD-HHMMSS.bak /etc/sysconfig/firewall.local

# Step 3: Reload the firewall
/etc/init.d/firewall restart

# Step 4: Verify rules loaded
iptables -L CUSTOMINPUT -n
```

---

### 2. Suricata/IDS Config

**What it covers:** `/etc/suricata/suricata.yaml`

**Backup location:** `/root/rollback/suricata-YYYYMMDD-HHMMSS.bak`

**Automated rollback (using script):**
```bash
# List available backups
bash /root/firewall-repo/rollback/rollback-suricata.sh

# Restore from specific backup
bash /root/firewall-repo/rollback/rollback-suricata.sh /root/rollback/suricata-YYYYMMDD-HHMMSS.bak
```

**Manual rollback (step-by-step, no script):**
```bash
# Step 1: List available backups
ls -lt /root/rollback/suricata-*.bak

# Step 2: Restore the config
cp /root/rollback/suricata-YYYYMMDD-HHMMSS.bak /etc/suricata/suricata.yaml

# Step 3: Restart Suricata
/etc/init.d/suricata restart

# Step 4: Verify Suricata running
suricata --build-info | head -1
```

---

### 3. DNS Config

**What it covers:** `/etc/unbound/forward.conf`

**Backup location:** `/root/rollback/dns-YYYYMMDD-HHMMSS.bak`

**Automated rollback (using script):**
```bash
# List available backups
bash /root/firewall-repo/rollback/rollback-dns.sh

# Restore from specific backup
bash /root/firewall-repo/rollback/rollback-dns.sh /root/rollback/dns-YYYYMMDD-HHMMSS.bak
```

**Manual rollback (step-by-step, no script):**
```bash
# Step 1: List available backups
ls -lt /root/rollback/dns-*.bak

# Step 2: Restore the config
cp /root/rollback/dns-YYYYMMDD-HHMMSS.bak /etc/unbound/forward.conf

# Step 3: Restart Unbound
/etc/init.d/unbound restart

# Step 4: Verify DNS resolving
dig +short example.com @127.0.0.1
```

**Note on ISP DNS:** IPFire enforces mutual exclusivity between ISP DNS and DNS-over-TLS. If the WUI DNS settings are affected, reconfigure via WUI > Network > DNS Settings.

---

### 4. DHCP Config

**What it covers:** `/var/ipfire/dhcp/dhcpd.conf.local`

**Backup location:** `/root/rollback/dhcp-YYYYMMDD-HHMMSS.bak`

**Automated rollback (using script):**
```bash
# List available backups
bash /root/firewall-repo/rollback/rollback-dhcp.sh

# Restore from specific backup
bash /root/firewall-repo/rollback/rollback-dhcp.sh /root/rollback/dhcp-YYYYMMDD-HHMMSS.bak
```

**Manual rollback (step-by-step, no script):**
```bash
# Step 1: List available backups
ls -lt /root/rollback/dhcp-*.bak

# Step 2: Restore the config
cp /root/rollback/dhcp-YYYYMMDD-HHMMSS.bak /var/ipfire/dhcp/dhcpd.conf.local

# Step 3: Restart DHCP server
/etc/init.d/dhcpd restart

# Step 4: Verify service running
/etc/init.d/dhcpd status
```

---

### 5. Zone/NIC Config

**What it covers:**
- `/etc/udev/rules.d/30-persistent-network.rules` (NIC persistence rules)
- `/var/ipfire/ethernet/settings` (zone assignments)

**Backup location:**
- `/root/rollback/zone-YYYYMMDD-HHMMSS.bak`
- `/root/rollback/ethernet-YYYYMMDD-HHMMSS.bak` (if present)

**Automated rollback (using script):**
```bash
# List available backups
bash /root/firewall-repo/rollback/rollback-zone.sh

# Restore from specific backup (also auto-restores ethernet settings if timestamp matches)
bash /root/firewall-repo/rollback/rollback-zone.sh /root/rollback/zone-YYYYMMDD-HHMMSS.bak
```

**Manual rollback (step-by-step, no script):**
```bash
# Step 1: List available backups
ls -lt /root/rollback/zone-*.bak
ls -lt /root/rollback/ethernet-*.bak

# Step 2: Restore the udev rules
cp /root/rollback/zone-YYYYMMDD-HHMMSS.bak /etc/udev/rules.d/30-persistent-network.rules

# Step 3: Restore ethernet settings (if backup exists)
cp /root/rollback/ethernet-YYYYMMDD-HHMMSS.bak /var/ipfire/ethernet/settings

# Step 4: Reboot for changes to take full effect
reboot

# Step 5: Verify after reboot
ip link show
```

**WARNING: Zone/NIC changes require a REBOOT to take full effect.** `udevadm trigger` may work for hotplug devices, but reboot is the safe path and must be used to ensure IPFire zone assignments are properly applied.

---

### 6. Kernel Parameters (Sysctl)

**What it covers:** `/etc/sysctl.conf`

**Backup location:** `/root/rollback/sysctl-YYYYMMDD-HHMMSS.bak`

**Automated rollback (using script):**
```bash
# List available backups
bash /root/firewall-repo/rollback/rollback-sysctl.sh

# Restore from specific backup
bash /root/firewall-repo/rollback/rollback-sysctl.sh /root/rollback/sysctl-YYYYMMDD-HHMMSS.bak
```

**Manual rollback (step-by-step, no script):**
```bash
# Step 1: List available backups
ls -lt /root/rollback/sysctl-*.bak

# Step 2: Restore the config
cp /root/rollback/sysctl-YYYYMMDD-HHMMSS.bak /etc/sysctl.conf

# Step 3: Apply kernel parameters
sysctl -p

# Step 4: Verify ip_forward (CRITICAL)
sysctl net.ipv4.ip_forward
```

**WARNING: After restore, verify `sysctl net.ipv4.ip_forward` returns 1. If 0, WAN routing is broken — set it immediately:**
```bash
sysctl -w net.ipv4.ip_forward=1
```

---

### 7. Syslog Config

**What it covers:** `/etc/syslog.conf`

**Backup location:** `/root/rollback/syslog-YYYYMMDD-HHMMSS.bak`

**Automated rollback (using script):**
```bash
# List available backups
bash /root/firewall-repo/rollback/rollback-syslog.sh

# Restore from specific backup
bash /root/firewall-repo/rollback/rollback-syslog.sh /root/rollback/syslog-YYYYMMDD-HHMMSS.bak
```

**Manual rollback (step-by-step, no script):**
```bash
# Step 1: List available backups
ls -lt /root/rollback/syslog-*.bak

# Step 2: Restore the config
cp /root/rollback/syslog-YYYYMMDD-HHMMSS.bak /etc/syslog.conf

# Step 3: Restart syslog daemon
/etc/init.d/sysklogd restart

# Step 4: Verify logs flowing
tail -5 /var/log/messages
```

**Note on syslog port persistence:** IPFire syslog forwards to remote hosts via UDP. Non-standard port settings in `/etc/syslog.conf` may revert on service restarts — verify the forwarding destination after restore.

---

## Additional Notes

### SSH / sshd_config

`sshd_config` is managed by IPFire's `sshctrl` binary via the WUI. **Do not rollback sshd_config by manually restoring a backup** — the `sshctrl` binary overwrites direct edits when WUI SSH settings are saved.

To rollback SSH settings: use **WUI > System > SSH Access**. No script-based rollback for SSH.

### Guardian (Brute Force Protection)

Guardian config is WUI-managed (`/var/ipfire/guardian/guardian.conf`). To rollback Guardian settings, use **WUI > Firewall > Guardian**. No script-based rollback.

---

## Quick Reference

| Category | Config File | Reload Command | Verify |
|----------|-------------|----------------|--------|
| Firewall | /etc/sysconfig/firewall.local | `/etc/init.d/firewall restart` | `iptables -L CUSTOMINPUT -n` |
| Suricata | /etc/suricata/suricata.yaml | `/etc/init.d/suricata restart` | `suricata --build-info \| head -1` |
| DNS | /etc/unbound/forward.conf | `/etc/init.d/unbound restart` | `dig +short example.com @127.0.0.1` |
| DHCP | /var/ipfire/dhcp/dhcpd.conf.local | `/etc/init.d/dhcpd restart` | `/etc/init.d/dhcpd status` |
| Zone/NIC | /etc/udev/rules.d/30-persistent-network.rules | `reboot` | `ip link show` |
| Sysctl | /etc/sysctl.conf | `sysctl -p` | `sysctl net.ipv4.ip_forward` |
| Syslog | /etc/syslog.conf | `/etc/init.d/sysklogd restart` | `tail -5 /var/log/messages` |
