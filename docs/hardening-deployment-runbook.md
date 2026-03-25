# System Hardening Deployment Runbook — Phase 6

**Date:** 2026-03-25
**IPFire Version:** 2.29 Core Update 200 (March 2, 2026)
**Management host:** 192.168.1.100
**IPFire WUI:** https://192.168.1.1:444
**IPFire SSH:** ssh -i ~/.ssh/ipfire_ed25519 root@192.168.1.1
**Repo root (dev machine):** C:\Users\ablan\Firewall

Complete sections in ORDER — the sequence below is mandatory for safe deployment.

---

## CRITICAL WARNINGS — Read Before Starting

- **ORDER IS MANDATORY:** Apply sysctl first, then file permissions, then integrity baseline LAST. The integrity baseline hashes files AFTER all changes. Creating it before hardening will produce a stale baseline that immediately fails on next verify.
- **DO NOT overwrite /etc/sysctl.conf** — append the hardening params. IPFire uses sysctl.conf for its own routing settings (net.ipv4.ip_forward=1). Overwriting it will break routing and require emergency recovery.
- **Verify net.ipv4.ip_forward=1 AFTER sysctl -p** — if this becomes 0, WAN routing stops immediately. The sysctl-hardening.conf is written to preserve this, but confirm before proceeding.
- **Backup include list deploys as-is** — the file at configs/firewall/backup-include.user will overwrite /var/ipfire/backup/include.user. Review its contents in the repo before copying.
- **Do NOT reboot after this runbook** — Plan 04 handles the reboot persistence test. This runbook ends with a pre-reboot snapshot, not a reboot.

---

## Section 0: Prerequisites

Before starting Phase 6 hardening deployment, verify the following are complete:

- Phase 6 Plan 01 complete: all hardening scripts and configs committed in repo
- Phase 6 Plan 02 complete: validate-phase6.sh and validate-all.sh scripts committed
- SSH access to IPFire as root working: `ssh -i ~/.ssh/ipfire_ed25519 root@192.168.1.1`
- SSH access from IPFire to supportTAK-server working (for validate-all.sh Phase 5 checks)
- Dev machine repo is current: `git pull` or verify latest commit includes Phase 6 Plan 01 and Plan 02 files

**Check list:**
- [ ] SSH to IPFire confirmed working
- [ ] WUI accessible at https://192.168.1.1:444
- [ ] Repo is current on dev machine
- [ ] Phase 6 Plan 01 and Plan 02 files present: `ls scripts/validate-phase6.sh configs/hardening/sysctl-hardening.conf`

---

## Section 1: Deploy Scripts and Configs to IPFire

Deploy the entire repo structure to IPFire's local copy at `/root/firewall-repo/`. This syncs all Phase 6 scripts, hardening configs, manifests, and docs.

```bash
# From dev machine
scp -r scripts/ root@192.168.1.1:/root/firewall-repo/scripts/
scp -r configs/ root@192.168.1.1:/root/firewall-repo/configs/
scp -r manifests/ root@192.168.1.1:/root/firewall-repo/manifests/
scp -r docs/ root@192.168.1.1:/root/firewall-repo/docs/
```

**Verify deployment:**
```bash
ssh root@192.168.1.1 'ls /root/firewall-repo/scripts/validate-phase6.sh && ls /root/firewall-repo/configs/hardening/sysctl-hardening.conf && echo "Deploy: OK"'
```

Expected: Both files listed with `Deploy: OK`.

