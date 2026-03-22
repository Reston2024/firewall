# Pitfalls Research

**Domain:** IPFire firewall appliance on Intel N100 hardware (6x i226-V NICs)
**Researched:** 2026-03-21
**Confidence:** HIGH — all findings verified through IPFire community forums, official documentation, and cross-platform corroboration

---

## Critical Pitfalls

### Pitfall 1: NIC Interface Ordering Breaks After Kernel or Core Updates

**What goes wrong:**
Linux assigns NIC names (eth0, eth1, enp2s0, etc.) based on probe order at boot. On multi-NIC appliances with 6x Intel i226-V controllers, the probe order can change after a kernel upgrade or IPFire Core Update. When order changes, zone assignments silently swap: what was GREEN becomes ORANGE, what was WAN (RED) becomes a trusted LAN zone. Firewall policy that was tight becomes porous — the worst case is WAN traffic being forwarded as trusted GREEN traffic.

On OpenWrt, upgrading from 23.05 to 24.10 caused i225/i226 interface naming order to change without warning. On Proxmox, a PVE 8.4→9.1 upgrade caused two of six i226-V ports to disappear entirely. IPFire Core Updates ship new kernel versions — the same instability applies.

**Why it happens:**
IPFire historically tied zone-to-NIC assignments to MAC addresses (stored in `/var/ipfire/ethernet/settings`), not PCIe slot addresses. When the kernel probes NICs in a different order during boot, the MAC-to-name mapping via the `igc` driver may resolve to a different `ethX` or `enp` name. The zone assignment then references the right MAC but the OS now associates that MAC with a different logical name than before.

**How to avoid:**
1. Before any Core Update, document the current mapping: `ip link show` output, MAC addresses, PCIe addresses (`lspci -nn | grep -i ethernet`), and physical port labels.
2. Create explicit udev rules anchoring each NIC to its interface name by PCIe address, not MAC address. Use `/etc/udev/rules.d/10-persistent-net.rules` with `KERNELS=="0000:<pci-addr>"` matching.
3. After every Core Update, run a post-update validation script that checks each MAC is still associated with the expected zone.
4. Label physical ports on the appliance chassis. Do not rely on mental models.

**Warning signs:**
- After a Core Update, `ip link show` output differs from pre-update
- Zone Configuration WUI shows NICs listed in a different order
- Unexpected traffic reaching a zone (e.g., WAN traffic visible on MGMT interface)
- `dmesg` at boot shows `igc` driver probing NICs in different PCIe bus order

**Phase to address:** Platform verification phase (Phase 1) — establish baseline MAC-to-PCIe mapping and write udev anchors before any other configuration is applied.

---

### Pitfall 2: Management Lockout During Firewall Rule Changes

**What goes wrong:**
A firewall rule change — especially enabling "Outgoing Blocked" default policy, adding a location block, or adding a zone-to-zone deny — can instantly revoke access to the WUI (port 444) and SSH (port 22). With no console attached and no recovery procedure, the box must be physically accessed or power-cycled into a recovery mode. A 2024 IPFire community case shows this happening from a log-relocation change that caused the WUI to refuse browser connections on reboot.

Core Update 150 caused a documented case where all devices were locked out after a geoblocking rule inadvertently blocked the GREEN interface. Core Update 199 fixed a race condition where applied firewall rules could be dropped mid-insertion — meaning even correct rules could temporarily produce a locked-out state on older versions.

**Why it happens:**
IPFire applies firewall rules immediately on save. There is no "test for 60 seconds then rollback" mechanism (unlike pfSense). If a rule blocks management traffic, there is no automatic recovery. The "Outgoing Blocked" policy is particularly dangerous because it controls IPFire's own traffic, not just forwarded traffic — a common source of confusion.

**How to avoid:**
1. Always have physical console access or a local KVM before making structural firewall changes.
2. Maintain a permanent, explicit allow rule for management: `CUSTOMINPUT` rule allowing port 444 and 22 from GREEN subnet — add this in `firewall.local` so it is never overwritten.
3. Test structural rule changes (default policy switches, geoblocking) from the console, not a remote session.
4. When enabling "Outgoing Blocked", add all required exceptions first (DNS, NTP, Pakfire port 443) before enabling the policy — not after.
5. Keep an out-of-band management path: a dedicated physical management interface on a separate MGMT zone that has an unconditional WUI allow rule.

