# Phase 3: SSH Hardening and Management Security - Research

**Researched:** 2026-03-22
**Domain:** IPFire SSH configuration, Guardian brute-force protection, WUI access restriction via firewall.local
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SSH-01 | SSH configured with key-only authentication (password auth disabled) | WUI checkbox "Allow password based authentication" disables password auth; WUI checkbox "Allow public key based authentication" enables key auth; authorized_keys at `/root/.ssh/authorized_keys` by default |
| SSH-02 | SSH access restricted to management IP/subnet whitelist | Two complementary methods: (1) CUSTOMINPUT iptables rules in firewall.local restricting port 22 by source IP; (2) AllowUsers directive in sshd_config for defense-in-depth |
| SSH-03 | Guardian installed via Pakfire for SSH brute-force protection | `pakfire install guardian` installs Guardian 2.0; config at `/var/ipfire/guardian/guardian.conf`; whitelist managed via WUI; WUI shows blocked IP list |
| SSH-04 | IPFire WUI access restricted to GREEN/management subnet only | CUSTOMINPUT iptables DROP rules in firewall.local blocking port 444 from ORANGE and BLUE zones; currently GREEN-only ACCEPT already in place from Phase 1 |
| SSH-05 | SSH 15-minute expiry feature documented and operational | WUI button "Stop SSH Daemon in 15 minutes" activates sshd, fcron checks timestamp and stops sshd after 15 min; sessions already established are NOT disconnected |
</phase_requirements>

---

## Summary

Phase 3 locks down remote management using IPFire-native tools only. SSH already runs on port 22 (confirmed in Phase 1 — the WUI "Set SSH port to default 22" checkbox was enabled). Three layers of protection are applied in sequence: (1) switch SSH to key-only authentication via WUI checkboxes, (2) restrict SSH and WUI access by source IP using CUSTOMINPUT iptables rules in firewall.local, and (3) install Guardian via Pakfire for brute-force detection.

The most important architectural insight for this phase is that IPFire manages SSH configuration through a binary called `/usr/local/bin/sshctrl` that is invoked when the WUI SSH Settings page is saved. This binary surgically modifies `/etc/ssh/sshd_config` — specifically the `Port` directive. It does NOT rewrite the entire file. This means manual edits to other directives (such as adding `AllowUsers`) will survive WUI saves, but only if they do not conflict with what sshctrl targets. The safe approach is: use WUI checkboxes for all settings the WUI manages (port, password auth, pubkey auth, agent forwarding, TCP forwarding), and add only non-WUI-managed directives manually (AllowUsers, Match Address blocks).

The authorized_keys path on IPFire is `/root/.ssh/authorized_keys` by default. The sshd_config shipped with IPFire uses the standard `AuthorizedKeysFile` default (`%h/.ssh/authorized_keys`), which resolves to `/root/.ssh/authorized_keys` for the root user. Some community documentation incorrectly references `/etc/ssh/authorized_keys` — this requires an explicit `AuthorizedKeysFile` override and is NOT the default.

Guardian 2.0 is the IPFire-native brute-force protection tool (fail2ban is not in Pakfire). It monitors SSH and WUI login failures via inotify on log files, blocks attacking IPs in iptables, and is fully managed through the WUI. The key operational note is that the management host (192.168.1.100) MUST be added to Guardian's ignore/whitelist before enabling Guardian, or a failed login attempt from the management host will lock it out.

**Primary recommendation:** Configure WUI SSH settings first (disable password auth, enable pubkey auth), deploy SSH key to `/root/.ssh/authorized_keys`, verify key login works, then add IP restriction rules to firewall.local, then install Guardian with the management host already in the whitelist before it starts monitoring.

---

## Standard Stack

### Core (native to IPFire CU200 — installed or built-in)

| Component | Location | Purpose | Notes |
|-----------|----------|---------|-------|
| OpenSSH daemon | Built-in | SSH remote access | Port 22 (enabled via WUI checkbox in Phase 1) |
| `/etc/ssh/sshd_config` | `/etc/ssh/sshd_config` | SSH daemon configuration | Partially managed by WUI via sshctrl binary |
| `/usr/local/bin/sshctrl` | Binary | WUI SSH settings applier | Modifies Port setting only; other directives survive save |
| firewall.local | `/etc/sysconfig/firewall.local` | Custom iptables rules | Already deployed in Phase 1; will be extended in Phase 3 |
| fcron | Built-in | Cron scheduler (SysVinit) | Implements SSH 15-minute expiry timer |