**Fix CRLF line endings on all scripts (required — files SCP'd from Windows):**
```bash
ssh root@192.168.1.1 'find /root/firewall-repo/scripts -name "*.sh" -exec sed -i "s/\r$//" {} \; && echo "CRLF fix: OK"'
```

**Set executable permissions on scripts:**
```bash
ssh root@192.168.1.1 'chmod +x /root/firewall-repo/scripts/*.sh && echo "chmod: OK"'
```

- [ ] All scripts and configs deployed to /root/firewall-repo/
- [ ] CRLF line endings fixed on all .sh files
- [ ] Scripts are executable

---

## Section 2: Apply Sysctl Hardening (HARD-04)

**ORDER CONSTRAINT: This must be done BEFORE file permissions and BEFORE integrity baseline.**

```bash
# On IPFire — read existing sysctl.conf before modifying
ssh root@192.168.1.1 'cat /etc/sysctl.conf'
```

Review the output. Note any custom values already present. The hardening config appends to (not replaces) this file.

```bash
# Append hardening params (DO NOT overwrite)
ssh root@192.168.1.1 'cat /root/firewall-repo/configs/hardening/sysctl-hardening.conf >> /etc/sysctl.conf'

# Apply immediately (no reboot required)
ssh root@192.168.1.1 'sysctl -p /etc/sysctl.conf'
```

**CRITICAL: Verify net.ipv4.ip_forward is still 1 (routing must work):**
```bash
ssh root@192.168.1.1 'sysctl net.ipv4.ip_forward'
```

Expected: `net.ipv4.ip_forward = 1`

If this returns 0: routing is broken. Run `sysctl -w net.ipv4.ip_forward=1` immediately, then inspect sysctl-hardening.conf for a conflicting entry.

**Verify hardening params applied:**
```bash
ssh root@192.168.1.1 'sysctl net.ipv4.conf.all.send_redirects'
```

Expected: `net.ipv4.conf.all.send_redirects = 0`

```bash
ssh root@192.168.1.1 'sysctl net.ipv4.conf.all.accept_redirects'
```

Expected: `net.ipv4.conf.all.accept_redirects = 0`

- [ ] sysctl-hardening.conf appended to /etc/sysctl.conf
- [ ] sysctl -p applied without errors
- [ ] net.ipv4.ip_forward = 1 (CONFIRMED)
- [ ] net.ipv4.conf.all.send_redirects = 0

---

## Section 3: File Permission Lockdown (HARD-02)

**ORDER CONSTRAINT: After sysctl, before integrity baseline.**

```bash
# On IPFire — lock down sensitive config files and directories
ssh root@192.168.1.1 'chmod 600 /etc/ssh/sshd_config && echo "sshd_config: OK"'
ssh root@192.168.1.1 'chmod 700 /etc/sysconfig/firewall.local && echo "firewall.local: OK"'
ssh root@192.168.1.1 'chmod 700 /root/.ssh/ && echo ".ssh dir: OK"'
ssh root@192.168.1.1 'chmod 600 /root/.ssh/authorized_keys 2>/dev/null && echo "authorized_keys: OK" || echo "authorized_keys: not found (skip)"'
```

**Verify permissions:**
```bash
ssh root@192.168.1.1 'stat -c "%a %n" /etc/ssh/sshd_config /etc/sysconfig/firewall.local /root/.ssh/'
```

Expected output:
```
600 /etc/ssh/sshd_config
700 /etc/sysconfig/firewall.local
700 /root/.ssh/
```

- [ ] /etc/ssh/sshd_config is 600
- [ ] /etc/sysconfig/firewall.local is 700
- [ ] /root/.ssh/ is 700
- [ ] /root/.ssh/authorized_keys is 600 (if it exists)

---

## Section 4: Service Audit and Pakfire Manifest (HARD-01)

**Enumerate all listening services — any unexpected listener is a finding.**

```bash
# On IPFire — enumerate listening services
ssh root@192.168.1.1 'ss -tlnp'
```

Expected ports:
- `:53` — unbound (DNS)
- `:22` — sshd (SSH)
- `:81` — httpd (WUI HTTP redirect)
- `:444` — httpd (WUI HTTPS)
- `:1013` — httpd (WUI proxy port, if enabled)

**If unexpected services appear:** Document the finding in `docs/decisions/` and either:
- Disable: `mv /etc/rc.d/rc3.d/S{XX}servicename /root/disabled-services/`
- Justify: add a decision log entry explaining why the service is needed

**Generate live Pakfire manifest:**
```bash
ssh root@192.168.1.1 'ls /opt/pakfire/db/installed/ > /root/firewall-repo/manifests/pakfire-manifest.txt && cat /root/firewall-repo/manifests/pakfire-manifest.txt'
```

**Compare against expected manifest:**
```bash
ssh root@192.168.1.1 'diff /root/firewall-repo/manifests/pakfire-manifest-expected.txt /root/firewall-repo/manifests/pakfire-manifest.txt'
```

If diff shows extra packages: investigate before proceeding. Unexpected Pakfire packages are a finding.

**Copy the generated manifest back to dev machine:**
```bash
scp root@192.168.1.1:/root/firewall-repo/manifests/pakfire-manifest.txt manifests/pakfire-manifest.txt
```

Commit the live manifest to the repo after copying.

- [ ] ss -tlnp shows only expected ports (53, 22, 81, 444; 1013 optional)
- [ ] No unexpected Pakfire packages in manifest diff
- [ ] pakfire-manifest.txt copied to dev machine and committed

---

## Section 5: Deploy Backup Include List

```bash
# On IPFire — deploy backup include list
ssh root@192.168.1.1 'cp /root/firewall-repo/configs/firewall/backup-include.user /var/ipfire/backup/include.user && echo "backup include: OK"'
```

**Verify:**
```bash
ssh root@192.168.1.1 'cat /var/ipfire/backup/include.user'
```

Expected: contents matching the repo file at `configs/firewall/backup-include.user`.

- [ ] /var/ipfire/backup/include.user deployed from repo

---

## Section 6: WUI Certificate Documentation (HARD-05)

Extract the WUI certificate details from IPFire and record them in docs/wui-certificate.md.

```bash
# On IPFire — RSA certificate
ssh root@192.168.1.1 'openssl x509 -in /etc/httpd/server.crt -noout -subject -issuer -dates -fingerprint -sha256'
```

```bash
# On IPFire — ECDSA certificate
ssh root@192.168.1.1 'openssl x509 -in /etc/httpd/server-ecdsa.crt -noout -subject -issuer -dates -fingerprint -sha256'
```

**Record the output:** Update `docs/wui-certificate.md` with the actual values from both commands above.

The output will look like:
```
subject=C = DE, ST = Baden-Wuerttemberg, L = Furtwangen, O = IPFire Project, ...
issuer=C = DE, ...
notBefore=Mar  2 12:00:00 2026 GMT
notAfter=Mar  2 12:00:00 2036 GMT
SHA256 Fingerprint=AB:CD:EF:...
```

- [ ] openssl output captured for both RSA and ECDSA certificates
- [ ] docs/wui-certificate.md updated with actual fingerprint values
- [ ] Updated wui-certificate.md committed to repo

---

## Section 7: Create Integrity Baseline (HARD-03)

**ORDER CONSTRAINT: This MUST be done AFTER sysctl and permission changes (Sections 2-3). The baseline hashes files in their final hardened state. If created before hardening, the baseline will immediately fail on the next verify.**

```bash
# On IPFire — create integrity baseline
ssh root@192.168.1.1 'bash /root/firewall-repo/scripts/check-integrity.sh --create-baseline'
```

Expected output: Lines like `[OK] baseline created: /root/integrity-baseline.sha256` or similar.

**Lock down the baseline file:**
```bash
ssh root@192.168.1.1 'chmod 600 /root/integrity-baseline.sha256 && echo "baseline perms: OK"'
```

**Verify the baseline (should show all PASS or OK):**
```bash
ssh root@192.168.1.1 'bash /root/firewall-repo/scripts/check-integrity.sh --verify'
```

Expected: All monitored files pass the hash check. Zero mismatches immediately after baseline creation.

If any mismatches appear immediately after creation: the check-integrity.sh script may have a logic error. Compare the file list in the script against what was actually hashed.

- [ ] /root/integrity-baseline.sha256 created
- [ ] Baseline file is chmod 600
- [ ] check-integrity.sh --verify shows all PASS

---

## Section 8: Run validate-phase6.sh

Run the full Phase 6 validation suite to confirm all hardening checks pass.

```bash
ssh root@192.168.1.1 'bash /root/firewall-repo/scripts/validate-phase6.sh'
```

**Expected results:**

| Check | Expected Result | Notes |
|-------|----------------|-------|
| HARD-01 | PASS | Only expected services listening |
| HARD-02 | PASS | sshd_config 600, firewall.local 700, .ssh/ 700 |
| HARD-03 | PASS | Integrity baseline exists and verifies |
| HARD-04 | PASS | sysctl params applied |
| HARD-05 | PASS | WUI certificate accessible on port 444 |

**If any check FAILS:**

| FAIL | Root Cause | Fix |
|------|-----------|-----|
| HARD-01 FAIL | Unexpected service listening | Identify and disable the service, or document justification |
| HARD-02 FAIL | Wrong file permissions | Re-run Section 3 chmod commands |
| HARD-03 FAIL | Baseline missing or mismatch | Re-run Section 7 (--create-baseline then --verify) |
| HARD-04 FAIL | Sysctl param not set | Check that sysctl-hardening.conf was appended (not missing from /etc/sysctl.conf) and `sysctl -p` was run |
| HARD-05 FAIL | httpd not responding on 444 | Check `/etc/init.d/apache status`; restart if needed |

- [ ] validate-phase6.sh exits 0 (all checks PASS or expected SKIP)

---

## Section 9: Capture Pre-Reboot Snapshot (VAL-08 prep)

**This is the last step. Do NOT reboot after this — Plan 04 handles the reboot persistence test.**

```bash
# On IPFire — capture pre-reboot state snapshot
ssh root@192.168.1.1 'bash /root/firewall-repo/scripts/validate-reboot.sh --snapshot'
```

Expected: Output confirming `/root/reboot-snapshot.txt` was created.

**Verify snapshot exists:**
```bash
ssh root@192.168.1.1 'ls -la /root/reboot-snapshot.txt && head -5 /root/reboot-snapshot.txt'
```

Expected: File exists with recent timestamp. First lines should show snapshot metadata (date, sysctl hash, iptables hash, etc.).

- [ ] /root/reboot-snapshot.txt created
- [ ] Snapshot file is non-empty and contains expected sections

---

## Sign-Off Checklist

Complete all items before signaling checkpoint passed.

**Section 1: Scripts deployed**
- [ ] All scripts and configs synced to /root/firewall-repo/ on IPFire
- [ ] CRLF line endings fixed
- [ ] Scripts are executable

**Section 2: Sysctl hardening (HARD-04)**
- [ ] sysctl-hardening.conf appended to /etc/sysctl.conf
- [ ] sysctl -p applied without errors
- [ ] net.ipv4.ip_forward = 1 (routing intact)
- [ ] send_redirects = 0

**Section 3: File permissions (HARD-02)**
- [ ] /etc/ssh/sshd_config is 600
- [ ] /etc/sysconfig/firewall.local is 700
- [ ] /root/.ssh/ is 700

**Section 4: Service audit (HARD-01)**
- [ ] No unexpected services found (or findings documented)
- [ ] pakfire-manifest.txt generated and copied to dev machine

**Section 5: Backup include list**
- [ ] /var/ipfire/backup/include.user deployed

**Section 6: WUI certificate (HARD-05)**
- [ ] docs/wui-certificate.md updated with actual SHA256 fingerprints

**Section 7: Integrity baseline (HARD-03)**
- [ ] /root/integrity-baseline.sha256 created after hardening
- [ ] check-integrity.sh --verify passes

**Section 8: Validation**
- [ ] validate-phase6.sh exits 0 — all HARD checks PASS

**Section 9: Pre-reboot snapshot**
- [ ] /root/reboot-snapshot.txt exists
- [ ] NOT yet rebooted (Plan 04 handles reboot test)

---

## After Completing This Runbook

Once all Sign-Off Checklist items are complete and validate-phase6.sh shows zero FAIL:

- **Signal to orchestrator:** Type `hardening deployed` with any findings or issues encountered
- **Next step:** Plan 04 — reboot persistence testing (reboot IPFire, run validate-reboot.sh --check)
- **If sysctl findings:** Document in docs/decisions/ before proceeding to Plan 04
