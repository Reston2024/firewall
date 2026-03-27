# Phase 1: Platform Foundation and Firewall - Research

**Researched:** 2026-03-21
**Domain:** IPFire zone/NIC configuration, udev persistent naming, firewall.local, backup includes, git repo structure
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PLAT-01 | All 6 NICs persistently mapped to IPFire zones via MAC-based udev rules, surviving reboots and kernel updates | udev rule syntax documented; ethernet/settings format documented; NIC identification commands documented |
| PLAT-02 | Anti-lockout rules in firewall.local ensuring management access (SSH + WUI) is preserved during all firewall changes | firewall.local exact syntax and chain names documented; CUSTOMINPUT chain behavior documented |
| PLAT-03 | Git repository initialized with project structure (/configs, /scripts, /services, /docs, /validation, /rollback, /manifests, /decision-log) | Directory structure prescribed; no tooling dependencies |
| PLAT-04 | IPFire hostname, timezone, and base system updates applied and documented | Standard WUI + console procedures; no novel research needed |
| PLAT-05 | Backup strategy defined — config export + backup include list for Core Update survival | /var/ipfire/backup/include.user format and syntax documented |
| FW-01 | Stateful firewall with default-deny inbound on all zones | Confirmed active on fresh install — inbound from RED blocked by default; stateful conntrack active |
| FW-02 | NAT/IP masquerade on RED (WAN) for all internal zones | GREEN masquerade confirmed enabled by default; ORANGE and BLUE require manual enable |
| FW-03 | Zone segmentation policies: GREEN/RED/ORANGE/BLUE with explicit inter-zone rules | Default inter-zone policy table documented; GREEN-to-ORANGE is OPEN by default — requires explicit block |
| FW-04 | Port forwarding (DNAT) capability configured and validated | DNAT supported natively via WUI; no custom iptables needed |
| FW-05 | Firewall logging enabled for all drop/reject actions | WUI Firewall Options controls logging; FORWARDFW prefix in /var/log/messages documented |
| FW-06 | Firewall rules persist across reboot | All WUI rules stored in /var/ipfire/ and loaded at boot via /etc/init.d/firewall — inherently persistent |
| FW-07 | Anti-lockout: MGMT allow rules applied FIRST before any deny rules during changes | CUSTOMINPUT chain processed BEFORE rest of ruleset — firewall.local is the correct mechanism |
</phase_requirements>

---

## Summary

Phase 1 establishes the physical and logical foundation that all other phases depend on. The two most critical tasks are: (1) locking each of the 6 Intel i226-V NICs to its zone name by MAC address via udev rules so that zone assignments survive kernel updates, and (2) writing a firewall.local script with hardcoded management allow rules that cannot be overridden by WUI rule changes.

IPFire's default firewall posture on a fresh install is already correct for a basic security baseline: inbound connections from RED are blocked by default, GREEN-to-RED forwarding is allowed by default, and GREEN zone NAT masquerade is enabled by default. The key gaps to address are: ensuring ORANGE masquerade is explicitly enabled, verifying GREEN-to-ORANGE is restricted (it is OPEN by default and must be explicitly blocked), and ensuring all 6 NICs are anchored to their zones before any configuration is written.

The udev rule mechanism in modern IPFire is confirmed: IPFire uses MAC-address-based zone assignment stored in `/var/ipfire/ethernet/settings`, and udev rules at `/etc/udev/rules.d/` are the correct mechanism for locking the kernel interface name to a specific zone. The git repository and backup include list must be established in this phase so that all subsequent configurations are protected from Core Update overwrites from day one.

**Primary recommendation:** Write udev rules and validate NIC persistence with a full reboot before configuring anything else. Then write firewall.local with management allow rules before touching any WUI firewall policies.

---

## Standard Stack

### Core (all native to IPFire — no packages to install in Phase 1)

| Component | Version/Location | Purpose | Notes |
|-----------|-----------------|---------|-------|
| IPFire | 2.29, Core Update 200 | Base OS — all firewall, NAT, zone policies | Already installed |
| Linux Kernel | 6.18.7 LTS | Ships with CU200; full i226-V support via `igc` driver | Already installed |
| udev | Built-in | Persistent NIC name binding by MAC | Write rules to `/etc/udev/rules.d/` |
| iptables / netfilter | Built-in | Stateful firewall; zone policy enforcement | Managed by WUI + firewall.local |
| /etc/sysconfig/firewall.local | File, not a package | Custom iptables rules that survive WUI changes | Must be created manually |
| /var/ipfire/ethernet/settings | Config file | Zone-to-NIC MAC mapping used by IPFire | Modified via `setup` or directly |
| /var/ipfire/backup/include.user | Config file | User-managed backup include list | Must be created/populated manually |
| git | Pakfire not required; git is already available on IPFire base | Repository initialization and commit | git is present on IPFire by default |

