# IPFire WUI HTTPS Certificate Documentation

## Overview

The IPFire Web UI (WUI) runs on port 444 over HTTPS using a self-signed certificate generated
during installation. Browser warnings are expected — this is by design for IPFire's management
interface. The certificate is NOT trusted by a public CA.

## Certificate File Locations

| File | Purpose | Notes |
|------|---------|-------|
| `/etc/httpd/server.crt` | RSA certificate (primary) | Used by Apache httpd |
| `/etc/httpd/server-ecdsa.crt` | ECDSA certificate (secondary) | Preferred by modern clients |
| `/etc/httpd/server.key` | RSA private key | **Not stored in repo** |
| `/etc/httpd/server-ecdsa.key` | ECDSA private key | **Not stored in repo** |

**Important:** Private keys are never stored in this repository. Only fingerprints and
certificate metadata are recorded here for verification purposes.

## Extraction Commands

Run these commands on the IPFire appliance to obtain certificate details:

### RSA Certificate
```bash
openssl x509 -in /etc/httpd/server.crt -noout -subject -issuer -dates -fingerprint -sha256
```

### ECDSA Certificate
```bash
openssl x509 -in /etc/httpd/server-ecdsa.crt -noout -subject -issuer -dates -fingerprint -sha256
```

### Live TLS Handshake Fingerprint (from loopback)
```bash
openssl s_client -connect 127.0.0.1:444 </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256
```

## Certificate Fingerprints

> **Fill during deployment checkpoint** — run the extraction commands above on the live
> IPFire appliance and record the results here.

### RSA Certificate
```
Subject:    [FILL IN FROM: openssl x509 -in /etc/httpd/server.crt -noout -subject]
Issuer:     [FILL IN FROM: openssl x509 -in /etc/httpd/server.crt -noout -issuer]
Not Before: [FILL IN]
Not After:  [FILL IN]
SHA256 Fingerprint: [FILL IN]
```

### ECDSA Certificate
```
Subject:    [FILL IN FROM: openssl x509 -in /etc/httpd/server-ecdsa.crt -noout -subject]
Issuer:     [FILL IN FROM: openssl x509 -in /etc/httpd/server-ecdsa.crt -noout -issuer]
Not Before: [FILL IN]
Not After:  [FILL IN]
SHA256 Fingerprint: [FILL IN]
```

## Self-Signed Certificate Context

- Self-signed certificates are the standard and expected configuration for IPFire WUI
- Browser will show a security warning on first visit — this is normal and expected
- To trust the certificate in a browser: add a permanent exception for `https://192.168.1.1:444`
- The certificate is generated automatically during IPFire installation
- Certificate validity: typically 10 years from installation date

## Certificate Regeneration

If the certificate needs to be regenerated (e.g., after hardware replacement or IP change):

Reference: IPFire wiki — `/optimization/ssl_cert`
URL: `https://wiki.ipfire.org/optimization/ssl_cert`

General procedure (verify against current wiki before executing):
1. SSH into IPFire
2. Back up existing certs: `cp /etc/httpd/server.crt /root/ && cp /etc/httpd/server-ecdsa.crt /root/`
3. Follow wiki procedure to regenerate
4. Restart httpd: `/etc/init.d/apache restart`
5. Update fingerprint records in this document

## Verification

After recording fingerprints, verify browser access:
1. Visit `https://192.168.1.1:444` in a browser
2. Accept the self-signed certificate warning
3. Log in to confirm WUI is accessible
4. Compare browser-shown fingerprint with recorded SHA256 fingerprint above