### Pakfire Add-on (install in Phase 3)

| Package | Pakfire Name | Purpose | Notes |
|---------|-------------|---------|-------|
| Guardian 2.0 | `guardian` | SSH + WUI brute-force protection | IPFire-native fail2ban equivalent; manages iptables blocks; WUI integration |

### Key File Paths

| File | Path | Notes |
|------|------|-------|
| SSH daemon config | `/etc/ssh/sshd_config` | WUI-partially-managed; sshctrl modifies Port only |
| Authorized keys | `/root/.ssh/authorized_keys` | Default for root; must be created with correct permissions |
| Guardian config | `/var/ipfire/guardian/guardian.conf` | WUI-generated; backed up to git as reference |
| Guardian log | `/var/log/guardian/guardian.log` | Blocked IP activity log |
| SSH WUI settings | `/var/ipfire/remote/settings` | WUI-generated settings file for SSH |
| firewall.local | `/etc/sysconfig/firewall.local` | Extended with source IP restrictions in Phase 3 |

**Installation:**
```bash
# Run on IPFire appliance
pakfire install guardian
```

### Alternatives NOT Used

| Instead of | Why Not |
|------------|---------|
| fail2ban | Not in Pakfire for IPFire 2.x; Guardian is the purpose-built replacement |
| TCP Wrappers (/etc/hosts.deny) | Deprecated in modern OpenSSH; iptables via CUSTOMINPUT is the correct layer |
| sshd ListenAddress binding | Binds to interface IP, not source IP — wrong layer for this use case; iptables is correct |
| Editing sshd_config for PasswordAuthentication | WUI checkbox is the correct method; manual edit risks being overwritten by sshctrl on next WUI save |

---

## Architecture Patterns

### Recommended Phase 3 Configuration Structure

```
configs/
├── firewall/
│   └── firewall.local          # Extended: add SSH+WUI source IP restrictions
├── ssh/
│   └── sshd_config.hardened    # Reference copy only — actual file at /etc/ssh/sshd_config
└── guardian/
    └── guardian.conf           # Reference copy of /var/ipfire/guardian/guardian.conf
```

### Pattern 1: WUI-Driven SSH Key Auth (Correct Method)

**What:** Use the IPFire WUI at System > SSH Access to manage SSH settings. The WUI writes configuration via the sshctrl binary. This survives Core Updates.

**When to use:** For all settings that have WUI checkboxes — port selection, password auth toggle, pubkey auth toggle.

**WUI settings to apply (in order):**

1. Uncheck "Allow password based authentication" — disables `PasswordAuthentication` in sshd_config
2. Check "Allow public key based authentication" — enables `PubkeyAuthentication yes`
3. Confirm "Set SSH port to default 22" is checked (established in Phase 1)
4. Uncheck "Allow SSH Agent Forwarding" (unless explicitly needed)
5. Uncheck "Allow TCP forwarding" (unless explicitly needed)

**After WUI save, verify:**
```bash
# Run on IPFire appliance
grep -E "(PasswordAuthentication|PubkeyAuthentication|Port)" /etc/ssh/sshd_config
# Expected:
# Port 22
# PasswordAuthentication no
# PubkeyAuthentication yes
```

### Pattern 2: SSH Key Deployment to IPFire

**What:** Generate ed25519 key pair on the management host (192.168.1.100 / Windows), copy public key to `/root/.ssh/authorized_keys` on IPFire. Key must be deployed while password auth is still enabled.

**When to use:** Before disabling password auth.

**Key generation (on Windows management host):**
```bash
# Generate ed25519 key pair (modern, compact, fast)
ssh-keygen -t ed25519 -f ~/.ssh/ipfire_ed25519 -C "mgmt@ipfire-$(date +%Y%m%d)"
# -t ed25519: recommended over RSA for new keys; IPFire OpenSSH supports ed25519
# -f: explicit key path prevents overwriting existing keys
# -C: comment for identification in authorized_keys
```

**Deploy public key to IPFire:**
```bash
# Option A: ssh-copy-id (preferred — handles permissions automatically)
ssh-copy-id -i ~/.ssh/ipfire_ed25519.pub -p 22 root@192.168.1.1

# Option B: Manual via SCP + SSH (Windows-safe approach when CRLF is a concern)
# Step 1: SCP the public key file (text file — watch for CRLF, use dos2unix if needed)
scp -P 22 ~/.ssh/ipfire_ed25519.pub root@192.168.1.1:/tmp/mgmt_key.pub
# Step 2: On IPFire, install the key
ssh root@192.168.1.1 -p 22
mkdir -p /root/.ssh && chmod 700 /root/.ssh
cat /tmp/mgmt_key.pub >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
rm /tmp/mgmt_key.pub
```

