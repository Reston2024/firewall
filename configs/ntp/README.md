# NTP Configuration

IPFire uses classic `ntpd` (NTP daemon) for time synchronization.
`ntpq` is the correct verification tool — not `chronyc` or `timedatectl`.

## WUI Setup

WUI path: Services > Time Server

| Setting | Value | Why |
|---------|-------|-----|
| Primary NTP | `0.pool.ntp.org` | Rotating pool for geographic distribution |
| Secondary NTP | `1.pool.ntp.org` | Failover |
| Synchronization | Daily | Prevents clock drift accumulation |
| Provide time to local network | **YES** | Required for DHCP NTP option to work |
| Force clock setting on boot | YES | Ensures correct time before services start |

## Critical Ordering

Enable "Provide time to local network" BEFORE setting the NTP option in the DHCP page.
If reversed, IPFire logs a WARNING about an NTP server not being enabled for DHCP option.

## Verification Commands (run on IPFire)

```bash
# Check NTP sync status (* prefix = synchronized source)
ntpq -p
# Look for a row starting with *
# stratum 1-3 = good upstream quality

# Check NTP is listening on port 123 (serving clients)
ss -ulnp | grep :123
# Expected: UNCONN 0 0 *:123

# Check service status
/etc/init.d/ntp status

# From a GREEN client (run on client, not IPFire)
ntpdate -q 192.168.1.1
# Expected: "adjust time..." with small offset
```

## Export After WUI Configuration

```bash
scp root@192.168.1.1:/var/ipfire/time/settings configs/ntp/time-settings
scp root@192.168.1.1:/etc/ntp.conf configs/ntp/ntp.conf
git add configs/ntp/
git commit -m "chore(02): export NTP configs after WUI setup"
```

## Phase 6 Note

If Phase 6 enables outgoing firewall blocking, add an explicit allow rule for UDP port 123
from IPFire's RED interface. Otherwise NTP sync to upstream pools will be silently blocked.
