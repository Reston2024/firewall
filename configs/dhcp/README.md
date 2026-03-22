# DHCP Configuration

IPFire uses two files for DHCP configuration. Both must be consistent or static leases will not work.

## File Roles

| File | Role | Survives WUI Save? | Deploy to IPFire? |
|------|------|--------------------|-------------------|
| `/var/ipfire/dhcp/dhcpd.conf` | WUI-generated daemon config | NO (overwritten) | No — WUI generates it |
| `/var/ipfire/dhcp/dhcpd.conf.local` | Custom options, extended config | YES | Yes — deploy from repo |
| `/var/ipfire/dhcp/fixleases` | Static lease data store (7-field CSV) | YES | Yes — deploy from repo |

## Deployment Order (from Phase 2 runbook)

1. Configure GREEN DHCP pool via WUI (Network > DHCP Server)
2. Deploy `fixleases` from this repo (see fixleases.template)
3. Toggle each static lease in WUI (off then on) to generate `host` blocks in `dhcpd.conf`
4. Deploy `dhcpd.conf.local` from this repo
5. Run syntax check: `ssh root@192.168.1.1 '/usr/sbin/dhcpd -t -cf /var/ipfire/dhcp/dhcpd.conf'`
6. Restart: `ssh root@192.168.1.1 '/etc/init.d/dhcp restart'`

## IP Range Design

| Range | Purpose |
|-------|---------|
| 192.168.1.1 | IPFire GREEN (gateway) — do not assign |
| 192.168.1.2 - 192.168.1.99 | Static lease assignments (edit fixleases) |
| 192.168.1.100 - 192.168.1.200 | Dynamic DHCP pool (set in WUI) |
| 192.168.1.201 - 192.168.1.254 | Reserved for future static use |

## Two-File DHCP Consistency Model

IPFire DHCP uses a two-file model:

- **`fixleases`** is the WUI data store — it controls what appears in the DHCP Server page table
- **`dhcpd.conf`** is the daemon config — it must contain `host` blocks for the daemon to honor static IPs

Writing `fixleases` alone does NOT make static leases active. The WUI must generate the `host` block in `dhcpd.conf`. This happens only when you toggle each entry in the WUI (disable then enable).

**Warning signs of inconsistency:** Client appears in WUI fixed leases table as enabled but still gets a dynamic IP. Check `grep "hardware ethernet" /var/ipfire/dhcp/dhcpd.conf` — if the block is absent, the WUI sync did not happen.

## After Any WUI DHCP Change

Export the regenerated config back to the repo for reproducibility:

```bash
scp root@192.168.1.1:/var/ipfire/dhcp/dhcpd.conf configs/dhcp/dhcpd.conf
scp root@192.168.1.1:/var/ipfire/dhcp/fixleases configs/dhcp/fixleases
```
