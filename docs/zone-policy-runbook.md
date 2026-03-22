# Zone Policy Runbook — Phase 1 Firewall Configuration

Step-by-step WUI actions to implement FW-01 through FW-06.
All steps performed by the human on the IPFire WUI at https://IPFIRE_IP:444.

**CRITICAL — Read before any WUI changes:**
firewall.local must be deployed and active before making any changes here.
Verify first: `iptables -L CUSTOMINPUT -n -v | grep -E '(222|444)'`
Both ports must show ACCEPT rules. If not, deploy firewall.local first (Plan 02).

---

## Default Firewall Posture (Fresh IPFire Install)

Understanding what is already correct prevents unnecessary changes.

| Zone Pair | Default | Action Required? | Requirement |
|-----------|---------|-----------------|-------------|
| RED inbound → any zone | BLOCKED | No — correct | FW-01 |
| GREEN outbound → RED | ALLOWED | No — correct | — |
| GREEN → ORANGE | **OPEN** | **YES — block it** | FW-03 |
| GREEN → BLUE | OPEN | Evaluate — block recommended | FW-03 |
| ORANGE → GREEN | BLOCKED | No — correct | FW-03 |
| BLUE → GREEN | BLOCKED | No — correct | FW-03 |
| GREEN masquerade (NAT) | ENABLED | No — correct | FW-02 |
| ORANGE masquerade (NAT) | **DISABLED** | **YES — enable it** | FW-02 |
| BLUE masquerade (NAT) | **DISABLED** | **YES — enable it** | FW-02 |

Stateful firewall (conntrack) is active by default — no configuration needed.

---

## FW-01: Stateful Firewall with Default-Deny Inbound

**Status: Active by default on fresh install.**
RED inbound is blocked by default. conntrack is active. No WUI changes needed.

**Verify:**
- From an external host (outside your WAN), run:
  `nmap -Pn -p 22,80,222,443,444,8080 YOUR_WAN_IP`
  All ports must show as `filtered` (no response from firewall) or `closed`.
- There must be NO `open` ports in nmap output for the WAN IP.

---

## FW-02: NAT/Masquerade on RED for All Internal Zones

GREEN masquerade is enabled by default. ORANGE and BLUE must be enabled manually.

### Enable ORANGE Masquerade

1. WUI: **Firewall > Masquerade**
2. Find the ORANGE zone row
3. Check the **Masquerade** checkbox for ORANGE
4. Click **Save**

**Verify:**
- From a host on ORANGE zone, run: `curl http://checkip.amazonaws.com`
- Response must be your WAN IP (not the ORANGE zone IP)

### Enable BLUE Masquerade

1. WUI: **Firewall > Masquerade**
2. Find the BLUE zone row
3. Check the **Masquerade** checkbox for BLUE
4. Click **Save**

**Verify:**
- From a host on BLUE zone, run: `curl http://checkip.amazonaws.com`
- Response must be your WAN IP

### Verify GREEN Masquerade (should already be active)

- From a host on GREEN zone, run: `curl http://checkip.amazonaws.com`
- Response must be your WAN IP

---

## FW-03: Zone Segmentation — Block GREEN-to-ORANGE

**CRITICAL: GREEN-to-ORANGE is OPEN by default. This must be explicitly blocked.**

If ORANGE is your DMZ, trusted LAN clients can reach DMZ hosts without any rules
until this is done. Add the block rule before adding any ORANGE hosts.

### Block GREEN-to-ORANGE Forwarding

1. WUI: **Firewall > Firewall Rules**
2. Click **Add Rule**
3. Configure:
   - Action: **DROP** (or REJECT)
   - Protocol: **All**
   - Source zone: **GREEN**
   - Destination zone: **ORANGE**
   - Log: **Enabled** (so drops appear in /var/log/messages)
   - Position: **Top of ruleset** (above any permissive rules)
4. Click **Save and Restart**

### Block GREEN-to-BLUE Forwarding (recommended)

Repeat the above for GREEN → BLUE to enforce wireless zone isolation.

### Add Pinhole Rules (as needed)

After blocking GREEN-to-ORANGE, add specific allow rules above the block rule
for services you explicitly want reachable from GREEN (e.g., a web server on ORANGE):

1. WUI: **Firewall > Firewall Rules**
2. Click **Add Rule**
3. Configure:
   - Action: **ACCEPT**
   - Protocol: **TCP**
   - Source zone: **GREEN**
   - Destination: specific ORANGE host IP and port (e.g., 172.16.1.10:443)
   - Position: **Above the DROP GREEN→ORANGE rule**
