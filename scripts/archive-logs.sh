#!/bin/bash
# archive-logs.sh — Archive raw logs to external drive with SHA256 checksums
# Chain of custody: raw untouched copies + checksum manifest
# Cron: 0 * * * * /opt/malcolm/scripts/archive-logs.sh
# Requires: external drive mounted at /media/opsadmin/Seagate Portable Drive

set -e

DRIVE="/media/opsadmin/Seagate Portable Drive"
ARCHIVE="${DRIVE}/firewall-archive"
DATE=$(date +%Y-%m-%d)
HOUR=$(date +%H)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG="/var/log/archive-logs.log"

# Verify drive is mounted
if ! mountpoint -q "${DRIVE}" 2>/dev/null; then
    echo "${TIMESTAMP} ERROR: External drive not mounted at ${DRIVE}" >> "${LOG}"
    exit 1
fi

# Archive EVE JSON (raw copy from IPFire via SCP, pre-Malcolm processing)
EVE_SRC="/opt/malcolm/suricata-logs/suricata-ipfire/eve.json"
EVE_DST="${ARCHIVE}/raw-logs/eve-json/eve-${DATE}-${HOUR}.json"
if [ -f "${EVE_SRC}" ]; then
    cp "${EVE_SRC}" "${EVE_DST}"
    sha256sum "${EVE_DST}" >> "${ARCHIVE}/checksums/eve-json-${DATE}.sha256"
    echo "${TIMESTAMP} Archived EVE JSON: $(stat -c%s "${EVE_DST}") bytes" >> "${LOG}"
fi

# Archive syslog (rsyslog writes from IPFire)
SYSLOG_SRC="/var/log/syslog"
SYSLOG_DST="${ARCHIVE}/raw-logs/syslog/syslog-${DATE}-${HOUR}.log"
if [ -f "${SYSLOG_SRC}" ]; then
    cp "${SYSLOG_SRC}" "${SYSLOG_DST}"
    sha256sum "${SYSLOG_DST}" >> "${ARCHIVE}/checksums/syslog-${DATE}.sha256"
    echo "${TIMESTAMP} Archived syslog: $(stat -c%s "${SYSLOG_DST}") bytes" >> "${LOG}"
fi

# Archive Zeek logs (rotated logs from live capture)
ZEEK_SRC="/opt/malcolm/zeek-logs/live/logs/current"
ZEEK_DST="${ARCHIVE}/raw-logs/zeek/${DATE}-${HOUR}"
if [ -d "${ZEEK_SRC}" ]; then
    mkdir -p "${ZEEK_DST}"
    cp -r "${ZEEK_SRC}"/*.log "${ZEEK_DST}/" 2>/dev/null
    if [ "$(ls -A "${ZEEK_DST}" 2>/dev/null)" ]; then
        find "${ZEEK_DST}" -type f -exec sha256sum {} \; >> "${ARCHIVE}/checksums/zeek-${DATE}.sha256"
        echo "${TIMESTAMP} Archived Zeek logs: $(ls "${ZEEK_DST}" | wc -l) files" >> "${LOG}"
    else
        rmdir "${ZEEK_DST}" 2>/dev/null
    fi
fi

echo "${TIMESTAMP} Archive cycle complete" >> "${LOG}"