### No Pakfire Packages Required for Phase 1

Guardian (Phase 3), Lynis (Phase 6), and other add-ons are out of scope for Phase 1. Phase 1 uses only native OS capabilities.

---

## Architecture Patterns

### Recommended Project Repository Structure

```
/
├── configs/                          # IPFire configuration exports
│   ├── udev/
│   │   └── 30-persistent-network.rules   # NIC persistence rules
│   ├── ethernet/
│   │   └── settings                      # Zone-to-NIC mapping export
│   └── firewall/
│       └── firewall.local                # Anti-lockout rules
│
├── scripts/                          # Automation scripts
│   ├── validate-nics.sh              # Verify MAC-to-zone mapping post-boot
│   └── validate-firewall.sh          # Connectivity matrix test
│
├── docs/                             # Architecture decisions, runbooks
│   ├── decisions/                    # ADR files
│   └── nic-map.md                    # Physical port to zone documentation
│
├── services/                         # Future: service configs (DHCP, DNS, etc.)
├── validation/                       # Future: test artifacts
├── rollback/                         # Future: rollback procedures
├── manifests/                        # Future: Pakfire addon list
└── decision-log/                     # Future: ADR index
```

### Pattern 1: MAC-Based udev NIC Persistence

**What:** udev rules at `/etc/udev/rules.d/30-persistent-network.rules` bind each zone interface name to its NIC by MAC address. When the kernel initializes NICs at boot, udev assigns the zone name (green0, red0, blue0, orange0) based on the MAC match, regardless of probe order.

**When to use:** Always — must be written before any other configuration.

**Example (verified syntax from IPFire community and Red Hat udev docs):**
```bash
# /etc/udev/rules.d/30-persistent-network.rules
# Source: IPFire community + RHEL consistent naming docs
ACTION=="add", SUBSYSTEM=="net", ATTR{type}=="1", ATTR{address}=="aa:bb:cc:dd:ee:01", NAME="red0"
ACTION=="add", SUBSYSTEM=="net", ATTR{type}=="1", ATTR{address}=="aa:bb:cc:dd:ee:02", NAME="green0"
ACTION=="add", SUBSYSTEM=="net", ATTR{type}=="1", ATTR{address}=="aa:bb:cc:dd:ee:03", NAME="blue0"
ACTION=="add", SUBSYSTEM=="net", ATTR{type}=="1", ATTR{address}=="aa:bb:cc:dd:ee:04", NAME="orange0"
# NICs 5 and 6 bridged to GREEN — assign to green zone via /var/ipfire/ethernet/settings bridge config
# These still need a unique kernel name to be referenced by bridge setup:
ACTION=="add", SUBSYSTEM=="net", ATTR{type}=="1", ATTR{address}=="aa:bb:cc:dd:ee:05", NAME="green1"
ACTION=="add", SUBSYSTEM=="net", ATTR{type}=="1", ATTR{address}=="aa:bb:cc:dd:ee:06", NAME="green2"
```

**Key notes:**
- `ATTR{type}=="1"` matches Ethernet interfaces only (type 1 = ARPHRD_ETHER)
- `ATTR{address}` is the MAC address in lowercase colon-separated format
- Rule file name starting with `30-` loads after udev default rules (`70-persistent-net.rules` if present) but early enough to affect naming
- Modern IPFire CU200 does NOT ship a pre-populated `/etc/udev/rules.d/70-persistent-net.rules` — NIC detection uses `/var/ipfire/ethernet/scanned_nics`
- After writing rules: `udevadm control --reload-rules && udevadm trigger` applies without reboot (for validation), but a full reboot is required to confirm persistence

**PCIe-address alternative (more robust):**
```bash
# Anchor to PCIe slot instead of MAC — survives NIC replacement
ACTION=="add", SUBSYSTEM=="net", KERNELS=="0000:02:00.0", NAME="red0"
ACTION=="add", SUBSYSTEM=="net", KERNELS=="0000:03:00.0", NAME="green0"
```

The PCIe address approach is more robust against MAC address changes (hardware replacement) but requires knowing the PCIe slot-to-port mapping, which must be empirically determined on the specific hardware.