4. Click **Save and Restart**

**Verify zone isolation:**
- From a GREEN host: `ping ORANGE_HOST_IP` — must time out (no response)
- From a GREEN host: `ping BLUE_HOST_IP` — must time out (if BLUE also blocked)
- From an ORANGE host: `ping GREEN_HOST_IP` — must time out (already blocked by default)

---

## FW-04: Port Forwarding (DNAT) Capability

IPFire handles DNAT natively via the WUI. No custom iptables rules needed.

### Configure a Test DNAT Rule

1. WUI: **Firewall > Port Forwarding**
2. Click **Add Rule**
3. Configure an example rule:
   - Incoming interface: **RED**
   - Protocol: **TCP**
   - Destination port: **8080** (test port — not 80/443 to avoid conflicts)
   - Forward to: an ORANGE host IP, port 80
4. Click **Save**

**Verify:**
- From an external host, `curl http://YOUR_WAN_IP:8080` should reach the ORANGE host
- Remove the test rule after verification (WUI: Firewall > Port Forwarding > delete)

**Note:** FW-04 validates the capability exists and works. Actual production DNAT
rules are out of scope for Phase 1 — add them when specific services require it.

---

## FW-05: Firewall Drop Logging

### Enable Drop Logging via WUI

1. WUI: **Firewall > Firewall Options**
2. Find **Log dropped packets** (or similar label — exact label may vary by IPFire version)
3. Enable the option
4. Click **Save**

**Verify:**
- Trigger a blocked connection: from an external host, `nmap -Pn YOUR_WAN_IP`
- On IPFire, check: `grep -E '(DROP|FORWARDFW)' /var/log/messages | tail -20`
- Must show log entries with FORWARDFW or DROP prefix within 60 seconds

**Note:** The FORWARDFW prefix applies to both ACCEPT and DROP decisions logged
by the FORWARDFW chain. DROP_INPUT applies to blocked INPUT chain packets.

---

## FW-06: Firewall Rules Persist Across Reboot

WUI rules are stored in /var/ipfire/ and loaded at boot via /etc/init.d/firewall.
No explicit configuration needed — persistence is inherent.

**Verify:**
1. Note the current state of firewall rules: `iptables -L -n | head -50`
2. Reboot IPFire: `reboot`
3. After reboot, re-check: `iptables -L -n | head -50`
4. Rules must be identical to pre-reboot state
5. Run: `bash /root/firewall-repo/scripts/validate-phase1.sh`
6. All checks must pass (this confirms both rules and NIC mapping persist)

---

## Summary: Required WUI Actions

Complete in this order:

- [ ] 1. Verify firewall.local is active (CUSTOMINPUT has 222 and 444 ACCEPT rules)
- [ ] 2. Enable ORANGE masquerade (FW-02)
- [ ] 3. Enable BLUE masquerade (FW-02)
- [ ] 4. Block GREEN-to-ORANGE forwarding (FW-03) — **do this before adding ORANGE hosts**
- [ ] 5. Block GREEN-to-BLUE forwarding (FW-03) — recommended
- [ ] 6. Enable drop logging (FW-05)
- [ ] 7. Verify: `bash /root/firewall-repo/scripts/validate-phase1.sh`
- [ ] 8. Reboot and re-verify (FW-06)

---

## Post-Configuration Verification Matrix

| Requirement | Test | From | Expected |
|-------------|------|------|----------|
| FW-01 | `nmap -Pn YOUR_WAN_IP` | External host | All ports filtered |
| FW-02 | `curl checkip.amazonaws.com` | GREEN host | WAN IP returned |
| FW-02 | `curl checkip.amazonaws.com` | ORANGE host | WAN IP returned |
| FW-02 | `curl checkip.amazonaws.com` | BLUE host | WAN IP returned |
| FW-03 | `ping ORANGE_IP` | GREEN host | Request timeout |
| FW-03 | `ping GREEN_IP` | ORANGE host | Request timeout |
| FW-04 | `curl http://WAN_IP:8080` | External host | Reaches ORANGE host |
| FW-05 | `grep FORWARDFW /var/log/messages` | IPFire console | Log entries present |
| FW-06 | `iptables -L -n` after reboot | IPFire console | Rules identical |
| FW-07 | `iptables -L CUSTOMINPUT -n -v` | IPFire console | 222 + 444 ACCEPT rules |