**Warning signs:**
- WUI connection times out after saving a rule (not the usual save-and-reload delay)
- SSH connection refused immediately after a rule change
- Attempting to enable default-deny without first inventorying what IPFire itself needs outbound

**Phase to address:** Anti-lockout protections must be in place in Phase 1 (platform setup), before any zone or firewall configuration is attempted in later phases.

---

### Pitfall 3: Suricata Rule Overload Saturates the N100

**What goes wrong:**
Enabling all rule categories from Emerging Threats (the default IPFire IPS selection) causes Suricata to consume 1 GB+ of RAM and pegs one or more CPU cores continuously. On the N100 (4 E-cores, 16 GB single-channel RAM), this leaves insufficient headroom for the telemetry stack (Grafana, log forwarder, etc.) and introduces packet-drop events under normal home/SOHO traffic loads.

The N100's single-channel memory architecture is a hidden bottleneck: even with 16 GB installed, memory bandwidth is constrained to one channel. Deep packet inspection is memory-bandwidth-intensive; the N100 cannot sustain full Emerging Threats rule evaluation at multi-gigabit speeds.

**Why it happens:**
The IPFire WUI presents Emerging Threats rules as categorized checkboxes. New users enable everything for "maximum security." The rule count is enormous — Emerging Threats is modified daily and contains more rules than Suricata loads by default. IPFire's process graphs do not display Suricata's memory consumption, so resource exhaustion is invisible until the system starts swapping.

Additionally, CVE-2024-23836 (Suricata < 8.0.2) allows crafted traffic to force unbounded memory growth — on a constrained platform this becomes a denial-of-service against the IDS itself.

**How to avoid:**
1. Enable only rule categories relevant to the threat model: for a home/SOHO gateway, enable policy, malware C2, and exploit categories; disable scanning, ICS, and protocol-specific categories for protocols not present on the network.
2. Start with IDS-only mode (monitor, not block) before enabling IPS. Measure CPU and memory impact before committing to blocking mode.
3. Set Suricata memory limits in `suricata.yaml`: configure `memcap` for the flow engine, stream engine, and defrag module explicitly.
4. Update Suricata to 8.0.2+ before enabling any IPS functionality to close CVE-2024-23836.
5. Monitor Suricata resource use via `htop` and `/proc` since the IPFire WUI does not surface it. Add a monitoring cron that alerts when Suricata RSS exceeds a threshold.

**Warning signs:**
- `htop` shows one CPU core at 100% continuously after enabling IPS
- System starts using swap (`free -h` shows swap consumption growing)
- Ping latency to GREEN interface increases from <1ms to 10ms+ under normal traffic
- `/var/log/messages` contains `igc` error messages suggesting NIC buffer exhaustion

**Phase to address:** IDS/IPS phase — rule selection and memory limits must be established as part of the initial Suricata configuration, not tuned later.

---

### Pitfall 4: Docker Bypasses IPFire Zone Firewall Rules

**What goes wrong:**
When Docker is installed on the IPFire host (for telemetry services like Grafana or a log forwarder), Docker inserts its own iptables chains and NAT rules at startup. These chains intercept traffic before IPFire's zone rules are evaluated, effectively bypassing zone-based access controls. Docker creates a `DOCKER-USER` chain inserted into `FORWARD` and inserts unconditional `ACCEPT` rules into the nat table for port-mapped containers. Published container ports become reachable from zones that should not have access — including potentially RED (WAN).

In environments using `firewalld`, Docker creates a zone called `docker` with target `ACCEPT` and adds a forwarding policy allowing traffic from ANY zone into the docker zone. IPFire does not use `firewalld`, but the iptables chain manipulation pattern is the same.

**Why it happens:**
Docker's networking model predates nftables and was designed for single-server deployments, not firewall appliances. It assumes it owns iptables. IPFire manages iptables very carefully through its own chain management (`CUSTOMINPUT`, `CUSTOMFORWARD`, etc.), and Docker's aggressive rule insertion conflicts with this model. There is no Docker-aware isolation built into IPFire's firewall engine.