### Pattern 2: firewall.local Anti-Lockout Script

**What:** `/etc/sysconfig/firewall.local` is a shell script called at every firewall reload with `start`, `stop`, and `reload` arguments. Rules in this file are processed before the rest of the WUI-managed ruleset, making them a reliable anti-lockout mechanism.

**When to use:** Write this before any WUI firewall policy changes. The hardcoded management allow rules survive all WUI changes.

**Complete working template:**
```bash
#!/bin/sh
# /etc/sysconfig/firewall.local
# Anti-lockout rules — preserves management access through all firewall changes
# Source: IPFire docs (firewall.local) + community examples

# Load interface variables from IPFire environment
. /var/ipfire/ethernet/settings

case "$1" in
  start)
    # Allow SSH (port 222 — IPFire default) from GREEN to IPFire
    /sbin/iptables -A CUSTOMINPUT -i "${GREEN_DEV}" -p tcp --dport 222 -j ACCEPT

    # Allow WUI (port 444) from GREEN to IPFire
    /sbin/iptables -A CUSTOMINPUT -i "${GREEN_DEV}" -p tcp --dport 444 -j ACCEPT

    # Log all dropped packets (explicit rule for visibility)
    # Note: DROP logging is also controllable via WUI Firewall Options
    ;;

  stop)
    # Mirror every start rule with a delete rule
    # Use -C (check) before -D (delete) to avoid errors on empty chains
    /sbin/iptables -C CUSTOMINPUT -i "${GREEN_DEV}" -p tcp --dport 222 -j ACCEPT 2>/dev/null && \
      /sbin/iptables -D CUSTOMINPUT -i "${GREEN_DEV}" -p tcp --dport 222 -j ACCEPT

    /sbin/iptables -C CUSTOMINPUT -i "${GREEN_DEV}" -p tcp --dport 444 -j ACCEPT 2>/dev/null && \
      /sbin/iptables -D CUSTOMINPUT -i "${GREEN_DEV}" -p tcp --dport 444 -j ACCEPT
    ;;

  reload)
    $0 stop
    $0 start
    ;;

  *)
    echo "Usage: $0 {start|stop|reload}"
    ;;
esac
```

**Key notes:**
- SSH default port on IPFire is **222**, not 22. Port 22 is available but not the default.
- Sourcing `. /var/ipfire/ethernet/settings` loads `${GREEN_DEV}` (value: `green0`) dynamically — no hardcoded interface names.
- `CUSTOMINPUT` processes BEFORE the main input ruleset — these rules cannot be blocked by WUI changes.
- Using `/sbin/iptables -C` before `-D` prevents the harmless-but-noisy "bad rule" error on the `stop` path.
- Apply changes with: `/etc/init.d/firewall restart`

### Pattern 3: /var/ipfire/ethernet/settings Configuration File

**What:** This file is the authoritative zone-to-NIC mapping for IPFire. It is read by IPFire's init scripts and the WUI. It must be consistent with the udev rules.

**File format (verified from IPFire community examples):**
```bash
# /var/ipfire/ethernet/settings
CONFIG_TYPE=4          # 1=GREEN+RED, 3=GREEN+RED+ORANGE, 4=GREEN+RED+BLUE+ORANGE

RED_DEV=red0
RED_MACADDR=aa:bb:cc:dd:ee:01
RED_DRIVER=igc
RED_TYPE=DHCP          # or STATIC, PPPOE
RED_ADDRESS=0.0.0.0
RED_NETMASK=0.0.0.0

GREEN_DEV=green0
GREEN_MACADDR=aa:bb:cc:dd:ee:02
GREEN_DRIVER=igc
GREEN_ADDRESS=192.168.1.1
GREEN_NETMASK=255.255.255.0
GREEN_NETADDRESS=192.168.1.0
GREEN_BROADCAST=192.168.1.255
GREEN_MODE=            # empty for Native, "Bridge" for bridge mode
GREEN_SLAVES=green1,green2   # comma-separated slave NICs for bridge mode

BLUE_DEV=blue0
BLUE_MACADDR=aa:bb:cc:dd:ee:03
BLUE_DRIVER=igc
BLUE_ADDRESS=10.0.10.1
BLUE_NETMASK=255.255.255.0

ORANGE_DEV=orange0
ORANGE_MACADDR=aa:bb:cc:dd:ee:04
ORANGE_DRIVER=igc
ORANGE_ADDRESS=172.16.1.1
ORANGE_NETMASK=255.255.255.0
```

