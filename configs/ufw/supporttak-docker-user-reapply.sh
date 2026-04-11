#!/bin/bash
# supporttak-docker-user-reapply.sh — Reapply DOCKER-USER rules idempotently.
#
# Why this exists: DOCKER-USER chain rules are NOT persisted across Docker
# daemon restart or Malcolm `docker compose down && up`. UFW rules ARE
# persisted (stored in /etc/ufw). This script reapplies only the
# DOCKER-USER portion so the host firewall posture survives Malcolm
# lifecycle events.
#
# Install via /etc/cron.d/malcolm-docker-user with:
#   @reboot       root  /opt/malcolm/scripts/supporttak-docker-user-reapply.sh
#   */5 * * * *   root  /opt/malcolm/scripts/supporttak-docker-user-reapply.sh
#
# Idempotent: rules keyed by a v2.0.1-remediation comment tag so repeated
# runs don't accumulate duplicates.
#
# Safe under concurrent Malcolm restart: iptables ops are atomic; at
# worst a narrow window exists between a Docker restart clearing rules
# and the next cron cycle reapplying (max 5 min).

set -uo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: must run as root" >&2
  exit 1
fi

LAPTOP="192.168.1.100"
DESKTOP_SOC="192.168.1.102"
TAG="v2.0.1-remediation"

# Delete any existing rules with our tag before re-adding.
del_rule() {
  while iptables -C DOCKER-USER "$@" 2>/dev/null; do
    iptables -D DOCKER-USER "$@"
  done
}

protect_tcp_port() {
  local PORT="$1"
  local DESC="$2"
  del_rule -p tcp --dport "${PORT}" -j DROP -m comment --comment "${TAG} ${DESC} drop"
  del_rule -s "${LAPTOP}" -p tcp --dport "${PORT}" -j RETURN -m comment --comment "${TAG} ${DESC} laptop"
  del_rule -s "${DESKTOP_SOC}" -p tcp --dport "${PORT}" -j RETURN -m comment --comment "${TAG} ${DESC} desktop-soc"
  del_rule -s 127.0.0.1 -p tcp --dport "${PORT}" -j RETURN -m comment --comment "${TAG} ${DESC} localhost"
  iptables -I DOCKER-USER 1 -p tcp --dport "${PORT}" -j DROP -m comment --comment "${TAG} ${DESC} drop"
  iptables -I DOCKER-USER 1 -s 127.0.0.1 -p tcp --dport "${PORT}" -j RETURN -m comment --comment "${TAG} ${DESC} localhost"
  iptables -I DOCKER-USER 1 -s "${DESKTOP_SOC}" -p tcp --dport "${PORT}" -j RETURN -m comment --comment "${TAG} ${DESC} desktop-soc"
  iptables -I DOCKER-USER 1 -s "${LAPTOP}" -p tcp --dport "${PORT}" -j RETURN -m comment --comment "${TAG} ${DESC} laptop"
}

protect_tcp_port 9200 'opensearch'
protect_tcp_port 443  'malcolm-dash'
protect_tcp_port 5044 'logstash-beats'

# Filebeat :5514 UDP — localhost only.
del_rule -p udp --dport 5514 -j DROP -m comment --comment "${TAG} filebeat-syslog drop"
del_rule -s 127.0.0.1 -p udp --dport 5514 -j RETURN -m comment --comment "${TAG} filebeat-syslog localhost"
iptables -I DOCKER-USER 1 -p udp --dport 5514 -j DROP -m comment --comment "${TAG} filebeat-syslog drop"
iptables -I DOCKER-USER 1 -s 127.0.0.1 -p udp --dport 5514 -j RETURN -m comment --comment "${TAG} filebeat-syslog localhost"

exit 0