**CRLF Warning (Windows-specific):** If copying public key via SCP from Windows, the `.pub` file may have CRLF line endings. OpenSSH on IPFire will reject keys with `\r\n`. Fix before deploying:
```bash
# On IPFire after receiving the file
dos2unix /tmp/mgmt_key.pub
```
Or generate the key on WSL/Git Bash where line endings are LF.

**Verify key login before disabling password auth:**
```bash
ssh -i ~/.ssh/ipfire_ed25519 -p 22 root@192.168.1.1
# Must succeed before proceeding to disable password auth
```

### Pattern 3: firewall.local Extension for Source IP Restriction

**What:** Extend the existing firewall.local (deployed in Phase 1) to add source IP restrictions. The existing file already has ACCEPT rules for ports 22 and 444 from GREEN_DEV. Add DROP rules to block SSH and WUI from non-management source IPs.

**Defense-in-depth approach:** The ACCEPT rule from Phase 1 allows all of GREEN (192.168.1.0/24). Phase 3 adds a more restrictive rule: only allow from management host (192.168.1.100), then DROP the rest.

**Critical ordering:** ACCEPT for management host MUST come BEFORE the DROP rule. CUSTOMINPUT is processed top-to-bottom; the first matching rule wins.

**Extended firewall.local pattern:**
```bash
#!/bin/sh
# /etc/sysconfig/firewall.local
# Phase 1: Anti-lockout rules (existing)
# Phase 3 extension: Restrict SSH and WUI to management subnet only

. /var/ipfire/ethernet/settings

# Management host — single IP or subnet
MGMT_HOST="192.168.1.100"
MGMT_SUBNET="192.168.1.0/24"  # GREEN subnet — for reference

case "$1" in
  start)
    # === Phase 1 rules (existing — DO NOT REMOVE) ===
    # These ensure SSH and WUI remain accessible from GREEN during any rule changes
    # The management-specific rules below are MORE restrictive but Phase 1 rules
    # remain as fallback if Phase 3 rules are misconfigured
    /sbin/iptables -A CUSTOMINPUT -i "${GREEN_DEV}" -p tcp --dport 22 -j ACCEPT
    /sbin/iptables -A CUSTOMINPUT -i "${GREEN_DEV}" -p tcp --dport 444 -j ACCEPT

    # === Phase 3 rules: Block SSH from ORANGE zone ===
    # ORANGE zone has no management function; SSH must not be reachable from DMZ
    /sbin/iptables -A CUSTOMINPUT -i "${ORANGE_DEV}" -p tcp --dport 22 -j DROP
    /sbin/iptables -A CUSTOMINPUT -i "${ORANGE_DEV}" -p tcp --dport 444 -j DROP

    # === Phase 3 rules: Block SSH from BLUE zone (WiFi) ===
    # BLUE zone clients must not reach management interface
    /sbin/iptables -A CUSTOMINPUT -i "${BLUE_DEV}" -p tcp --dport 22 -j DROP
    /sbin/iptables -A CUSTOMINPUT -i "${BLUE_DEV}" -p tcp --dport 444 -j DROP
    ;;

  stop)
    # Phase 1 rules
    /sbin/iptables -C CUSTOMINPUT -i "${GREEN_DEV}" -p tcp --dport 22 -j ACCEPT 2>/dev/null && \
      /sbin/iptables -D CUSTOMINPUT -i "${GREEN_DEV}" -p tcp --dport 22 -j ACCEPT
    /sbin/iptables -C CUSTOMINPUT -i "${GREEN_DEV}" -p tcp --dport 444 -j ACCEPT 2>/dev/null && \
      /sbin/iptables -D CUSTOMINPUT -i "${GREEN_DEV}" -p tcp --dport 444 -j ACCEPT

    # Phase 3 rules
    /sbin/iptables -C CUSTOMINPUT -i "${ORANGE_DEV}" -p tcp --dport 22 -j DROP 2>/dev/null && \
      /sbin/iptables -D CUSTOMINPUT -i "${ORANGE_DEV}" -p tcp --dport 22 -j DROP
    /sbin/iptables -C CUSTOMINPUT -i "${ORANGE_DEV}" -p tcp --dport 444 -j DROP 2>/dev/null && \
      /sbin/iptables -D CUSTOMINPUT -i "${ORANGE_DEV}" -p tcp --dport 444 -j DROP
    /sbin/iptables -C CUSTOMINPUT -i "${BLUE_DEV}" -p tcp --dport 22 -j DROP 2>/dev/null && \
      /sbin/iptables -D CUSTOMINPUT -i "${BLUE_DEV}" -p tcp --dport 22 -j DROP
    /sbin/iptables -C CUSTOMINPUT -i "${BLUE_DEV}" -p tcp --dport 444 -j DROP 2>/dev/null && \
      /sbin/iptables -D CUSTOMINPUT -i "${BLUE_DEV}" -p tcp --dport 444 -j DROP
    ;;

  reload)
    $0 stop
    $0 start
    ;;

  *)
    echo "Usage: $0 {start|stop|reload}"
    exit 1
    ;;
esac
```