**Key notes for 6-NIC setup:**
- `CONFIG_TYPE=4` enables all four zones (GREEN + RED + BLUE + ORANGE)
- NICs 5 and 6 bridged to GREEN: set `GREEN_MODE=Bridge` and `GREEN_SLAVES=green1,green2`
- After editing: restart networking with `/etc/init.d/network restart` or reboot
- This file is managed by the `setup` utility but can be edited directly — keep a copy in git

### Pattern 4: Backup Include List

**What:** `/var/ipfire/backup/include.user` lists additional files that should be included in IPFire backups. Protects custom files from being lost after backup-restore cycles.

**File format (verified from IPFire docs — April 2024 revision):**
```
# /var/ipfire/backup/include.user
# One path per line; include leading slash
/etc/udev/rules.d/30-persistent-network.rules
/etc/sysconfig/firewall.local
```

**Key notes:**
- Path: `/var/ipfire/backup/include.user` (NOT the addon includes directory)
- Include the leading `/` — the April 2024 docs revision confirmed leading slashes are correct
- `backupctrl include` creates a backup that includes these files
- `backupctrl list` shows all files currently included
- This file itself is included in the standard IPFire backup by default

### Pattern 5: NIC Physical Port Identification Workflow

**What:** On a 6-NIC N100 mini-PC with identical i226-V NICs, you must map each physical port (labeled 1-6 on the chassis) to a MAC address and PCIe slot before writing udev rules.

**Identification sequence:**
```bash
# Step 1: List all NICs with current names and MAC addresses
ip link show

# Step 2: Map interface names to PCIe addresses
for iface in $(ls /sys/class/net | grep -v lo); do
  echo "$iface: $(ethtool -i $iface 2>/dev/null | grep bus-info)"
done

# Step 3: List all i226-V NICs via lspci (Device ID 0x125c)
lspci -nn | grep -i '8086:125c'

# Step 4: Physical port identification using NIC blink/identify
# In IPFire setup utility: type 'setup' → Network config → select NIC → Identify
# The selected NIC's LED blinks for physical identification

# Step 5: Link-state based identification (plug/unplug cable method)
# Plug a cable into port 1 only, observe which interface shows link up:
ip link show | grep -E "(state UP|state DOWN)"
# Note which interface goes UP when cable is in port 1
# Repeat for each port
```

**Intel i226-V identification:**
- PCI device ID: `[8086:125c]`
- Kernel driver: `igc`
- `ethtool -i <iface>` shows `bus-info: 0000:XX:00.0` — matches to `lspci` output
- On N100 platforms, the 6 i226-V NICs appear as consecutive PCIe slots

### Anti-Patterns to Avoid

- **Relying on eth0/eth1 naming:** Non-deterministic after any kernel update. Always use udev-assigned names (green0, red0, etc.).
- **Configuring services before validating NIC persistence:** Complete a full reboot and verify zone assignments before any service configuration.
- **Skipping firewall.local management rules:** WUI rules can lock you out. firewall.local is the safety net.
- **Touching GREEN_SLAVES via direct file edit without understanding bridge mode:** Bridge mode has specific requirements — use the `setup` utility for initial bridge configuration.
- **Modifying suricata.yaml or other package-owned files:** They are overwritten by Core Updates. Use include mechanisms.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Stateful firewall | Custom iptables chains | IPFire's built-in netfilter (WUI-managed) | IPFire's zone engine handles conntrack, SYN checks, and inter-zone policies correctly; custom chains break WUI rule ordering |
| NIC naming persistence | Custom init scripts to rename interfaces | udev rules at `/etc/udev/rules.d/` | udev is the correct kernel mechanism; init scripts run too late in the boot process |
| Management anti-lockout | Adding ACCEPT rules directly to INPUT chain | `CUSTOMINPUT` chain in firewall.local | Direct INPUT chain modifications are overwritten by IPFire's firewall restart |
| NAT/masquerade | iptables MASQUERADE rules in firewall.local | WUI Firewall Options — enable masquerade per zone | WUI masquerade rules are properly coordinated with zone routing; custom MASQUERADE rules cause rule ordering conflicts |
| Backup management | Shell scripts that tar custom files | `/var/ipfire/backup/include.user` + `backupctrl` | IPFire's backup system is integrated with Core Update compatibility checks |

**Key insight:** IPFire is a sealed appliance OS. Its internal mechanisms (WUI-managed iptables, zone-aware routing, firewall.local hooks) are designed to work together. Bypassing them with raw iptables commands outside of firewall.local or with custom init scripts creates hard-to-debug conflicts that appear only after reboots or Core Updates.

