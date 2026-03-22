# Phase 3: SSH Hardening and Management Security — Deployment Runbook

Human-executable WUI steps and shell commands for securing remote management on IPFire 2.29 CU200.
Complete sections in ORDER — the sequence below is mandatory for safe deployment.

**IPFire WUI:** https://192.168.1.1:444
**IPFire SSH:** ssh root@192.168.1.1 (port 22)
**Management host:** 192.168.1.100

**Prerequisite:** Phase 2 complete (DHCP, DNS, NTP operational), SSH working from 192.168.1.100 via password.

**CRITICAL ORDER — read before starting:**
1. Deploy SSH key and verify key login BEFORE disabling password auth
2. Whitelist management host in Guardian BEFORE enabling Guardian
3. Apply firewall.local BEFORE testing IP restriction

---

## Section 1: Generate and Deploy SSH Key

### 1.1 Generate ed25519 key pair (on management host 192.168.1.100)

```bash
# Run on Windows (Git Bash or PowerShell)
ssh-keygen -t ed25519 -f ~/.ssh/ipfire_ed25519 -C "mgmt@ipfire-$(date +%Y%m%d)"
# Creates:
#   ~/.ssh/ipfire_ed25519       (private key — never share)
#   ~/.ssh/ipfire_ed25519.pub   (public key — deploy to IPFire)
```

### 1.2 Deploy public key to IPFire (while password auth is still enabled)

```bash
# Option A: ssh-copy-id (preferred — handles permissions automatically)
ssh-copy-id -i ~/.ssh/ipfire_ed25519.pub -p 22 root@192.168.1.1

# Option B: Manual (if ssh-copy-id is unavailable)
scp -P 22 ~/.ssh/ipfire_ed25519.pub root@192.168.1.1:/tmp/mgmt_key.pub
ssh root@192.168.1.1
# Then on IPFire:
dos2unix /tmp/mgmt_key.pub          # Fix Windows CRLF if present
mkdir -p /root/.ssh && chmod 700 /root/.ssh
cat /tmp/mgmt_key.pub >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
rm /tmp/mgmt_key.pub
```

**WARNING — CRLF:** If using native Windows ssh-keygen (not WSL/Git Bash), the .pub file
may have CRLF line endings. IPFire sshd will silently reject keys with CRLF.
Always run `dos2unix` on the key file after SCP from Windows. Verify with:
`file /tmp/mgmt_key.pub` — must show "ASCII text", not "ASCII text, with CRLF line terminators."

### 1.3 Verify key login BEFORE proceeding (mandatory)

```bash
# From management host — forces key-only, no password fallback
ssh -i ~/.ssh/ipfire_ed25519 -p 22 -o PasswordAuthentication=no root@192.168.1.1
# Must succeed and show IPFire shell prompt.
# If this fails: do NOT proceed to Section 2.
# Debug: ssh -v -i ~/.ssh/ipfire_ed25519 root@192.168.1.1
```

- [ ] Key login verified from 192.168.1.100 before proceeding

---

## Section 2: Configure SSH Settings via WUI

WUI path: **System > SSH Access**

Apply settings in this order:

1. Verify "Set SSH port to default 22" is checked (established in Phase 1)
2. Check "Allow public key based authentication" (enables PubkeyAuthentication yes)
3. Uncheck "Allow password based authentication" (disables password login)
4. Uncheck "Allow SSH Agent Forwarding" (not needed — reduces attack surface)
5. Uncheck "Allow TCP forwarding" (not needed — reduces attack surface)
6. Set SSH mode to "Enable SSH access until disabled by this checkbox" (persistent — required for remote admin)
7. Click **Save**

**Post-save verification (on IPFire):**
```bash
grep -E "(PasswordAuthentication|PubkeyAuthentication|Port)" /etc/ssh/sshd_config
# Expected:
# Port 22
# PasswordAuthentication no
# PubkeyAuthentication yes
```

**Verify key login still works after WUI save:**
```bash
ssh -i ~/.ssh/ipfire_ed25519 -o PasswordAuthentication=no root@192.168.1.1
# Must still succeed. If it fails, re-check authorized_keys permissions:
# chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys
```

**Verify password login is rejected:**
```bash
ssh -o PubkeyAuthentication=no root@192.168.1.1
# Must show: Permission denied (publickey)
```

- [ ] WUI SSH settings saved
- [ ] Key login verified after WUI save
- [ ] Password login rejected

---

## Section 3: Deploy Extended firewall.local (IP Restriction)

This step restricts SSH and WUI access to the management host (192.168.1.100) and blocks
ORANGE and BLUE zones from reaching management ports.

### 3.1 Deploy updated firewall.local from repo

```bash
# From dev machine (Windows)
scp configs/firewall/firewall.local root@192.168.1.1:/etc/sysconfig/firewall.local

# Fix CRLF (mandatory — shell script with CRLF will fail silently)
ssh root@192.168.1.1 'sed -i "s/\r$//" /etc/sysconfig/firewall.local'

# Apply the rules
ssh root@192.168.1.1 '/etc/init.d/firewall restart'
```