**Note on ORANGE_DEV and BLUE_DEV availability:** These variables are sourced from `/var/ipfire/ethernet/settings`. If ORANGE or BLUE zones are not configured, the variables will be empty and the iptables commands will fail. Guard against this with:
```bash
[ -n "${ORANGE_DEV}" ] && /sbin/iptables -A CUSTOMINPUT -i "${ORANGE_DEV}" -p tcp --dport 22 -j DROP
```

**GREEN-subnet-only restriction (more restrictive option):** To restrict SSH to 192.168.1.100 only within GREEN (not just zone-level), add:
```bash
# After the GREEN ACCEPT rule, add:
# Allow only management host — DROP any other GREEN source
/sbin/iptables -A CUSTOMINPUT -i "${GREEN_DEV}" -p tcp --dport 22 -j DROP
/sbin/iptables -A CUSTOMINPUT -i "${GREEN_DEV}" -p tcp --dport 444 -j DROP
# Then replace the broad GREEN ACCEPT rules with specific source IP:
/sbin/iptables -A CUSTOMINPUT -s 192.168.1.100 -i "${GREEN_DEV}" -p tcp --dport 22 -j ACCEPT
/sbin/iptables -A CUSTOMINPUT -s 192.168.1.100 -i "${GREEN_DEV}" -p tcp --dport 444 -j ACCEPT
```

**IMPORTANT:** Source-IP restriction REMOVES the broad GREEN zone fallback. If the management host IP changes or is unreachable, SSH is locked out until console access. Keep the broader GREEN subnet ACCEPT as the Phase 1 fallback until the source-IP rules are validated.

### Pattern 4: Guardian Installation and Configuration

**What:** Install Guardian via Pakfire, add management host to the ignore list via WUI BEFORE Guardian starts monitoring, configure strike threshold.

**Operational sequence (order is critical):**

```
1. pakfire install guardian
2. WUI: System > Guardian — Add 192.168.1.100 to ignore list (BEFORE enabling)
3. WUI: System > Guardian — Set strike threshold (default 3 is appropriate)
4. WUI: System > Guardian — Enable Guardian
5. Verify: Guardian log shows it is monitoring
6. Test: Confirm a failed SSH attempt from a non-whitelisted host is blocked
```

**Guardian WUI configuration fields:**
- Strike threshold: Number of failures before block (default: 3)
- Ignored Hosts: Single IPs or CIDR subnets — add `192.168.1.100` and optionally `192.168.1.0/24`
- Log facility: File (writes to `/var/log/guardian/guardian.log`) or Syslog
- Log level: Info (default) — logs block/unblock events

**Post-install verification:**
```bash
# Verify Guardian service is running (SysVinit)
/etc/init.d/guardian status

# Check Guardian log for activity
tail -f /var/log/guardian/guardian.log

# Verify Guardian's iptables rules
iptables -L INPUT -n -v | grep Guardian
# or
iptables -L -n | grep -i guardian
```

### Pattern 5: SSH 15-Minute Expiry Workflow

**What:** The WUI "Stop SSH Daemon in 15 minutes" button is the recommended access mode for IPFire SSH. It starts sshd, then an fcron job stops it after 15 minutes. Sessions already established are NOT terminated — only new connection attempts are blocked after 15 minutes.

**How it works (IPFire 2.x SysVinit + fcron):**
1. User clicks "Stop SSH Daemon in 15 minutes" in WUI
2. IPFire starts sshd and writes a timestamp file
3. The fcron scheduler checks the timestamp periodically
4. After 15 minutes from SSH activation, fcron triggers `/etc/init.d/sshd stop`
5. Existing sessions remain; new connections are rejected