---

## Default Firewall Posture (Fresh Install)

This is critical context for Phase 1 — understanding what is already configured vs. what needs explicit action.

| Zone Pair | Default Policy | Requires Action? |
|-----------|----------------|------------------|
| RED inbound → GREEN | BLOCKED (default-deny) | No — correct by default |
| RED inbound → ORANGE | BLOCKED (default-deny) | No — correct by default |
| RED inbound → BLUE | BLOCKED (default-deny) | No — correct by default |
| GREEN outbound → RED | ALLOWED (forward = open) | No — correct for basic connectivity |
| GREEN → ORANGE | OPEN (allowed by default) | YES — must explicitly restrict for zone isolation |
| GREEN → BLUE | OPEN (allowed by default) | Evaluate — may need restriction |
| ORANGE → GREEN | BLOCKED | No — correct by default |
| BLUE → GREEN | BLOCKED | No — correct by default |
| GREEN masquerade (NAT) | ENABLED by default | No for GREEN; YES for ORANGE and BLUE |
| ORANGE masquerade (NAT) | DISABLED by default | YES — enable if ORANGE hosts need internet |
| BLUE masquerade (NAT) | DISABLED by default | YES — enable if BLUE hosts need internet |

**Critical finding:** GREEN-to-ORANGE is OPEN by default. If ORANGE is provisioned as a DMZ, trusted LAN hosts can reach DMZ hosts without any firewall rules. An explicit FORWARD rule blocking GREEN→ORANGE (with specific pinholes for allowed services) must be added in Phase 1.

**Stateful firewall is active by default:** conntrack tracks connection state; "new not SYN" packets are dropped and logged as `DROP_NEWNOTSYN`; INVALID state packets are dropped as `DROP_CTINVALID`. No configuration needed.

---

## Common Pitfalls

### Pitfall 1: NIC Order Changes After Core Update (CRITICAL)

**What goes wrong:** After a Core Update that ships a new kernel, the igc driver probes 6x identical i226-V NICs in a potentially different order. Without udev anchoring, green0 may become the WAN interface. This is a silent security failure — traffic flows but zones are wrong.

**Why it happens:** Linux probe order is non-deterministic when all NICs are the same chip (i226-V). The `igc` driver binds them in PCIe enumeration order, which can vary by kernel version. IPFire's MAC-based zone mapping in ethernet/settings knows which MAC belongs to which zone, but without udev, the kernel may assign a different name to that MAC.

**How to avoid:** Write udev rules anchored to MAC address (or PCIe bus address) in Phase 1 before any other configuration. After every Core Update, run a validation script: `ip link show | grep -E 'red0|green0|blue0|orange0'` and compare MACs against the documented nic-map.md.

**Warning signs:** After a Core Update, `ip link show` output shows NICs in different order than before; WAN traffic appears on a non-RED interface in firewall logs.

### Pitfall 2: Management Lockout (CRITICAL)

**What goes wrong:** Enabling "Outgoing Blocked" policy or any broad deny rule in the WUI instantly cuts SSH (port 222) and WUI (port 444) access. IPFire has no automatic rollback window. Recovery requires physical console.

**Why it happens:** WUI rule changes take effect immediately on save. The "Outgoing Blocked" option controls IPFire's own outbound traffic — enabling it without exceptions blocks DNS, NTP, and Pakfire update traffic too.

**How to avoid:** Write firewall.local with CUSTOMINPUT ACCEPT rules for ports 222 and 444 from GREEN before any WUI policy changes. CUSTOMINPUT is processed before the main ruleset — these rules cannot be blocked by WUI changes. Always have physical console access before structural rule changes.

**Warning signs:** WUI page times out immediately after saving a firewall rule (not the usual reload delay).

### Pitfall 3: Backup Include List Gap

**What goes wrong:** udev rules and firewall.local are not in IPFire's default backup scope. After a restore, zone assignments and anti-lockout rules are gone.

**Why it happens:** IPFire's backup covers `/var/ipfire/` contents by default. Files in `/etc/udev/rules.d/` and `/etc/sysconfig/` are outside this path.

**How to avoid:** Populate `/var/ipfire/backup/include.user` in Phase 1 with the udev rules file and firewall.local. Verify with `backupctrl list`.

### Pitfall 4: GREEN-to-ORANGE Open by Default

**What goes wrong:** Phase 3 configures ORANGE as a DMZ. GREEN-to-ORANGE traffic is open by default — trusted LAN devices can reach DMZ services without any rules. Zone isolation is not enforced.