### 3.2 Verify rules applied correctly

```bash
ssh root@192.168.1.1 'iptables -L CUSTOMINPUT -n -v --line-numbers | grep -E "(22|444)"'
# Expected output includes:
#   ACCEPT   192.168.1.100   -> any   dpt:22
#   ACCEPT   192.168.1.100   -> any   dpt:444
#   ACCEPT   (broad GREEN)   -> any   dpt:22   (Phase 1 fallback)
#   ACCEPT   (broad GREEN)   -> any   dpt:444  (Phase 1 fallback)
#   DROP     (ORANGE_DEV)    -> any   dpt:22   (if ORANGE zone configured)
#   DROP     (BLUE_DEV)      -> any   dpt:22   (if BLUE zone configured)
```

### 3.3 Verify SSH still works from management host after rule change

```bash
ssh -i ~/.ssh/ipfire_ed25519 root@192.168.1.1
# Must succeed from 192.168.1.100
```

- [ ] firewall.local deployed and CRLF stripped
- [ ] firewall restart completed without errors
- [ ] SSH still works from management host after rule change

---

## Section 4: Install and Configure Guardian

**CRITICAL ORDER:** Add management host to ignore list BEFORE enabling Guardian.

### 4.1 Install Guardian via Pakfire

```bash
# On IPFire
pakfire install guardian
# Guardian installs and registers with WUI. Does NOT start automatically.
```

### 4.2 Configure Guardian via WUI BEFORE enabling

WUI path: **System > Guardian**

Apply ALL of the following BEFORE clicking "Enable Guardian":

1. In "Ignored Hosts" field, add: `192.168.1.100`
   (Add the full subnet optionally: `192.168.1.0/24` for broader safety)
2. Set "Strike threshold" to 3 (default — 3 failed attempts before block)
3. Set "Log facility" to File (writes to /var/log/guardian/guardian.log)
4. Click **Save** to persist the ignore list
5. NOW click "Enable Guardian"
6. Click **Save**

**WARNING:** If you enable Guardian before saving the ignore list, a single SSH typo
from 192.168.1.100 will count toward the block threshold. After 3 failures,
the management host is blocked. Recovery requires console or WUI if WUI is accessible.

### 4.3 Verify Guardian is running

```bash
ssh root@192.168.1.1 '/etc/init.d/guardian status'
# Expected: running or started

ssh root@192.168.1.1 'tail -20 /var/log/guardian/guardian.log'
# Should show Guardian startup and monitoring activity

ssh root@192.168.1.1 'iptables -L INPUT -n | grep -i guardian'
# Guardian adds rules to the INPUT chain (not CUSTOMINPUT)
```

### 4.4 Verify management host is in ignore list

```bash
ssh root@192.168.1.1 'grep "192.168.1.100" /var/ipfire/guardian/guardian.conf'
# Must return a match — if empty, return to WUI and add the ignore entry
```

- [ ] Guardian installed via Pakfire
- [ ] 192.168.1.100 added to Guardian ignore list BEFORE enabling
- [ ] Guardian enabled and running
- [ ] Guardian log shows monitoring activity

---

## Section 5: Run Validation Suite

```bash
# From dev machine — deploy repo to IPFire if not already there
scp -r C:/Users/ablan/Firewall/scripts root@192.168.1.1:/root/firewall-repo/scripts
ssh root@192.168.1.1 'find /root/firewall-repo/scripts -name "*.sh" -exec sed -i "s/\r$//" {} \; -exec chmod +x {} \;'

# Deploy docs too (required for SSH-05 runbook check)
scp -r C:/Users/ablan/Firewall/docs root@192.168.1.1:/root/firewall-repo/docs
ssh root@192.168.1.1 'find /root/firewall-repo/docs -name "*.md" -exec sed -i "s/\r$//" {} \;'

# Run validation
ssh root@192.168.1.1 'bash /root/firewall-repo/scripts/validate-phase3.sh'
# All automated checks must PASS. SKIP items require manual verification (see below).
```

- [ ] validate-phase3.sh returns ALL CHECKS PASS

---

## Section 6: Export Live Configs to Git

```bash
# On IPFire — copy live configs to repo
ssh root@192.168.1.1 '
  REPO=/root/firewall-repo
  mkdir -p "$REPO/configs/ssh" "$REPO/configs/guardian"
  # Export sshd_config (reference — shows actual post-WUI state)
  cp /etc/ssh/sshd_config "$REPO/configs/ssh/sshd_config"
  # Export firewall.local (should match what we deployed)
  cp /etc/sysconfig/firewall.local "$REPO/configs/firewall/firewall.local"
  # Export Guardian config (WUI-generated)
  cp /var/ipfire/guardian/guardian.conf "$REPO/configs/guardian/guardian.conf" 2>/dev/null || true
'

# Pull to dev machine
scp root@192.168.1.1:/root/firewall-repo/configs/ssh/sshd_config C:/Users/ablan/Firewall/configs/ssh/sshd_config
scp root@192.168.1.1:/root/firewall-repo/configs/guardian/guardian.conf C:/Users/ablan/Firewall/configs/guardian/guardian.conf 2>/dev/null || true

# Commit
cd C:/Users/ablan/Firewall
git add configs/ssh/sshd_config configs/guardian/guardian.conf
git commit -m "chore(03-02): export live SSH and Guardian configs after Phase 3 setup"
```