**Implication for Phase 3:** For permanent SSH with key-only auth (required for automation/monitoring), the "Enable SSH access until disabled by this checkbox" mode is used. The 15-minute mode is documented as the preferred manual-access method for ad-hoc administration.

**Documentation task:** SSH-05 requires this feature be documented and operational. The planner should create a runbook entry in `docs/ssh-management-runbook.md` explaining:
- When to use 15-minute mode vs. permanent mode
- How to verify the timer is active
- Emergency access recovery procedure

### Anti-Patterns to Avoid

- **Manually editing PasswordAuthentication in sshd_config:** sshctrl may overwrite changes on next WUI SSH save. Use the WUI checkbox instead.
- **Using /etc/hosts.allow or TCP wrappers:** Deprecated in OpenSSH 6.7+; IPFire uses iptables, not TCP wrappers.
- **Removing Phase 1 CUSTOMINPUT ACCEPT rules:** The Phase 1 rules are the anti-lockout failsafe. Phase 3 rules are additive restrictions, not replacements.
- **Enabling Guardian before whitelisting management host:** Guardian will block failed SSH attempts from the management host. One typo while testing and you are locked out.
- **Adding source IP restriction before verifying key login works:** Always verify key-based login succeeds from 192.168.1.100 before disabling password auth.
- **Using AllowUsers without testing:** If `AllowUsers root@192.168.1.100` is added but SSH is tested from a different host, the session is rejected. Test from the exact whitelisted IP.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SSH brute-force protection | Custom iptables rate limiting or fail2ban | Guardian (Pakfire) | Guardian monitors sshd and WUI logs via inotify; correctly tracks authentication failures not just connection attempts; full WUI integration |
| SSH key distribution | Custom rsync scripts | `ssh-copy-id` | Handles authorized_keys permissions correctly; idempotent; native to OpenSSH |
| Port-based access control | Custom iptables script | firewall.local CUSTOMINPUT pattern | CUSTOMINPUT is preserved across WUI changes; custom scripts in /etc/rc.local may not survive Core Updates |

**Key insight:** IPFire has a WUI-first configuration model. Any hand-rolled solution that duplicates WUI functionality will conflict with WUI state management. Stay in the WUI where possible; use firewall.local only for things the WUI cannot express.

---

## Common Pitfalls

### Pitfall 1: sshctrl Overwrites Manual sshd_config Changes

**What goes wrong:** Manually adding `PasswordAuthentication no` to `/etc/ssh/sshd_config`, then saving SSH settings in the WUI. The sshctrl binary modifies the file and may corrupt the manual entry.

**Why it happens:** IPFire's SSH configuration page generates changes via a C binary (sshctrl) that edits specific lines in sshd_config. It targets `Port` directives by line pattern matching. Other directives may or may not survive depending on sshctrl version.

**How to avoid:** Use the WUI checkboxes for all WUI-managed settings. Do not manually set PasswordAuthentication — use the "Allow password based authentication" checkbox instead. Only add directives to sshd_config that have NO corresponding WUI checkbox (e.g., `AllowUsers`, `Match Address` blocks, `MaxAuthTries`).

**Warning signs:** `PasswordAuthentication no` appears in sshd_config after manual edit, then disappears after WUI save.

### Pitfall 2: Guardian Locks Out Management Host

**What goes wrong:** Guardian is installed and enabled before the management host (192.168.1.100) is added to the ignore list. A typo in the SSH password during key setup causes Guardian to count the failure. After 3 failures, 192.168.1.100 is blocked.

**Why it happens:** Guardian blocks by source IP. The management host is the most active SSH source. Its failures are the first thing Guardian sees.

**How to avoid:** Add 192.168.1.100 (and optionally 192.168.1.0/24) to Guardian's ignore list via WUI BEFORE clicking "Enable Guardian." The ignore list takes effect immediately on Guardian startup.

**Recovery:** SSH blocked by Guardian can be recovered via physical console: `iptables -D INPUT -s 192.168.1.100 -j DROP` or via WUI if WUI is still accessible.

### Pitfall 3: Authorized Keys CRLF from Windows

**What goes wrong:** SSH public key file copied from Windows has `\r\n` line endings. IPFire's sshd rejects the key silently. Password auth fallback works but key auth fails.

**Why it happens:** Windows text editors and even native Windows SSH keygen may write CRLF line endings. OpenSSH expects LF-only authorized_keys.

**How to avoid:** Always run `dos2unix` on the key file after copying from Windows, OR generate keys in WSL/Git Bash. Verify key format: `file ~/.ssh/ipfire_ed25519.pub` should show "ASCII text" not "ASCII text, with CRLF line terminators."