**How to avoid:**
1. Do not run Docker on the IPFire host. Run Docker on a dedicated host/VM behind IPFire (e.g., in the GREEN or ORANGE zone). This is the only fully safe architecture.
2. If Docker must run on the IPFire host (acceptable only for lightweight telemetry agents): set `"iptables": false` in `/etc/docker/daemon.json` to disable Docker's iptables management. Then manually create the required NAT and forward rules using IPFire's `firewall.local` (using `CUSTOMFORWARD` and `CUSTOMPOSTROUTING` chains).
3. Never use `--publish` (`-p`) flags with containers when Docker's iptables management is disabled — ports must be explicitly allowed via IPFire firewall rules instead.
4. After any Docker daemon restart, verify IPFire's firewall rules are intact: `iptables -L FORWARD -n -v` should show IPFire's chains, not just Docker's.

**Warning signs:**
- After installing Docker, traffic that was previously blocked by zone rules starts passing
- `iptables -L FORWARD -n` shows Docker chains with broad ACCEPT rules at the top
- Container ports are reachable from the RED interface without explicit firewall rules
- IPFire WUI shows no firewall drops for traffic that should be blocked

**Phase to address:** Docker/telemetry phase — the iptables isolation architecture must be designed before any Docker service is deployed, not retrofitted after.

---

### Pitfall 5: IPFire Core Updates Overwrite Custom Configuration Files

**What goes wrong:**
IPFire Core Updates overwrite files that users commonly customize. Confirmed overwrites include:
- `suricata.yaml` (confirmed in Core Update 194): all custom EVE JSON logging configuration, syslog forwarder settings, and memory tuning were reset to defaults.
- Firewall-related configuration files managed by the WUI (not `firewall.local`) are regenerated from the internal database on update.
- Zone DNS and unbound zone files: a December 2024 case showed zone files missing from `/etc/unbound/zonefiles/` after a backup restore across Core Updates.

The inverse problem also occurs: Core Update 201 introduced a new DNS firewall requirement (access to `primary.dbl.ipfire.org`) that users with "Outgoing Blocked" policy had not added, causing DNS firewall functionality to silently break post-update.

**Why it happens:**
IPFire treats files in managed directories as owned by the package system. Custom modifications to package-owned files are not preserved. The documentation does not clearly identify which files are safe to modify and which will be overwritten. There is no pre-update diff or warning about pending file overwrites.

**How to avoid:**
1. Never modify Suricata or other package-owned config files directly. Instead, use the include mechanism: create a drop-in configuration directory (e.g., `/etc/suricata/conf.d/`) and reference it from a file that survives updates, or script the customization as a post-update hook.
2. Store all custom rules in `/etc/sysconfig/firewall.local` — this file is explicitly preserved across updates.
3. Add custom files to the IPFire backup include list: create entries in `/var/ipfire/backup/addons/includes/` listing every custom file path.
4. Before every Core Update, create a checkpoint: `backupctrl include` to capture the current state.
5. After every Core Update, run a validation script that checks key configuration values (Suricata EVE output enabled, log destinations correct, custom rules present).
6. Read the Core Update release notes before applying — look for "new firewall requirements" or "configuration changes."

**Warning signs:**
- After a Core Update, Suricata logs stop appearing in the telemetry pipeline
- Custom iptables rules in `suricata.yaml` are absent from the running config
- `diff /var/ipfire/backup/<pre-update>/<file> <file>` shows unexpected changes
- Services depending on custom configuration begin logging errors