**Why it happens:** IPFire's default forward policy is ALLOWED for traffic originating from trusted zones. ORANGE is not treated as fully untrusted by the default policy.

**How to avoid:** In Phase 1, after provisioning all zones, add explicit FORWARD rules: block GREEN→ORANGE by default, and add pinholes only for explicitly required service ports.

### Pitfall 5: Core Update Overwrites firewall.local Alternative Locations

**What goes wrong:** Some sources suggest putting custom rules in other locations. Only `/etc/sysconfig/firewall.local` is explicitly preserved across Core Updates.

**Why it happens:** IPFire package updates own files outside the `/var/ipfire/` hierarchy. The `firewall.local` file at `/etc/sysconfig/` is in the explicitly-preserved list.

**How to avoid:** All custom iptables rules go in `/etc/sysconfig/firewall.local` only. Add this file to `include.user`.

---

## Code Examples

### Verify NIC-to-Zone Mapping After Reboot

```bash
#!/bin/bash
# configs/scripts/validate-nics.sh
# Run after every reboot or Core Update

# Source expected MACs from documented nic-map
RED_EXPECTED_MAC="aa:bb:cc:dd:ee:01"
GREEN_EXPECTED_MAC="aa:bb:cc:dd:ee:02"
BLUE_EXPECTED_MAC="aa:bb:cc:dd:ee:03"
ORANGE_EXPECTED_MAC="aa:bb:cc:dd:ee:04"

FAIL=0

check_nic() {
  local zone="$1"
  local dev="$2"
  local expected_mac="$3"
  local actual_mac
  actual_mac=$(cat /sys/class/net/${dev}/address 2>/dev/null)
  if [ "$actual_mac" = "$expected_mac" ]; then
    echo "PASS: ${zone} (${dev}) MAC=${actual_mac}"
  else
    echo "FAIL: ${zone} (${dev}) expected MAC=${expected_mac} got MAC=${actual_mac:-MISSING}"
    FAIL=1
  fi
}

check_nic "RED"    "red0"    "$RED_EXPECTED_MAC"
check_nic "GREEN"  "green0"  "$GREEN_EXPECTED_MAC"
check_nic "BLUE"   "blue0"   "$BLUE_EXPECTED_MAC"
check_nic "ORANGE" "orange0" "$ORANGE_EXPECTED_MAC"

[ $FAIL -eq 0 ] && echo "ALL NICS PASS" || echo "NIC VALIDATION FAILED"
exit $FAIL
```

### Reload firewall.local

```bash
# Apply firewall.local changes without full firewall restart
/etc/init.d/firewall restart

# Or call the script directly (for testing only)
/etc/sysconfig/firewall.local reload
```

### NIC Identification Commands

```bash
# List all NICs with MAC and link state
ip link show

# Map interface to PCIe slot (for all non-loopback interfaces)
for iface in $(ls /sys/class/net/ | grep -v lo); do
  bus=$(ethtool -i $iface 2>/dev/null | awk '/bus-info/ {print $2}')
  mac=$(cat /sys/class/net/$iface/address)
  echo "$iface  PCIe=$bus  MAC=$mac"
done

# List i226-V NICs via PCI device ID
lspci -nn | grep '8086:125c'

# Check driver info for a specific interface
ethtool -i red0
```

### Verify firewall.local Rules Are Active

```bash
# Verify CUSTOMINPUT rules for management access
iptables -L CUSTOMINPUT -n -v | grep -E '(222|444)'

# Show all custom chains
iptables -L CUSTOMINPUT -n -v
iptables -L CUSTOMFORWARD -n -v
```

### Backup Include List Population

