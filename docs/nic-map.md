# NIC Map — Physical Port to Zone Assignment

**Hardware:** N100 6-NIC mini-PC
**NICs:** 6x Intel i226-V (PCI device ID 8086:125c, kernel driver: igc)
**Status:** TEMPLATE — fill in MAC addresses and PCIe bus IDs from live hardware

## Identification Commands (run on IPFire console)

```bash
# Step 1: List all NICs with MAC and link state
ip link show

# Step 2: Map interface names to PCIe slots
for iface in $(ls /sys/class/net/ | grep -v lo); do
  bus=$(ethtool -i $iface 2>/dev/null | awk '/bus-info/ {print $2}')
  mac=$(cat /sys/class/net/$iface/address)
  echo "$iface  PCIe=$bus  MAC=$mac"
done

# Step 3: Enumerate i226-V NICs by PCI device ID
lspci -nn | grep '8086:125c'

# Step 4: Physical port identification (LED blink method)
# Run `setup` utility -> Network Configuration -> select NIC -> Identify
# The selected NIC's LED blinks for physical identification

# Step 5: Cable-plug method (if LED blink unavailable)
# Plug cable into one port at a time, run: ip link show | grep -E "state UP|state DOWN"
# Record which interface goes UP for each physical port
```

## NIC Assignment Table

Fill in this table before writing udev rules. Every cell marked FILL_IN must be completed.

| Physical Port | Zone | Device Name | MAC Address | PCIe Bus | Driver | Notes |
|--------------|------|-------------|-------------|----------|--------|-------|
| Port 1 | RED (WAN) | red0 | FILL_IN | FILL_IN | FILL_IN | Connect to ISP/modem |
| Port 2 | GREEN (LAN) | green0 | FILL_IN | FILL_IN | FILL_IN | Primary trusted LAN |
| Port 3 | BLUE (Wireless) | blue0 | FILL_IN | FILL_IN | FILL_IN | Wireless/guest zone |
| Port 4 | ORANGE (DMZ) | orange0 | FILL_IN | FILL_IN | FILL_IN | DMZ / untrusted servers |
| Port 5 | GREEN Bridge | green1 | FILL_IN | FILL_IN | FILL_IN | Bridged to green0 |
| Port 6 | GREEN Bridge | green2 | FILL_IN | FILL_IN | FILL_IN | Bridged to green0 |

## IP Addressing

| Zone | Interface | IP Address | Subnet | Purpose |
|------|-----------|------------|--------|---------|
| GREEN | green0 | FILL_IN | FILL_IN | Default gateway for LAN clients |
| GREEN Bridge | green1 | FILL_IN | FILL_IN | Bridged with green0 (same subnet) |
| GREEN Bridge | green2 | FILL_IN | FILL_IN | Bridged with green0 (same subnet) |
| BLUE | blue0 | FILL_IN | FILL_IN | Default gateway for wireless clients |
| ORANGE | orange0 | FILL_IN | FILL_IN | Default gateway for DMZ hosts |
| RED | red0 | DHCP from ISP | N/A | WAN / internet uplink |

## After Filling This Table

1. Copy MAC addresses into `configs/udev/30-persistent-network.rules`
2. Copy MAC addresses into `configs/ethernet/settings`
3. Copy MAC addresses into the `*_EXPECTED_MAC` variables in `scripts/validate-nics.sh`
4. Commit updated files to git

## Post-Reboot Verification

After installing udev rules and rebooting IPFire:
```bash
bash /root/firewall-repo/scripts/validate-nics.sh
```
Expected output: 6x "PASS:" lines followed by "ALL NICS PASS"
