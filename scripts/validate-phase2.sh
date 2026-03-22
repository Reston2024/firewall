#!/bin/bash
# validate-phase2.sh — Phase 2 Core Network Services validation
# Usage: bash /root/firewall-repo/scripts/validate-phase2.sh
# Run on IPFire appliance (not dev machine)
# Exits: 0 if all automated checks pass, 1 if any fail

FAIL=0
PASS=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "SKIP: $1 (manual verification required)"; }

echo "=== Phase 2 Validation Suite — $(date) ==="
echo ""

# --- SVC-01: DHCP GREEN zone has correct gateway, DNS, NTP options ---
echo "[SVC-01] DHCP GREEN zone options"
if grep -q "option routers 192.168.1.1" /var/ipfire/dhcp/dhcpd.conf 2>/dev/null; then
  pass "DHCP option routers = 192.168.1.1"
else
  fail "DHCP option routers not set to 192.168.1.1 in dhcpd.conf"
fi

if grep -q "option domain-name-servers 192.168.1.1" /var/ipfire/dhcp/dhcpd.conf 2>/dev/null; then
  pass "DHCP option domain-name-servers = 192.168.1.1"
else
  fail "DHCP option domain-name-servers not set to 192.168.1.1 in dhcpd.conf"
fi

if grep -q "option ntp-servers 192.168.1.1" /var/ipfire/dhcp/dhcpd.conf 2>/dev/null; then
  pass "DHCP option ntp-servers = 192.168.1.1"
else
  fail "DHCP option ntp-servers not set to 192.168.1.1 in dhcpd.conf — set Primary NTP in WUI DHCP page"
fi

if /etc/init.d/dhcp status 2>/dev/null | grep -qi "running\|started"; then
  pass "dhcpd service is running"
else
  fail "dhcpd service is NOT running — run: /etc/init.d/dhcp start"
fi
echo ""

# --- SVC-02: Static lease capability (host blocks in dhcpd.conf) ---
echo "[SVC-02] DHCP static lease capability"
STATIC_COUNT=$(grep -c "hardware ethernet" /var/ipfire/dhcp/dhcpd.conf 2>/dev/null || echo "0")
if [ "$STATIC_COUNT" -gt 0 ]; then
  pass "dhcpd.conf contains $STATIC_COUNT static lease host block(s)"
else
  skip "SVC-02: No static leases configured yet — add entries to fixleases and toggle in WUI"
fi

if [ -f /var/ipfire/dhcp/fixleases ]; then
  pass "fixleases file exists at /var/ipfire/dhcp/fixleases"
else
  skip "SVC-02: fixleases file not deployed — deploy from configs/dhcp/fixleases after editing"
fi
echo ""

# --- SVC-03: DNSSEC validation active (AD flag in response) ---
echo "[SVC-03] DNSSEC validation"
if command -v dig >/dev/null 2>&1; then
  DIG_OUTPUT=$(dig +dnssec sigok.verteiltesysteme.net @127.0.0.1 2>/dev/null)
  if echo "$DIG_OUTPUT" | grep -q "flags:.*ad"; then
    pass "DNSSEC AD flag present — sigok.verteiltesysteme.net validates correctly"
  else
    fail "DNSSEC AD flag NOT present — check Unbound DNSSEC config (should be on by default since CU80)"
  fi

  SERVFAIL_OUTPUT=$(dig sigfail.verteiltesysteme.net @127.0.0.1 2>/dev/null)
  if echo "$SERVFAIL_OUTPUT" | grep -qi "SERVFAIL"; then
    pass "DNSSEC enforcement active — sigfail.verteiltesysteme.net returns SERVFAIL as expected"
  else
    fail "DNSSEC not enforcing — sigfail.verteiltesysteme.net should return SERVFAIL"
  fi
else
  fail "dig command not found — install bind-utils or equivalent"
fi

if /etc/init.d/unbound status 2>/dev/null | grep -qi "running\|started"; then
  pass "unbound service is running"
else
  fail "unbound service is NOT running — run: /etc/init.d/unbound start"
fi
echo ""

# --- SVC-04: DNS-over-TLS to upstream resolvers ---
echo "[SVC-04] DNS-over-TLS upstream configuration"
if grep -q "forward-tls-upstream: yes" /etc/unbound/forward.conf 2>/dev/null; then
  pass "forward-tls-upstream: yes found in /etc/unbound/forward.conf"
else
  fail "forward-tls-upstream NOT enabled — in WUI: Network > DNS Servers > Protocol: TLS"
fi

if grep -q "@853#" /etc/unbound/forward.conf 2>/dev/null; then
  pass "TLS hostname entries (@853#hostname) present in forward.conf"
else
  fail "TLS hostname entries missing from forward.conf — add TLS hostnames in WUI DNS Servers page"
fi

if grep -q "1dot1dot1dot1.cloudflare-dns.com\|dns.quad9.net" /etc/unbound/forward.conf 2>/dev/null; then
  pass "Cloudflare or Quad9 TLS hostname found in forward.conf"
else
  fail "Cloudflare/Quad9 TLS hostnames missing — configure in WUI: Network > DNS Servers"
fi

skip "SVC-04 wire verification: tcpdump -i red0 -n port 53 (should show no upstream plaintext DNS)"
skip "SVC-04 wire verification: tcpdump -i red0 -n port 853 (should show encrypted DoT traffic)"
echo ""

# --- SVC-05: NTP synchronized and serving clients ---
echo "[SVC-05] NTP synchronization and client serving"
NTP_SYNC=$(ntpq -p 2>/dev/null | grep '^\*')
if [ -n "$NTP_SYNC" ]; then
  pass "NTP synchronized — active peer: $(echo "$NTP_SYNC" | awk '{print $1, "stratum", $3}')"
else
  fail "NTP NOT synchronized — check upstream pool reachability: ntpq -p"
fi

if ss -ulnp 2>/dev/null | grep -q ':123'; then
  pass "NTP listening on port 123 (serving clients)"
else
  fail "NTP NOT listening on port 123 — enable 'Provide time to local network' in WUI: Services > Time Server"
fi

if /etc/init.d/ntp status 2>/dev/null | grep -qi "running\|started"; then
  pass "ntpd service is running"
else
  fail "ntpd service is NOT running — run: /etc/init.d/ntp start"
fi
echo ""

# --- SVC-06: All services auto-start at boot ---
echo "[SVC-06] Service auto-start registration (SysVinit)"
for svc_pattern in "S.*dhcp" "S.*unbound" "S.*ntp"; do
  if ls /etc/rc.d/rc3.d/ 2>/dev/null | grep -qE "$svc_pattern"; then
    pass "Boot symlink exists: /etc/rc.d/rc3.d/ matches $svc_pattern"
  else
    fail "Boot symlink MISSING for pattern $svc_pattern in /etc/rc.d/rc3.d/"
  fi
done

skip "SVC-06 reboot persistence: reboot IPFire and re-run this script to confirm all services start"
echo ""

# --- Summary ---
echo "=== Results: ${PASS} pass, ${FAIL} fail ==="
if [ "$FAIL" -eq 0 ]; then
  echo "ALL CHECKS PASS"
  exit 0
else
  echo "PHASE 2 VALIDATION FAILED — resolve failures above"
  exit 1
fi