**Phase to address:** Reproducibility phase — the backup include list and post-update validation script must be established alongside the initial configuration of each service.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Skip udev NIC anchoring, rely on IPFire MAC-based assignment | Faster initial setup | Zone assignment silently breaks after kernel update; WAN traffic routed to wrong zone | Never |
| Enable all Emerging Threats rule categories | "Maximum security" appearance | 1 GB+ RAM consumption, CPU saturation, packet drops | Never on N100 |
| Modify `suricata.yaml` directly for EVE logging | Quick to configure | Configuration wiped by Core Updates | Never — use include mechanism |
| Run Docker on IPFire host without disabling `iptables` in Docker daemon | Containers work immediately | Docker bypass of zone firewall; published ports exposed past security policy | Never for production |
| Store custom iptables rules as ad-hoc commands outside `firewall.local` | Quick to test | Rules lost on reboot or Core Update | Only during active debugging session, never committed |
| Restore backup across a major Core Update version gap | Saves re-configuration time | MAC-based firewall rules break; zone files may be missing; service configs out of schema | Never without verifying compatibility first |
| Skip post-update validation | Faster update cycle | Silent misconfiguration accumulates until a security incident reveals it | Never |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Suricata + Syslog forwarder | Setting EVE JSON output in `suricata.yaml` directly | Use an include-compatible drop-in config that survives Core Updates; document in repo |
| Suricata + telemetry pipeline | Enabling all rule sets before measuring impact | Baseline CPU/RAM with minimal rules first; add categories incrementally with impact measurement |
| Docker + IPFire iptables | Running Docker with default iptables management enabled | Set `"iptables": false` in daemon.json; use IPFire `firewall.local` for all container networking rules |
| IPFire backup + git repo | Putting only `backupctrl` tar archives in git | Extract and commit individual config files (firewall rules, `firewall.local`, zone settings, Suricata drop-ins) for diff-readable history |
| i226-V NICs + auto-negotiation | Relying on auto-negotiation with 1G-only upstream equipment | Test link speed explicitly with `ethtool ethX`; add `/etc/ethtool.conf` force-speed entries if flapping occurs |
| IPFire update + "Outgoing Blocked" policy | Applying Core Updates without reading release notes for new firewall requirements | Read release notes; check for new IP/port requirements before applying updates |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| All Emerging Threats rules enabled on N100 | CPU core pegged at 100%, increased latency, packet drops | Enable only relevant rule categories; set Suricata memcap limits | Immediately on traffic above ~200 Mbps with full rule set |
| EVE JSON firehose logging to local NVMe without rotation | `/var/log/suricata/eve.json` grows to fill NVMe; Suricata stops writing; syslog fills | Configure `rotate-interval` in Suricata EVE output; add size-based log rotation via logrotate; monitor disk via cron | Within hours on a busy network; within days on a quiet one |
| Telemetry stack (Grafana + log forwarder) on same host as Suricata | Memory contention; both Suricata and telemetry degrade simultaneously | Measure combined memory footprint in IDS-only mode before enabling IPS; consider off-box telemetry | When Suricata memory growth triggers swap usage |
| Single-channel DDR5 memory bandwidth saturation | All four N100 cores busy but throughput still degrades at 2+ Gbps | Accept 1 Gbps as practical IDS ceiling for this hardware; do not attempt 2.5G IDS | At sustained throughput above ~1.4 Gbps with IDS enabled |
| Docker containers logging to stdout without a log size limit | Container logs in `/var/lib/docker/containers/*/` fill NVMe | Set `"log-driver": "json-file"` with `"max-size"` and `"max-file"` in Docker daemon.json | After several days of active container operation |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| SSH permanently enabled, accessible from GREEN without IP restriction | Brute force from any GREEN host; lateral movement if any GREEN device is compromised | Restrict SSH to specific management subnet IP; use public key authentication only; disable root SSH login via `sshd_config` |
| WUI (port 444) accessible from all GREEN zones | Any device on any LAN can attempt WUI access | Restrict WUI access to the dedicated MGMT zone/subnet via `CUSTOMINPUT` rule |
| No explicit allow rule for management in `firewall.local` | An inadvertent default-deny rule change locks out all management permanently | Maintain a hardcoded management allow rule in `firewall.local` that cannot be removed by WUI rule changes |
| Orange zone with pinholes to Green using broad subnet ranges | DMZ compromise leads to Green LAN access via overly permissive pinhole | Scope pinholes to exact IP:port pairs; Suricata must inspect Orange-to-Green traffic |
| Docker published ports not explicitly blocked at zone boundaries | Container service becomes reachable from RED (WAN) via Docker iptables bypass | Disable Docker iptables management; never use `--publish` without corresponding explicit IPFire allow rules |
| IPFire WUI on default self-signed cert | MITM on management traffic; cert pinning warnings train users to ignore security warnings | Replace self-signed cert with a privately issued cert from an internal CA during hardening phase |

---

## "Looks Done But Isn't" Checklist