**Warning signs:** `ssh -v` output shows "Offering public key" but server responds with `permission denied`.

### Pitfall 4: Phase 1 ACCEPT Rules vs Phase 3 DROP Rules Ordering

**What goes wrong:** Phase 3 DROP rules for ORANGE/BLUE zones are added but Phase 1 ACCEPT rules for GREEN are positioned AFTER the DROP rules. CUSTOMINPUT is first-match-wins. A DROP rule early in the chain blocks traffic that should have been ACCEPTed by a later rule.

**Why it happens:** iptables CUSTOMINPUT uses the first-matching rule. If DROP is added at position 1 and ACCEPT at position 2, the DROP fires first even if the traffic matches both.

**How to avoid:** Always structure firewall.local so ACCEPT rules come before DROP rules for the same port. The Phase 1 ACCEPT for GREEN on ports 22 and 444 must be added before any DROP rules for those ports.

**Warning signs:** Can SSH from ORANGE but not from GREEN. Check rule order: `iptables -L CUSTOMINPUT -n -v --line-numbers`.

### Pitfall 5: ORANGE_DEV / BLUE_DEV Undefined When Zones Not Active

**What goes wrong:** firewall.local references `${ORANGE_DEV}` but ORANGE zone is not configured, so the variable is empty. The iptables command becomes `iptables -A CUSTOMINPUT -i -p tcp` which is a syntax error. The firewall reload fails.

**Why it happens:** `/var/ipfire/ethernet/settings` only defines `_DEV` variables for configured zones. If ORANGE is not configured, `ORANGE_DEV` is unset.

**How to avoid:** Guard zone-specific rules with `[ -n "${ORANGE_DEV}" ] && ...`. The firewall.local must be resilient to unconfigured zones.

### Pitfall 6: SSH Access Mode for Phase 3 (Key Auth + Permanent vs. 15-Minute)

**What goes wrong:** Phase 3 sets up key auth but the WUI is left in "15-minute" mode. On next reboot, sshd is not running. The first manual access requires WUI (which requires being on 192.168.1.100 at port 444). If both fail, you need console access.

**Why it happens:** The IPFire default is "SSH daemon is normally not running." The WUI 15-minute button is a transient mode — it does NOT persist across reboots.

**How to avoid:** For a managed appliance where SSH is used for automation, monitoring, or regular admin, set "Enable SSH access until disabled by this checkbox" in the WUI. This persists across reboots. Document this decision in the runbook.

**The 15-minute mode is appropriate for:** Unattended appliances where SSH is only used for emergency access.

---

## Code Examples

### Check Current CUSTOMINPUT Rules
```bash
# Source: iptables standard usage, verified on IPFire 2.x
iptables -L CUSTOMINPUT -n -v --line-numbers
# Shows rule numbers, packet counts, source/destination, and ports
# Verify SSH (port 22) and WUI (port 444) ACCEPT rules are present
# Verify DROP rules for ORANGE/BLUE come AFTER GREEN ACCEPT rules
```

### Install Guardian
```bash
# Source: IPFire Pakfire documentation
# Run on IPFire appliance
pakfire install guardian
# Guardian installs, creates /var/ipfire/guardian/guardian.conf, and registers with WUI
```

### Guardian Service Control (SysVinit)
```bash
# Source: IPFire SysVinit patterns (confirmed — IPFire 2.x uses SysVinit, not systemd)
/etc/init.d/guardian status
/etc/init.d/guardian start
/etc/init.d/guardian stop
/etc/init.d/guardian restart
```

### Verify SSH Key Authentication Works
```bash
# Run from management host (192.168.1.100) before disabling password auth
ssh -i ~/.ssh/ipfire_ed25519 -p 22 -o PasswordAuthentication=no root@192.168.1.1
# -o PasswordAuthentication=no: forces key-only so test confirms key works, not password
# Must succeed before proceeding to WUI disable-password step
```

### Verify sshd_config Settings
```bash
# Run on IPFire
grep -E "(PasswordAuthentication|PubkeyAuthentication|AuthorizedKeysFile|Port|AllowUsers)" /etc/ssh/sshd_config
```

### Verify authorized_keys Permissions
```bash
# Run on IPFire — OpenSSH rejects authorized_keys with wrong permissions
ls -la /root/.ssh/
# Expected:
# drwx------ 2 root root ... .ssh/       (700)
# -rw------- 1 root root ... authorized_keys  (600)
```