```bash
# Populate /var/ipfire/backup/include.user
cat > /var/ipfire/backup/include.user << 'EOF'
/etc/udev/rules.d/30-persistent-network.rules
/etc/sysconfig/firewall.local
EOF

# Verify backup includes these files
backupctrl list | grep -E '(udev|firewall.local)'

# Create a backup
backupctrl include
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `/etc/udev/rules.d/70-persistent-net.rules` auto-generated | Must write rules manually; no auto-generation in IPFire CU200 | CU200 / modern udev | Phase 1 must explicitly write udev rules — do not expect them to be auto-created |
| Promtail log agent | Grafana Alloy 1.14.1 | Promtail EOL Feb 28, 2026 | Not relevant to Phase 1, but noted for later phases |
| IPFire Shalla domain blocklist | IPFire DBL (beta in CU200) | CU200, March 2026 | DBL is out of scope for Phase 1 |
| Debian-style persistent NIC naming (`enp5s0`) | udev rule with `NAME=` to force zone names | Always on IPFire | IPFire's zone scripts expect `green0`, `red0` — predictable naming must use `NAME=` rule, not rename scripts |

**Deprecated/outdated:**
- `net.ifnames=0` kernel parameter approach: Disables predictable names globally — not recommended; use explicit `NAME=` rules per NIC instead.
- `/etc/udev/rules.d/70-persistent-net.rules` auto-generation: This mechanism is not active in modern IPFire. Do not rely on it.

---

## Open Questions

1. **Exact PCIe bus addresses for the specific N100 hardware**
   - What we know: PCIe addresses are hardware-specific (e.g., `0000:02:00.0`); can be read with `lspci` on the live system
   - What's unclear: Which PCIe slot maps to which physical port label on the specific mini-PC chassis — this requires physical testing
   - Recommendation: Use the cable-plug/LED-blink method to document the physical-to-PCIe mapping before writing udev rules; document in `docs/nic-map.md`

2. **Whether GREEN_MODE=Bridge and GREEN_SLAVES need to be set via setup utility or can be set directly in ethernet/settings**
   - What we know: The field exists in ethernet/settings; bridge mode is documented
   - What's unclear: Whether editing ethernet/settings directly for bridge config causes WUI conflicts
   - Recommendation: Use the `setup` utility for initial bridge configuration; then export the resulting ethernet/settings to git

3. **Whether udev rules on IPFire survive Core Updates**
   - What we know: `/etc/udev/rules.d/` is in the system path, not in `/var/ipfire/`; include.user covers it for backup
   - What's unclear: Whether Core Updates overwrite files in `/etc/udev/rules.d/` directly
   - Recommendation: Add udev rules file to `include.user` and verify after every Core Update as part of the post-update validation script

---

## Validation Architecture

`workflow.nyquist_validation` is `true` in `.planning/config.json` — validation architecture is required.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Bash shell scripts (no external test framework — IPFire is a firewall appliance, not a software project) |
| Config file | None — scripts live in `scripts/` directory in the git repo |
| Quick run command | `bash /root/firewall-repo/scripts/validate-nics.sh` |
| Full suite command | `bash /root/firewall-repo/scripts/validate-phase1.sh` (to be created in Wave 0) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PLAT-01 | Each zone NIC MAC matches documented MAC | Integration | `bash scripts/validate-nics.sh` | Wave 0 |
| PLAT-01 | NIC assignments survive reboot | Integration | `reboot; ssh ipfire bash scripts/validate-nics.sh` | Wave 0 |
| PLAT-02 | SSH (222) accessible after firewall restart | Integration | `nc -zv 192.168.1.1 222` from GREEN host | Wave 0 |
| PLAT-02 | WUI (444) accessible after firewall restart | Integration | `curl -sk https://192.168.1.1:444` from GREEN host | Wave 0 |
| PLAT-03 | Git repo exists with correct directory structure | Smoke | `ls /root/firewall-repo/{configs,scripts,docs,services,validation,rollback,manifests,decision-log}` | Wave 0 |
| PLAT-04 | Hostname set correctly | Smoke | `hostname` returns expected value | Manual |
| PLAT-05 | include.user contains udev rules and firewall.local paths | Smoke | `grep udev /var/ipfire/backup/include.user && grep firewall.local /var/ipfire/backup/include.user` | Wave 0 |
| FW-01 | Inbound connection from RED is blocked | Integration | `nmap -Pn -p 80,443,22,222,444 <RED_IP>` from external — all closed/filtered | Manual (requires external vantage point) |
| FW-02 | GREEN host reaches internet (NAT active) | Integration | `curl http://checkip.amazonaws.com` from GREEN host — returns RED IP | Manual (requires GREEN client) |
| FW-03 | GREEN cannot reach ORANGE without explicit rule | Integration | `ping 172.16.1.x` from GREEN host — times out | Manual (requires GREEN client + ORANGE host) |
| FW-05 | Dropped packets logged in /var/log/messages | Smoke | `grep 'DROP\|FORWARDFW' /var/log/messages` returns entries after blocked connection attempt | Integration |
| FW-06 | Firewall rules survive reboot | Integration | Apply test rule; reboot; verify rule still present via `iptables -L` | Integration |
| FW-07 | CUSTOMINPUT rules loaded before main ruleset | Smoke | `iptables -L CUSTOMINPUT -n -v` shows 222 and 444 ACCEPT rules | Integration |

### Sampling Rate

- **Per task commit:** `bash /root/firewall-repo/scripts/validate-nics.sh`
- **Per wave merge:** `bash /root/firewall-repo/scripts/validate-phase1.sh`
- **Phase gate:** All integration tests pass (including reboot persistence test) before declaring Phase 1 complete

### Wave 0 Gaps

- [ ] `scripts/validate-nics.sh` — validates PLAT-01 MAC-to-zone mapping
- [ ] `scripts/validate-phase1.sh` — runs all Phase 1 integration tests
- [ ] `docs/nic-map.md` — physical port documentation template
- [ ] `configs/udev/30-persistent-network.rules` — placeholder with correct structure (actual MACs filled in during execution)
- [ ] `configs/firewall/firewall.local` — working template with management allow rules

*All test files require the live hardware to determine actual MAC addresses — Wave 0 creates the framework with placeholder values.*

---

## Sources

### Primary (HIGH confidence)

- [IPFire Backup Documentation](https://www.ipfire.org/docs/configuration/system/backup) — backup include.user path and syntax; backupctrl commands
- [IPFire firewall.local Documentation](https://www.ipfire.org/docs/configuration/firewall/firewall-local) — CUSTOMINPUT chain names, script structure, persistence behavior
- [IPFire Zone Configuration](https://www.ipfire.org/docs/configuration/network/zoneconf) — zone modes (Native/Bridge), NIC assignment, four-zone hard limit
- [IPFire Firewall Default Policy](https://www.ipfire.org/docs/configuration/firewall/default-policy) — zone default allow/deny table, fresh install behavior
- [IPFire SSH Documentation](https://www.ipfire.org/docs/configuration/system/ssh) — default SSH port is 222, not 22; temporary and permanent SSH enable modes
- [IPFire CU200 Release Notes](https://www.ipfire.org/blog/ipfire-2-29-core-update-200-released) — kernel 6.18.7 LTS, igc driver, Suricata 8.0.3

### Secondary (MEDIUM confidence)

- IPFire community search results — `/var/ipfire/ethernet/settings` complete field format verified from multiple community posts
- [RHEL Consistent NIC Naming Documentation](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/configuring_and_managing_networking/consistent-network-interface-device-naming_configuring-and-managing-networking) — udev NAME= rule syntax; ATTR{type}=="1" Ethernet match; ATTR{address}== MAC match
- [IPFire Community: backup own settings/files](https://community.ipfire.org/t/backup-own-settings-files/6803) — include.user is preferred over addons/includes; leading slash syntax confirmed
- [IPFire Community: firewall.local examples](https://community.ipfire.org/t/firewall-local-and-custom-rules/9040) — verified start/stop case structure
- [IPFire Community: FORWARDFW logging](https://community.ipfire.org/t/the-log-shows-forwardfw-i-do-not-understand/10339) — FORWARDFW prefix applies to both ACCEPT and DROP logged rules
- [IPFire Community: CWWK N100/N150](https://community.ipfire.org/t/cwwk-n100-n150-is-a-good-option/13811) — N100 hardware context; single-channel DDR5 bandwidth concern
- [OpenWrt: i225/i226 interface ordering changes after upgrade](https://github.com/openwrt/openwrt/issues/17955) — cross-platform corroboration of NIC ordering pitfall

### Tertiary (LOW confidence — requires live system validation)

- Whether udev rules in `/etc/udev/rules.d/` survive Core Updates without include.user — inferred from how Core Updates work but not explicitly documented
- Exact PCIe slot-to-physical-port mapping for the specific N100 mini-PC hardware — hardware-specific; must be determined empirically
- Whether `GREEN_SLAVES=green1,green2` syntax in ethernet/settings works for bridge config or requires setup utility — community evidence exists but not authoritatively documented

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all components are native IPFire; no external packages
- Architecture: HIGH — udev syntax, firewall.local chains, ethernet/settings format all verified from official docs and community
- Pitfalls: HIGH — NIC ordering pitfall corroborated cross-platform; management lockout documented in multiple IPFire community cases
- Default firewall posture: HIGH — verified from official IPFire default policy documentation
- Backup include.user format: HIGH — verified from April 2024 documentation revision
- SSH port 222 default: HIGH — from official IPFire SSH docs

**Research date:** 2026-03-21
**Valid until:** 2026-06-21 (stable documentation; IPFire 2.x conventions change slowly)