- [ ] **NIC Zone Assignment:** Zone configuration WUI shows correct zones — verify actual MAC-to-PCIe binding with `ip link show` and `lspci`; confirm udev anchors are in place and survive a reboot.
- [ ] **Firewall Default Deny:** "Inbound blocked" is set — verify by attempting a connection from RED to GREEN; verify IPFire's own outbound traffic (Pakfire, DNS, NTP) still works after enabling "Outgoing Blocked."
- [ ] **Suricata Active:** IPS logs exist in `/var/log/suricata/` — verify Suricata is actually inspecting the correct zones (not just enabled but not bound to any interface); confirm with `curl http://testmynids.org/uid/index.html` and check for alert in eve.json.
- [ ] **Log Rotation Configured:** Suricata is logging — verify `logrotate -d /etc/logrotate.d/suricata` shows correct rotation policy; verify disk usage of `/var/log/suricata/` is not growing unbounded.
- [ ] **Docker Network Isolation:** Containers are running — verify IPFire zone rules still block traffic they should block with Docker running; check `iptables -L FORWARD -n` for unexpected Docker ACCEPT rules.
- [ ] **Custom Config Preserved:** Configurations appear correct — verify all custom files are in the IPFire backup include list; do a test restore to a snapshot and confirm customizations survive.
- [ ] **Post-Update Validation:** Core Update applied — run validation script checking: NIC order unchanged, Suricata config not reverted, `firewall.local` intact, zone assignments correct.
- [ ] **Management Anti-Lockout:** Management rules appear in WUI — verify the hardcoded `firewall.local` allow rule for management cannot be overridden by a WUI default-deny change.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| NIC order change after update locks WAN to wrong zone | HIGH | Physical console access required; run `setup` to reassign NICs to zones; verify with `ip link show` and `cat /var/ipfire/ethernet/settings`; apply udev anchor rules to prevent recurrence |
| WUI/SSH lockout from firewall rule change | MEDIUM | Physical console login as root; run `setup` or edit `/etc/sysconfig/firewall.local` to restore management access; reboot to apply |
| Suricata consuming all RAM, system in swap | LOW-MEDIUM | SSH to box; `systemctl stop suricata`; edit rule selections in WUI to reduce scope; set `memcap` limits in Suricata config; restart Suricata in IDS-only mode first |
| Core Update overwrites suricata.yaml customizations | MEDIUM | Restore customizations from git repo; add config to backup includes list; configure drop-in include mechanism to prevent recurrence |
| Docker bypasses zone rules exposing service to WAN | HIGH | `systemctl stop docker`; set `"iptables": false` in `/etc/docker/daemon.json`; audit iptables rules for Docker remnants; restart Docker; add explicit IPFire firewall rules for required ports only |
| EVE JSON fills disk, Suricata stops | LOW | `systemctl stop suricata`; delete or truncate `eve.json`; configure log rotation; restart Suricata; monitor disk |
| Backup restore fails across Core Update version gap | HIGH | Do not restore across major version gaps; instead do a fresh install of the target version, apply the backup, then manually reconcile diverged config files; use git diff to identify what changed |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| NIC interface ordering breaks after kernel update | Phase 1: Platform Verification | Reboot after writing udev anchors; confirm `ip link show` order is stable; document MAC-to-zone mapping in repo |
| Management lockout during firewall changes | Phase 1: Platform Verification | Confirm `firewall.local` management allow rule survives a WUI default-deny toggle; test SSH and WUI access from MGMT zone only |
| Suricata rule overload saturates N100 | Phase 3: IDS/IPS Setup | Measure CPU and RAM with `htop` under load with selected rule categories; confirm no swap usage; verify <50% CPU headroom |
| Docker bypasses zone firewall rules | Phase 4: Docker/Telemetry | After deploying first container, run full zone access test matrix; confirm RED cannot reach container ports; check iptables FORWARD chain |
| Core Updates overwrite custom config files | Phase 5: Reproducibility | Run Core Update on a test snapshot; validate via post-update script that all custom configs are intact; confirm backup includes list covers all modified files |
| Log storage exhaustion from Suricata EVE JSON | Phase 3: IDS/IPS Setup | Observe disk usage growth over 24 hours; confirm logrotate is running and rotating correctly; set disk usage alert |
| Zone misconfiguration causes traffic leakage | Phase 2: Firewall Hardening | Run traffic matrix test: attempt connections between all zone pairs; verify only explicitly allowed traffic passes; check firewall log for unexpected allows |
| Reproducibility failure on hardware rebuild | Phase 5: Reproducibility | Execute a test rebuild from the repo on a fresh IPFire install; verify all zones, rules, services, and Suricata configuration are restored to expected state |
| i226-V link flapping or 2.5G negotiation failure | Phase 1: Platform Verification | Confirm stable link state with `ethtool ethX` and `ip link show` over 10 minutes; check for kernel log errors with `dmesg | grep igc` |
| Backup restore version incompatibility | Phase 5: Reproducibility | Document the Core Update version that the backup was taken from; test restore on same version before treating as authoritative |

---

## Sources

- IPFire Community: i226-V rev 04 rate adaptation — https://community.ipfire.org/t/i226-v-rev-04-rate-adaptation/15363
- IPFire Community: Suricata problems (Core 199→200) — https://community.ipfire.org/t/suricata-problems/15532
- IPFire Community: Core Update 194 overwrote suricata.yaml — https://community.ipfire.org/t/ipfire-2-29-core-update-194-overwrote-suricata-yaml/14133
- IPFire Community: Zone config after MAC address change — https://community.ipfire.org/t/zone-config-after-mac-address-change/9472
- IPFire Community: Admin account not reachable — https://community.ipfire.org/t/admin-account-on-ipfire-box-not-reachable/6385
- IPFire Community: CWWK N100/N150 is a good option? — https://community.ipfire.org/t/cwwk-n100-n150-is-a-good-option/13811
- IPFire Community: Suricata not displayed in process memory graphs — https://community.ipfire.org/t/suricata-is-not-displayed-in-process-and-process-memory-graphs/9524
- IPFire Community: Core 201 DNS Firewall rule requirement — https://community.ipfire.org/t/core-201-test-dns-firewall-adding-an-iptables-rule-for-primary-dbl-ipfire-org/15596
- IPFire Community: Backup restore version compatibility — https://community.ipfire.org/t/config-backup-restore-version-compatibility/2748
- IPFire Docs: firewall.local — https://www.ipfire.org/docs/configuration/firewall/firewall-local
- IPFire Docs: IPS/Suricata — https://www.ipfire.org/docs/configuration/firewall/ips
- IPFire Docs: SSH Access — https://www.ipfire.org/docs/configuration/system/ssh
- IPFire Docs: Backup — https://www.ipfire.org/docs/configuration/system/backup
- IPFire Docs: Zone Configuration — https://www.ipfire.org/docs/configuration/network/zoneconf
- IPFire Docs: Additional Security Configuration — https://www.ipfire.org/docs/optimization/start/security_hardening/additional_security_configuration
- IPFire Fireinfo: igc driver — https://www.ipfire.org/fireinfo/drivers/igc
- Docker Docs: Packet filtering and firewalls — https://docs.docker.com/engine/network/packet-filtering-firewalls/
- Docker Docs: Docker with nftables — https://docs.docker.com/engine/network/firewall-nftables/
- cr0x.net: Docker vs iptables/nftables conflict — https://cr0x.net/en/docker-iptables-nftables-conflict/
- Suricata Docs: Performance analysis — https://docs.suricata.io/en/latest/performance/analysis.html
- Suricata Forum: CPU 100% on one core — https://forum.suricata.io/t/how-to-resolve-one-cpu-usage-100-when-running-suricata/1691
- Suricata Forum: EVE JSON files too large — https://forum.suricata.io/t/suricata-4-0-6-data-suricata-eve-json-files-too-large/4576
- Vulert: Suricata CVE-2024-23836 (memory/CPU exhaustion) — https://vulert.com/vuln-db/debian-11-suricata-169072
- OPNsense GitHub: Suricata log rotation ignored, RAM disk fills — https://github.com/opnsense/core/issues/9385
- pfSense bugtracker: i226 ignores manually selected link speed — https://redmine.pfsense.org/issues/13529
- OpenWrt GitHub: i225/i226 interface naming order changes after upgrade — https://github.com/openwrt/openwrt/issues/17955
- Proxmox Forum: 6-port i226-V ports disappear after upgrade — https://forum.proxmox.com/threads/i-have-a-6-port-intel-i226-v-machine-after-upgrading-from-proxmox-ve-8-4-to-9-1-two-network-ports-disappeared-from-the-system-enp5s0-and-enp7s0.180273/
- CubicleNate: Hardware failure on IPFire (June 2024) — https://cubiclenate.com/2024/06/05/hardware-failure-on-ipfire-blathering/
- Red Hat Docs: Consistent network interface device naming — https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/configuring_and_managing_networking/consistent-network-interface-device-naming_configuring-and-managing-networking
- firewalld.org: Strictly filtering Docker containers — https://firewalld.org/2024/04/strictly-filtering-docker-containers

---
*Pitfalls research for: IPFire firewall appliance on Intel N100 (6x i226-V NICs)*
*Researched: 2026-03-21*
