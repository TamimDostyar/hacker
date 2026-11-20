# Credential Stuffing

**Platform:** CyLab Security Academy
**Category:** Web / Password Security
**Difficulty:** Easy
**Flag:** `academy{d0nt_r3u5e_cr3d3nt1als_bf0ae95e}`

---

## Description

An online banking service is exposed at `chatelaine.cylabacademy.net`. A dump of
leaked credentials (`creds-dump.txt`) is provided alongside the challenge. The
service does not rate-limit or lock accounts, so a leaked username/password pair
from another breach can be replayed against it — classic **credential stuffing**.

The goal: find the leaked credential pair that still works, log in, and retrieve
the flag.

## Recon

Connecting to the service reveals a plain-text login prompt:
