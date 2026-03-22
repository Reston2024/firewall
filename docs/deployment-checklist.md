# Phase 1 Deployment Checklist

Steps performed by the human on IPFire hardware. Complete in order.

## Pre-Deployment (Before First Reboot)

### PLAT-04: Hostname, Timezone, and Base Updates

- [ ] **Set hostname** via IPFire WUI: System > Hostname
      Recommended: `firewall` or your preferred hostname
      Verify: `hostname` on console returns expected value

- [ ] **Set timezone** via IPFire WUI: System > Time Settings
      Select your local timezone
      Verify: `date` shows correct local time

- [ ] **Run system updates** via IPFire WUI: Pakfire > Update
      Install all pending Core Updates
      Current target: Core Update 200 (IPFire 2.29)
      Verify: WUI shows "No updates available" after completion

- [ ] **Verify kernel version** on console:
      `uname -r` should return `6.18.7` (CU200 kernel)

## NIC Identification (Before Writing udev Rules)

- [ ] Run the NIC identification commands from docs/nic-map.md
- [ ] Fill in ALL cells marked FILL_IN in the NIC assignment table
- [ ] Update `configs/udev/30-persistent-network.rules` with real MACs
- [ ] Update `configs/ethernet/settings` with real MACs and IPs
- [ ] Update `scripts/validate-nics.sh` with real expected MACs
- [ ] Commit all changes to git

## Plan 02 Deployment: udev Rules + firewall.local

- [ ] Copy udev rules to IPFire:
      `scp configs/udev/30-persistent-network.rules root@192.168.1.1:/etc/udev/rules.d/`

- [ ] Copy firewall.local to IPFire:
      `scp configs/firewall/firewall.local root@192.168.1.1:/etc/sysconfig/`

- [ ] Copy ethernet/settings to IPFire (if modified from defaults):
      `scp configs/ethernet/settings root@192.168.1.1:/var/ipfire/ethernet/settings`

- [ ] Reload udev on IPFire (SSH to IPFire, port 222):
      `udevadm control --reload-rules && udevadm trigger`

- [ ] Apply firewall.local:
      `/etc/init.d/firewall restart`

- [ ] Verify firewall.local rules active (on IPFire):
      `iptables -L CUSTOMINPUT -n -v | grep -E '(222|444)'`
      Must show ACCEPT rules for both ports.

- [ ] Copy backup include list:
      `scp configs/firewall/backup-include.user root@192.168.1.1:/var/ipfire/backup/include.user`

- [ ] Populate backup include on IPFire:
      `backupctrl list | grep -E '(udev|firewall.local)'`
      Must show both paths.

## Reboot Persistence Test

- [ ] **Reboot IPFire:** `reboot` (from SSH on port 222)
- [ ] Wait 60 seconds, then reconnect on SSH port 222
- [ ] Run NIC validation on IPFire:
      `bash /root/firewall-repo/scripts/validate-nics.sh`
      Expected: ALL NICS PASS

## Plan 03 Deployment: Zone Policies

See docs/zone-policy-runbook.md for WUI steps.

- [ ] Enable ORANGE masquerade (WUI: Firewall > Masquerade)
- [ ] Enable BLUE masquerade (WUI: Firewall > Masquerade)
- [ ] Block GREEN-to-ORANGE forwarding (WUI: Firewall > Firewall Rules)
- [ ] Enable firewall drop logging (WUI: Firewall > Firewall Options)
- [ ] Run full Phase 1 validation:
      `bash /root/firewall-repo/scripts/validate-phase1.sh`

## Sign-Off Criteria

All of the following must be true before declaring Phase 1 complete:

- [ ] `bash scripts/validate-nics.sh` returns ALL NICS PASS
- [ ] `bash scripts/validate-phase1.sh` returns ALL CHECKS PASS
- [ ] SSH (port 222) accessible from management host after firewall restart
- [ ] WUI (port 444) accessible from management host after firewall restart
- [ ] GREEN host can reach internet (NAT active)
- [ ] GREEN host CANNOT ping ORANGE zone (zone isolation enforced)
- [ ] Dropped packets appear in /var/log/messages with FORWARDFW prefix
- [ ] All changes survive a clean reboot