- [ ] Live sshd_config exported and committed to configs/ssh/sshd_config
- [ ] Live guardian.conf exported and committed to configs/guardian/guardian.conf

---

## Section 7: SSH 15-Minute Expiry Mode (SSH-05)

The IPFire WUI offers two additional SSH access modes beyond "always on":

| Mode | WUI Setting | Persists After Reboot | Use Case |
|------|------------|----------------------|----------|
| Always On | "Enable SSH access until disabled" | Yes | Regular admin, monitoring, Phase 3+ |
| 15-minute | "Stop SSH Daemon in 15 minutes" | No (one-shot) | Ad-hoc emergency access |
| 30-minute | "Stop SSH Daemon in 30 minutes" | No (one-shot) | Extended emergency session |

**How 15-minute mode works:**
1. Click "Stop SSH Daemon in 15 minutes" in WUI (System > SSH Access)
2. IPFire starts sshd and writes a timestamp file
3. fcron (IPFire's cron daemon) checks the timestamp periodically
4. After 15 minutes from activation, fcron runs `/etc/init.d/sshd stop`
5. Existing established sessions are NOT disconnected — only NEW connections are blocked

**How to verify the timer is active:**
```bash
# Check sshd is running
/etc/init.d/sshd status

# Check fcron has the 15-minute job scheduled
fcrontab -l 2>/dev/null | grep -i ssh
```

**When to use 15-minute mode:**
- One-off administration session on an unattended appliance
- When you want SSH to auto-close after your session ends
- When "always on" is disabled and you need temporary access

**Emergency access recovery (if SSH locked out):**
1. If WUI is accessible from 192.168.1.100 at https://192.168.1.1:444: navigate to System > SSH Access and enable SSH
2. If Guardian blocked your IP: WUI > System > Guardian > Blocked Hosts > Remove your IP, or on console: `iptables -D INPUT -s 192.168.1.100 -j DROP`
3. If firewall.local misconfigured: physical console — `iptables -F CUSTOMINPUT && /etc/init.d/firewall restart`
4. If authorized_keys missing/wrong permissions: physical console — `chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys`

---

## Sign-Off Checklist

Complete all items before marking Phase 3 done.

**Automated (validate-phase3.sh must pass):**
- [ ] `PasswordAuthentication no` in /etc/ssh/sshd_config (SSH-01)
- [ ] `PubkeyAuthentication yes` in /etc/ssh/sshd_config (SSH-01)
- [ ] /root/.ssh/authorized_keys exists with permissions 600 (SSH-01)
- [ ] CUSTOMINPUT has ACCEPT for 192.168.1.100 on port 22 (SSH-02)
- [ ] CUSTOMINPUT has DROP for ORANGE/BLUE on ports 22 and 444 (SSH-02, SSH-04)
- [ ] Guardian is installed and running (SSH-03)
- [ ] 192.168.1.100 is in Guardian ignore list (SSH-03)
- [ ] CUSTOMINPUT has ACCEPT for 192.168.1.100 on port 444 (SSH-04)
- [ ] ssh-management-runbook.md documents 15-minute expiry (SSH-05)

**Manual verification required:**
- [ ] Key-based SSH login succeeds from 192.168.1.100: `ssh -i ~/.ssh/ipfire_ed25519 root@192.168.1.1` (SSH-01)
- [ ] Password SSH is rejected: `ssh -o PubkeyAuthentication=no root@192.168.1.1` returns `Permission denied` (SSH-01)
- [ ] WUI accessible from management host: https://192.168.1.1:444 loads (SSH-04)
- [ ] SSH blocked from ORANGE or BLUE zone (if any host available on those zones) (SSH-02)
- [ ] WUI blocked from ORANGE or BLUE zone (if any host available) (SSH-04)
- [ ] Guardian WUI panel shows Guardian active (SSH-03)
- [ ] 15-minute expiry tested: click button, wait, confirm sshd stops (SSH-05)

**Git:**
- [ ] validate-phase3.sh committed to scripts/
- [ ] firewall.local updated and committed to configs/firewall/
- [ ] sshd_config exported from live IPFire and committed to configs/ssh/
- [ ] guardian.conf exported from live IPFire and committed to configs/guardian/
- [ ] validate-phase3.sh returns ALL CHECKS PASS (post-deployment)