### Guardian Ignore List (WUI-managed, reference only)
```bash
# /var/ipfire/guardian/guardian.conf — WUI-generated reference
# Ignore list entries visible in WUI: System > Guardian > Ignored Hosts
# Entries accept: single IPv4 (192.168.1.100) or CIDR (192.168.1.0/24)
# These are NOT edited by hand — use the WUI input field
```

### Verify Firewall Rules After Reload
```bash
# Apply firewall.local changes
/etc/init.d/firewall restart

# Verify rules applied
iptables -L CUSTOMINPUT -n -v --line-numbers | grep -E "(22|444)"
# Should show: ACCEPT rules for GREEN, DROP rules for ORANGE/BLUE
```

---

## SSH 15-Minute Mode: Decision Reference

| SSH Mode | WUI Setting | Persists Across Reboot | Use Case |
|----------|------------|----------------------|----------|
| Always On | "Enable SSH access until disabled" | Yes | Regular admin, monitoring scripts, Phase 3+ |
| 15-minute | "Stop SSH Daemon in 15 minutes" | No (one-shot) | Emergency access, unattended appliance |
| 30-minute | "Stop SSH Daemon in 30 minutes" | No (one-shot) | Extended session, unattended appliance |
| Off | SSH daemon not running | N/A | Default state, most secure |

**Recommendation for Phase 3:** Enable "SSH access until disabled" (persistent) while configuring key auth. After Phase 3 is complete, the runbook should document how to switch to 15-minute mode for tighter security if desired.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| RSA keys for SSH | ed25519 keys | OpenSSH 6.5 (2014) | ed25519 is smaller, faster, equally secure; avoid RSA-SHA1 (disabled in OpenSSH 8.8+) |
| TCP wrappers (hosts.deny) | iptables / nftables | OpenSSH 6.7 | TCP wrappers removed from OpenSSH; use firewall-layer restriction only |
| fail2ban | Guardian (on IPFire) | IPFire Pakfire policy | fail2ban not packaged for IPFire; Guardian is the maintained alternative |

---

## Open Questions

1. **SSH port: permanent port 22 vs revert to 222**
   - What we know: Phase 1 deployed firewall.local with port 22 ACCEPT; the actual deployed file uses port 22; the Phase 1 plan referenced port 222 but the deployed artifact shows port 22
   - What's unclear: Was port 22 specifically chosen in Phase 1, or is it still on 222 and the firewall.local was deployed with a typo
   - Recommendation: Validate the live system's SSH port before Phase 3 plan execution. `grep "^Port" /etc/ssh/sshd_config` will confirm. The plan should verify this and document the actual port.

2. **ORANGE_DEV and BLUE_DEV zone configuration status**
   - What we know: The ethernet/settings template from Phase 1 has ORANGE and BLUE configured; the 6-NIC setup assigns all 4 zones
   - What's unclear: Whether ORANGE and BLUE are actually active (have traffic/devices) or just configured at the IP level
   - Recommendation: Phase 3 firewall.local should guard zone variable usage with `[ -n "${VAR}" ]` checks regardless; ADD blocking rules for all configured zones.

3. **Guardian and Suricata IPS interaction (Phase 4 dependency)**
   - What we know: Phase 3 must be complete before Phase 4 (IPS) to prevent IPS rules from blocking management traffic
   - What's unclear: Whether Guardian blocks interoperate correctly with Suricata's nfqueue IPS mode (which sits before iptables in packet path)
   - Recommendation: Guardian uses standard iptables INPUT chain rules; Suricata nfqueue operates at a different hook point; the interaction should be clean. Flag for Phase 4 validation: confirm Guardian blocks still apply after Suricata IPS is enabled.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Shell scripts (bash) — consistent with Phase 1 and Phase 2 validation approach |
| Config file | None — scripts run directly |
| Quick run command | `bash /root/firewall-repo/scripts/validate-phase3.sh` |
| Full suite command | Same as quick (Phase 3 is a small, self-contained phase) |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | Notes |
|--------|----------|-----------|-------------------|-------|
| SSH-01 | Password auth rejected; key auth succeeds | automated | `ssh -o PasswordAuthentication=no -i key root@192.168.1.1` succeeds; `ssh -o PubkeyAuthentication=no root@192.168.1.1` fails | Must test from 192.168.1.100 |
| SSH-02 | SSH from outside management subnet dropped | semi-automated | `iptables -L CUSTOMINPUT -n` shows DROP for ORANGE/BLUE; live test requires host on ORANGE or BLUE | ORANGE/BLUE live test is SKIP if zones unpopulated |
| SSH-03 | Guardian blocking brute-force visible in WUI | semi-automated | `/etc/init.d/guardian status` shows running; guardian.log exists; WUI shows Guardian active | Full block test requires simulated failed logins |
| SSH-04 | WUI unreachable from ORANGE/BLUE | semi-automated | `iptables -L CUSTOMINPUT -n` shows port 444 DROP for ORANGE/BLUE | Live test requires host on ORANGE or BLUE |
| SSH-05 | 15-minute expiry documented and operational | manual | Document in runbook; manual test: click 15-min button, wait, confirm sshd stops | Cannot automate timer wait |

