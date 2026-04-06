#!/bin/bash
set -e
SRC="root@192.168.1.1:/var/log/suricata/eve.json"
DEST="/var/log/ipfire-eve/eve.json"
TMP="${DEST}.tmp"
SSH_KEY="/home/opsadmin/.ssh/ipfire_ed25519"
scp -q -i "${SSH_KEY}" -o StrictHostKeyChecking=yes -o BatchMode=yes "${SRC}" "${TMP}" && mv "${TMP}" "${DEST}"
