#!/bin/bash
# supporttak-rules.sh — Idempotent host firewall rules for supportTAK-server
#
# Run: sudo bash configs/ufw/supporttak-rules.sh
# Added: v2.0.1 remediation (2026-04-11)
#
# Two-layer posture because Docker-published ports bypass UFW's filter
# chain: UFW covers host-bound processes (SSH, ChromaDB :8200) via the
# standard INPUT chain, and iptables DOCKER-USER rules cover Malcolm's
# Docker-published ports (:9200 OpenSearch, :5514 Filebeat, :443 dash).
#
# Scope (what's allowed to reach what):
#   SSH :22 from 192.168.1.100 (laptop) + 192.168.1.102 (desktop SOC)
#   ChromaDB :8200 from 192.168.1.100 + 192.168.1.102
#   Malcolm Dashboard :443 from 192.168.1.100 + 192.168.1.102
#   Malcolm OpenSearch :9200 from 192.168.1.100 + 192.168.1.102
#   Malcolm Filebeat :5514 UDP from 127.0.0.1 only (localhost relay)
#   syslog :514 UDP from 192.168.1.1 (IPFire) only
#   Everything else incoming: DENY
#
# Notes:
#   - wlp1s0 (WiFi, 192.168.5.x) is deliberately excluded from all allow
#     rules. Management must come via the wired GREEN interface.
#   - enx6c6e072d459d is the SPAN capture NIC; no IP filtering is applied
#     because all ingress on that interface is promiscuous SPAN traffic
#     destined for Zeek/Suricata raw-socket capture, not TCP/UDP.
#   - The script is idempotent: running it twice produces the same state.
#   - UFW logging is set to 'low' (logs blocked connections); adjust to
#     'medium' for more detail if debugging.

set -uo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: must run as root (try: sudo bash $0)"
  exit 1
fi

# ---- Trust list ----
LAPTOP="192.168.1.100"
DESKTOP_SOC="192.168.1.102"
IPFIRE="192.168.1.1"

# ---- UFW layer (host-bound services) ----
echo "[ufw] setting defaults"
ufw --force reset >/dev/null
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw logging low >/dev/null

echo "[ufw] SSH from management hosts"
ufw allow from "${LAPTOP}" to any port 22 proto tcp comment 'ssh laptop' >/dev/null
ufw allow from "${DESKTOP_SOC}" to any port 22 proto tcp comment 'ssh desktop-soc' >/dev/null

echo "[ufw] ChromaDB :8200 (host python3 process)"
ufw allow from "${LAPTOP}" to any port 8200 proto tcp comment 'chromadb laptop' >/dev/null
ufw allow from "${DESKTOP_SOC}" to any port 8200 proto tcp comment 'chromadb desktop-soc' >/dev/null

echo "[ufw] enabling"
# --force skips the interactive 'are you sure' prompt — required for
# non-interactive scripted runs. SSH from LAPTOP is already allowed
# above, so the current SSH session (opsadmin from 192.168.1.100) will
# remain connected across the enable.
ufw --force enable >/dev/null
ufw status numbered

# ---- iptables DOCKER-USER layer (Docker-published ports) ----
# DOCKER-USER is evaluated BEFORE the DOCKER ACCEPT chain. By default
# it's empty. We insert RETURN rules for allowed sources, then a final
# DROP for the protected port. Rules are inserted in reverse order so
# the logical read-top-down order is: allow-laptop, allow-desktop, drop.
#
# Idempotency: flush rules with a well-known comment tag before adding.

TAG="v2.0.1-remediation"

# Per-rule delete-before-add pattern for idempotency. iptables-save /
# iptables-restore is too broad here — it would clobber Docker's own
# DOCKER, DOCKER-FORWARD, DOCKER-ISOLATION-* chains.