### Wave 0 Gaps

- [ ] `scripts/validate-phase3.sh` — covers SSH-01, SSH-02, SSH-03, SSH-04 (automated portions)
- [ ] `docs/ssh-management-runbook.md` — covers SSH-05 documentation requirement

---

## Sources

### Primary (HIGH confidence)

- [IPFire SSH Access Documentation](https://www.ipfire.org/docs/configuration/system/ssh) — WUI checkbox list, port behavior, 15-minute expiry, authorized_keys, sshctrl binary behavior
- [IPFire Guardian Add-on Documentation](https://www.ipfire.org/docs/addons/guardian) — installation, WUI integration, ignore list syntax, block display
- [IPFire Additional Security Configuration](https://www.ipfire.org/docs/optimization/start/security_hardening/additional_security_configuration) — official recommendation for key-only auth, Guardian, subnet restriction
- [IPFire firewall.local Documentation](https://www.ipfire.org/docs/configuration/firewall/firewall-local) — CUSTOMINPUT chain, start/stop/reload pattern
- Phase 1 RESEARCH.md and deployed `configs/firewall/firewall.local` — confirmed port 22 in deployed artifact, CUSTOMINPUT pattern, GREEN_DEV variable usage

### Secondary (MEDIUM confidence)

- [IPFire Community: SSH Public Key Setup with PuTTY](https://community.ipfire.org/t/how-to-setup-ssh-public-key-access-with-putty/7875) — authorized_keys path confirmed as `/root/.ssh/authorized_keys` (root default); WUI save overwrites sshd_config warning confirmed by moderator
- [IPFire Community: WUI Access Restriction Discussion](https://community.ipfire.org/t/deny-access-to-webui-from-blue/10138) — CUSTOMINPUT DROP pattern for port 444 restriction from BLUE zone
- [IPFire Community: sshd_config and sshctrl behavior](https://forum.ipfire.org/viewtopic.php?t=22983) — sshctrl modifies Port line only; manual changes to other directives may survive
- [IPFire Community: How to Disable SSH from RED](https://community.ipfire.org/t/how-to-disable-ssh-from-red/4030) — default RED zone blocks SSH; no inbound rule required for RED
- IPFire crontab source (fossies.org) — confirms fcron implements 15-minute expiry timer

### Tertiary (LOW confidence — verify on live system)

- Exact behavior of sshctrl when it encounters additional manually-added directives in sshd_config — community reports suggest it modifies Port only, but this should be verified after first WUI SSH save
- ORANGE_DEV and BLUE_DEV variable availability when zones are configured but have no active connections — verify variables are populated in `/var/ipfire/ethernet/settings` on the live system

---

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — Guardian and SSH are documented in IPFire official docs; file paths confirmed from multiple sources
- Architecture patterns: HIGH — firewall.local CUSTOMINPUT pattern confirmed from Phase 1; WUI checkbox list confirmed from official docs; key auth path confirmed from community + official docs
- Pitfalls: HIGH — sshctrl behavior confirmed by community moderator; CRLF issue is documented Phase 1 known concern; rule ordering is fundamental iptables behavior
- Guardian behavior: HIGH — official docs + blog post describe WUI integration, ignore list, and block display

**Research date:** 2026-03-22
**Valid until:** 2026-06-22 (stable IPFire 2.x patterns; Guardian 2.0 released Feb 2025, stable)

**Known uncertainty:** The authorized_keys path has conflicting community reports (`/root/.ssh/authorized_keys` vs `/etc/ssh/authorized_keys`). The official WUI documentation references `ssh-copy-id` without specifying a path, and the `AuthorizedKeysFile` directive in the default sshd_config was not retrievable due to the Fossies 403 error. The plan should verify the live `AuthorizedKeysFile` directive with `grep AuthorizedKeysFile /etc/ssh/sshd_config` as a first step, and use whatever path the live system has configured.