protect_docker_port() {
  local PROTO="$1"
  local PORT="$2"
  local DESC="$3"

  # Remove any existing DOCKER-USER rules for this port (idempotency).
  while iptables -C DOCKER-USER -p "${PROTO}" --dport "${PORT}" -j DROP -m comment --comment "${TAG} ${DESC} drop" 2>/dev/null; do
    iptables -D DOCKER-USER -p "${PROTO}" --dport "${PORT}" -j DROP -m comment --comment "${TAG} ${DESC} drop"
  done
  while iptables -C DOCKER-USER -s "${LAPTOP}" -p "${PROTO}" --dport "${PORT}" -j RETURN -m comment --comment "${TAG} ${DESC} laptop" 2>/dev/null; do
    iptables -D DOCKER-USER -s "${LAPTOP}" -p "${PROTO}" --dport "${PORT}" -j RETURN -m comment --comment "${TAG} ${DESC} laptop"
  done
  while iptables -C DOCKER-USER -s "${DESKTOP_SOC}" -p "${PROTO}" --dport "${PORT}" -j RETURN -m comment --comment "${TAG} ${DESC} desktop-soc" 2>/dev/null; do
    iptables -D DOCKER-USER -s "${DESKTOP_SOC}" -p "${PROTO}" --dport "${PORT}" -j RETURN -m comment --comment "${TAG} ${DESC} desktop-soc"
  done
  while iptables -C DOCKER-USER -s 127.0.0.1 -p "${PROTO}" --dport "${PORT}" -j RETURN -m comment --comment "${TAG} ${DESC} localhost" 2>/dev/null; do
    iptables -D DOCKER-USER -s 127.0.0.1 -p "${PROTO}" --dport "${PORT}" -j RETURN -m comment --comment "${TAG} ${DESC} localhost"
  done

  # Insert in reverse so top-to-bottom reads: laptop allow, desktop allow,
  # localhost allow, else drop.
  iptables -I DOCKER-USER 1 -p "${PROTO}" --dport "${PORT}" -j DROP -m comment --comment "${TAG} ${DESC} drop"
  iptables -I DOCKER-USER 1 -s 127.0.0.1 -p "${PROTO}" --dport "${PORT}" -j RETURN -m comment --comment "${TAG} ${DESC} localhost"
  iptables -I DOCKER-USER 1 -s "${DESKTOP_SOC}" -p "${PROTO}" --dport "${PORT}" -j RETURN -m comment --comment "${TAG} ${DESC} desktop-soc"
  iptables -I DOCKER-USER 1 -s "${LAPTOP}" -p "${PROTO}" --dport "${PORT}" -j RETURN -m comment --comment "${TAG} ${DESC} laptop"
}

echo "[iptables] DOCKER-USER rules for Malcolm published ports"
protect_docker_port tcp 9200 'opensearch'
protect_docker_port tcp 443  'malcolm-dash'
protect_docker_port tcp 5044 'logstash-beats'
# Filebeat :5514 is UDP and only needs localhost (rsyslog relay is 127.0.0.1).
# Only allow 127.0.0.1 source, drop everything else.
while iptables -C DOCKER-USER -p udp --dport 5514 -j DROP -m comment --comment "${TAG} filebeat-syslog drop" 2>/dev/null; do
  iptables -D DOCKER-USER -p udp --dport 5514 -j DROP -m comment --comment "${TAG} filebeat-syslog drop"
done
while iptables -C DOCKER-USER -s 127.0.0.1 -p udp --dport 5514 -j RETURN -m comment --comment "${TAG} filebeat-syslog localhost" 2>/dev/null; do
  iptables -D DOCKER-USER -s 127.0.0.1 -p udp --dport 5514 -j RETURN -m comment --comment "${TAG} filebeat-syslog localhost"
done
iptables -I DOCKER-USER 1 -p udp --dport 5514 -j DROP -m comment --comment "${TAG} filebeat-syslog drop"
iptables -I DOCKER-USER 1 -s 127.0.0.1 -p udp --dport 5514 -j RETURN -m comment --comment "${TAG} filebeat-syslog localhost"

# Host-bound syslog :514 UDP (rsyslog) — not Docker-published.
# Use UFW for this.
echo "[ufw] syslog :514 UDP from IPFire only"
ufw allow from "${IPFIRE}" to any port 514 proto udp comment 'syslog from ipfire' >/dev/null

echo
echo "[summary] DOCKER-USER rules:"
iptables -L DOCKER-USER -n --line-numbers

echo
echo "[summary] UFW status:"
ufw status numbered

echo
echo "Done. Expected: UFW active, DOCKER-USER has 14 rules (4 ports x 3 allows + 1 drop + 1 udp-syslog pair)."
