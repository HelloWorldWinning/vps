#!/usr/bin/env bash
# Run as root on the VPS. Requires Docker with Compose v2, Python 3 and OpenSSL.
# First run: copy or reuse an issued acme.sh certificate and start six listeners.
# Install prompts for the TLS hostname, REALITY target and SNI use 3-second defaults.
# Later: edit /root/xray_docker_multi/config.json and choose Apply edited config.
set -euo pipefail

exec python3 -c "$(cat <<'PYTHON'
import base64
import fcntl
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import select
import shlex
import shutil
import socket
import statistics
import subprocess
import sys
import tempfile
import termios
import textwrap
import time
from urllib.parse import quote, urlencode


ROOT = Path("/root/xray_docker_multi")
CONFIG = ROOT / "config.json"
ACTIVE = ROOT / ".active-config.json"
COMPOSE = ROOT / "docker-compose.yml"
ENV_FILE = ROOT / ".env"
HOST_FILE = ROOT / "connection-host"
CERT_DIR = ROOT / "certs"
PROJECT = "xray_docker_multi"
IMAGE_REPO = "ghcr.io/xtls/xray-core"
DEFAULT_TAG = "26.10.31"
DEFAULT_UUID = "12345678-1234-1234-1234-123456789012"
RUNTIME_CONFIG = "/usr/local/etc/xray/config.json"
REALITY_DEFAULT = "www.oracle.com"
INSTALL_DEFAULT_TIMEOUT = 3
WEBSOCKET_DEPRECATION = re.compile(
    r"\[Warning\]\s+common/errors: (?:The|This) feature "
    r"WebSocket transport \(with ALPN http/1\.1, etc\.\) is deprecated\b"
)

# tag, port, transport, security, flow. Only used on first install.
INBOUNDS = [
    ("vless-ws",        9043, "ws",    "none",    ""),
    ("vless-ws-tls",    9143, "ws",    "tls",     ""),
    ("vless-xhttp-tls", 9243, "xhttp", "tls",     ""),
    ("vless-xhttp",     9343, "xhttp", "none",    ""),
    ("vless-reality",   9643, "raw",   "reality", "xtls-rprx-vision"),
    ("vless-vision",    9743, "raw",   "tls",     "xtls-rprx-vision"),
]

X25519_PRIVATE_PREFIX = bytes.fromhex("302e020100300506032b656e04220420")
X25519_PUBLIC_PREFIX = bytes.fromhex("302a300506032b656e032100")


class ManagerError(Exception):
    pass


def command(args, *, capture=False, merge_stderr=False, data=None, deadline=None, env=None):
    stderr = subprocess.PIPE if capture else None
    if merge_stderr:
        stderr = subprocess.STDOUT
    return subprocess.run(
        args, check=True, timeout=deadline, env=env,
        stdin=subprocess.DEVNULL if data is None else None, input=data,
        stdout=subprocess.PIPE if capture else None,
        stderr=stderr,
    ).stdout


def ask(label, default=None, *, timeout=None):
    suffix = f" [{default}]" if default is not None else ""
    if timeout is None or default is None:
        value = input(f"{label}{suffix}: ").strip()
    else:
        print(f"{label}{suffix} (default in {timeout}s): ", end="", flush=True)
        if not select.select([sys.stdin], [], [], timeout)[0]:
            termios.tcflush(sys.stdin.fileno(), termios.TCIFLUSH)
            print(f"\n  Using {default}", flush=True)
            return default
        value = input().strip()
    return value if value or default is None else default


def confirm(label):
    return ask(f"{label} (y/N)").lower() == "y"


def write_private(path, data):
    if isinstance(data, str):
        data = data.encode()
    output = tempfile.NamedTemporaryFile(dir=path.parent, delete=False)
    temporary = Path(output.name)
    try:
        with output:
            output.write(data)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def json_bytes(data):
    return json.dumps(data, indent=2) + "\n"


def docker_ready():
    try:
        command(["docker", "compose", "version"], capture=True)
        command(["docker", "info", "--format", "{{.ServerVersion}}"], capture=True, deadline=15)
    except (OSError, subprocess.SubprocessError) as exc:
        raise ManagerError("Docker must be running with the Docker Compose v2 plugin installed.") from exc


def compose(*args, config=None, image=None, capture=False, merge_stderr=False):
    env = os.environ.copy()
    env.pop("XRAY_CONFIG_PATH", None)
    env.pop("XRAY_IMAGE", None)
    if config is not None:
        env["XRAY_CONFIG_PATH"] = str(config)
    if image is not None:
        env["XRAY_IMAGE"] = image
    return command(
        ["docker", "compose", "--project-name", PROJECT,
         "--project-directory", str(ROOT), "--env-file", str(ENV_FILE),
         "-f", str(COMPOSE), *args],
        env=env, capture=capture, merge_stderr=merge_stderr,
    )


def probe_reality(target, sni):
    print(f"Testing TLS 1.3 + h2 with SNI {sni} at {target} (3 attempts) …", flush=True)
    times = []
    for _ in range(3):
        start = time.monotonic()
        try:
            result = command(
                ["openssl", "s_client", "-connect", target, "-servername", sni,
                 "-tls1_3", "-alpn", "h2", "-verify_hostname", sni,
                 "-verify_return_error", "-no_ign_eof"],
                capture=True, deadline=5,
            )
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            continue
        if b"ALPN protocol: h2" in result:
            times.append((time.monotonic() - start) * 1000)
    if times:
        print(f"  {len(times)}/3 passed. Median TLS connection time {statistics.median(times):.0f} ms.")
    else:
        print("  TLS 1.3, h2 and hostname verification did not pass.")
    return bool(times)


def reality_prompt(target_host=REALITY_DEFAULT, *, timeout=None):
    target = ask("REALITY target (hostname:port)", f"{target_host}:443", timeout=timeout)
    host, _, port = target.rpartition(":")
    if not re.fullmatch(r"[a-zA-Z0-9.-]+", host) or not port.isdecimal() or not 1 <= int(port) <= 65535:
        raise ManagerError("Enter a REALITY target such as www.oracle.com:443.")
    sni = ask("REALITY SNI", host, timeout=timeout)
    if not re.fullmatch(r"[a-zA-Z0-9.-]+", sni):
        raise ManagerError("The REALITY SNI must be a hostname.")
    return target, sni


def acme_client():
    home = Path(os.environ.get("XRAY_ACME_HOME", "/root/.acme.sh"))
    binary = home / "acme.sh"
    if not os.access(binary, os.X_OK):
        binary = shutil.which("acme.sh")
    if not binary:
        raise ManagerError("acme.sh is missing. Set XRAY_ACME_HOME if it uses a custom directory.")
    return [str(binary), "--home", str(home)]


def choose_certificate(acme, *, hostname_timeout=None):
    rows = command([*acme, "--list"], capture=True).decode().splitlines()
    options = []
    for line in rows:
        fields = line.split()
        if len(fields) < 2:
            continue
        domain, key_length = fields[:2]
        if not re.fullmatch(r"(?:\*\.)?[A-Za-z0-9.-]+", domain):
            continue
        key_length = key_length.strip('"\'')
        if key_length.startswith("ec-") or key_length.isdecimal():
            options.append((domain, key_length))
    if not options:
        raise ManagerError("acme.sh has no issued certificates to select.")
    print("Issued acme.sh certificates")
    for i, (domain, key_length) in enumerate(options, 1):
        print(f"  {i}) {domain} ({key_length})")
    default = next((i for i, (domain, length) in enumerate(options, 1)
                    if domain == "la.zhulei.eu.org" and length.startswith("ec-")), 1)
    selected = ask("Select certificate", str(default))
    if not selected.isdecimal() or not 1 <= int(selected) <= len(options):
        raise ManagerError("Choose a certificate number from the list.")
    domain, key_length = options[int(selected) - 1]
    flags = ["--ecc"] if key_length.startswith("ec-") else []
    default_host = domain if not domain.startswith("*.") else None
    hostname = ask("TLS hostname for direct clients", default_host, timeout=hostname_timeout)
    if not re.fullmatch(r"[a-zA-Z0-9.-]+", hostname):
        raise ManagerError("Enter a concrete TLS hostname covered by the certificate.")
    return domain, flags, hostname.lower()


def validate_cert(cert, key, hostname):
    if not cert.is_file() or not key.is_file() or not cert.stat().st_size or not key.stat().st_size:
        raise ManagerError("The certificate or key file is missing or empty.")
    try:
        command(["openssl", "x509", "-in", str(cert), "-noout", "-checkend", "0"], capture=True)
        match = command(["openssl", "x509", "-in", str(cert), "-noout", "-checkhost", hostname],
                        capture=True)
        cert_pub = command(["openssl", "x509", "-in", str(cert), "-pubkey", "-noout"], capture=True)
        key_pub = command(["openssl", "pkey", "-in", str(key), "-passin", "pass:", "-pubout"],
                          capture=True)
    except subprocess.CalledProcessError as exc:
        raise ManagerError("Use an unexpired PEM certificate and its unencrypted PEM private key.") from exc
    if b"does match certificate" not in match or cert_pub != key_pub:
        raise ManagerError("The TLS hostname or private key does not match the certificate.")


def certificate_paths(acme, domain, flags, hostname):
    # acme.sh stores one set of install-cert destinations per certificate.
    # Read those destinations before deciding whether this is a first deployment.
    output = command([*acme, "--info", "-d", domain, *flags], capture=True).decode()
    info = dict(line.split("=", 1) for line in output.splitlines() if "=" in line)
    if info.get("Le_Domain") != domain:
        raise ManagerError("Could not confirm the selected certificate with acme.sh --info.")

    cert = info.get("Le_RealFullChainPath", "")
    key = info.get("Le_RealKeyPath", "")
    existing = any(info.get(field) for field in (
        "Le_RealFullChainPath", "Le_RealKeyPath", "Le_RealCertPath",
        "Le_RealCACertPath", "Le_ReloadCmd", "Le_DeployHook",
    ))
    if not existing:
        CERT_DIR.mkdir(mode=0o700, exist_ok=True)
        cert_file = CERT_DIR / "fullchain.cer"
        key_file = CERT_DIR / "private.key"
        for path in (cert_file, key_file):
            if path.is_symlink() or (path.exists() and not path.is_file()):
                raise ManagerError(f"Expected a regular file at {path}.")
            path.touch(mode=0o600, exist_ok=True)
        print(f"Registering the first acme.sh certificate deployment at {CERT_DIR}.", flush=True)
        command([*acme, "--install-cert", "-d", domain, *flags,
                 "--fullchain-file", str(cert_file), "--key-file", str(key_file)])
    else:
        if not cert or not key or not Path(cert).is_file() or not Path(key).is_file():
            print("This certificate already has acme.sh deployment settings.")
            cert = ask("Absolute path to an existing renewed fullchain", cert or None)
            key = ask("Absolute path to its existing renewed key", key or None)
        else:
            print("Reusing the fullchain and key already deployed by acme.sh.")
        cert_file, key_file = Path(cert), Path(key)
        if not cert_file.is_absolute() or not key_file.is_absolute():
            raise ManagerError("Both deployed certificate paths must be absolute.")
        if cert_file.is_symlink() or key_file.is_symlink():
            raise ManagerError("Use the stable PEM files written by acme.sh. The selected files are symlinks.")
    cert_file, key_file = cert_file.resolve(), key_file.resolve()
    validate_cert(cert_file, key_file, hostname)
    return cert_file, key_file


def compose_yaml(cert, key):
    # Bind the directories so Xray sees new file contents even after an atomic file replacement.
    directories = list(dict.fromkeys([cert.parent, key.parent]))
    mounts = {path: f"/run/xray-tls/{i}" for i, path in enumerate(directories)}
    for directory in directories:
        acme_home = Path(os.environ.get("XRAY_ACME_HOME", "/root/.acme.sh")).resolve()
        if directory in [Path("/"), Path("/root"), Path("/etc"), ROOT] or directory.is_relative_to(acme_home):
            raise ManagerError(f"Choose certificate files in a dedicated deployment directory, not {directory}.")
    yaml = """services:
  xray:
    image: "${XRAY_IMAGE}"
    container_name: xray_docker_multi
    network_mode: host
    restart: unless-stopped
    user: "0:0"
    read_only: true
    cap_drop: [ALL]
    security_opt: ["no-new-privileges:true"]
    command: ["run", "-config", "/usr/local/etc/xray/config.json"]
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    volumes:
      - type: bind
        source: "${XRAY_CONFIG_PATH:-./.active-config.json}"
        target: /usr/local/etc/xray/config.json
        read_only: true
        bind:
          create_host_path: false
"""
    for source, target in mounts.items():
        source_path = json.dumps(str(source).replace("$", "$$"))
        yaml += (
            "      - type: bind\n"
            f"        source: {source_path}\n"
            f"        target: {target}\n"
            "        read_only: true\n"
            "        bind:\n"
            "          create_host_path: false\n"
        )
    return yaml, f"{mounts[cert.parent]}/{cert.name}", f"{mounts[key.parent]}/{key.name}"


def make_config(cert, key, target, sni, listen="::"):
    inbounds = []
    for tag, port, transport, security, flow in INBOUNDS:
        client = {"id": DEFAULT_UUID, "email": tag}
        if flow:
            client["flow"] = flow
        stream = {"network": transport, "security": security}
        if transport == "ws":
            stream["wsSettings"] = {"path": "/"}
        if transport == "xhttp":
            stream["xhttpSettings"] = {"path": "/", "mode": "auto"}
        if security == "tls":
            stream["tlsSettings"] = {
                "minVersion": "1.3" if flow else "1.2",
                "alpn": ["http/1.1"] if transport == "ws" else ["h2", "http/1.1"],
                "certificates": [{
                    "certificateFile": cert, "keyFile": key, "oneTimeLoading": False,
                }],
            }
        if security == "reality":
            stream["realitySettings"] = {
                "target": target, "serverNames": [sni],
                "privateKey": base64.urlsafe_b64encode(secrets.token_bytes(32)).decode().rstrip("="),
                "shortIds": [secrets.token_hex(8)],
            }
        inbounds.append({
            "tag": tag, "listen": listen, "port": port, "protocol": "vless",
            "settings": {"clients": [client], "decryption": "none"},
            "streamSettings": stream,
        })
    return {"log": {"loglevel": "warning"}, "inbounds": inbounds,
            "outbounds": [{"tag": "direct", "protocol": "freedom"}]}


def validate_config(path, image=None):
    if not path.is_file():
        raise ManagerError(f"Missing config file {path}.")
    try:
        output = compose("run", "--rm", "--no-deps", "-T", "xray", "run", "-test",
                         "-config", RUNTIME_CONFIG, config=path, image=image,
                         capture=True, merge_stderr=True)
    except subprocess.CalledProcessError as exc:
        if exc.output:
            sys.stderr.write(exc.output.decode(errors="replace"))
        raise

    # WebSocket remains one of the supported presets. Keep the advisory in raw logs.
    for line in output.decode(errors="replace").splitlines(keepends=True):
        if not WEBSOCKET_DEPRECATION.search(line):
            sys.stdout.write(line)


def container_state():
    result = compose("ps", "-a", "--format", "json", "xray", capture=True).decode().strip()
    if not result:
        return None
    record = json.loads(result.splitlines()[0])
    if isinstance(record, list):
        if not record:
            return None
        record = record[0]
    return record["State"]


def recreate():
    try:
        compose("up", "-d", "--force-recreate", "--wait", "--wait-timeout", "15")
        time.sleep(1)
        state = command(["docker", "inspect", "--format", "{{.State.Status}} {{.RestartCount}}",
                         PROJECT], capture=True).decode().strip()
        if state != "running 0":
            raise ManagerError(f"Xray did not stay up after startup ({state}).")
    except (subprocess.CalledProcessError, ManagerError):
        compose("logs", "--tail", "35", "xray")
        raise


def available_listen_address():
    dualstack = socket.has_dualstack_ipv6()
    host = "::" if dualstack else "0.0.0.0"
    family = socket.AF_INET6 if dualstack else socket.AF_INET
    for _, port, *_ in INBOUNDS:
        try:
            with socket.create_server((host, port), family=family, dualstack_ipv6=dualstack):
                pass
        except OSError as exc:
            raise ManagerError(f"Cannot listen on TCP port {port}: {exc}") from exc
    return host


def install():
    if CONFIG.exists() or COMPOSE.exists() or ACTIVE.exists():
        raise ManagerError(f"Existing manager files found in {ROOT}. Use Apply, Start or Update.")
    docker_ready()
    listen = available_listen_address()
    acme = acme_client()
    domain, flags, hostname = choose_certificate(acme, hostname_timeout=INSTALL_DEFAULT_TIMEOUT)
    target, sni = reality_prompt(timeout=INSTALL_DEFAULT_TIMEOUT)
    if not probe_reality(target, sni) and not confirm("Continue with this REALITY target anyway"):
        raise ManagerError("Installation paused. Select another REALITY target and try again.")
    command(["docker", "pull", f"{IMAGE_REPO}:{DEFAULT_TAG}"])
    cert, key = certificate_paths(acme, domain, flags, hostname)
    yaml, in_cert, in_key = compose_yaml(cert, key)
    write_private(HOST_FILE, hostname + "\n")
    write_private(ENV_FILE, f"XRAY_IMAGE={IMAGE_REPO}:{DEFAULT_TAG}\n")
    write_private(CONFIG, json_bytes(make_config(in_cert, in_key, target, sni, listen)))
    write_private(COMPOSE, yaml)
    try:
        validate_config(CONFIG)
        write_private(ACTIVE, CONFIG.read_bytes())
        recreate()
    except (subprocess.CalledProcessError, ManagerError):
        compose("down")
        raise ManagerError("Xray did not start. Files were retained for Apply or Start after fixing the error.")
    print(f"Xray started. Edit {CONFIG} and choose Apply to change the listeners.")


def activate_config():
    previous = ACTIVE.read_bytes() if ACTIVE.is_file() else None
    state = container_state()
    # Validate a snapshot so an editor save cannot change the file between check and apply.
    with tempfile.TemporaryDirectory(prefix=".validate-", dir=ROOT) as work:
        draft = Path(work) / "config.json"
        candidate = CONFIG.read_bytes()
        json.loads(candidate)
        write_private(draft, candidate)
        validate_config(draft)
    if previous == candidate:
        print("The editable config already matches the applied config.")
        return
    write_private(ACTIVE, candidate)
    if state in ("running", "restarting"):
        try:
            recreate()
        except (subprocess.CalledProcessError, ManagerError):
            if previous is not None:
                write_private(ACTIVE, previous)
                recreate()
            raise ManagerError("The edited config failed to start. The edit is still in config.json.")
    print("Config applied." if state == "running" else "Config applied. Choose Start to bring Xray up.")


def use_root_paths():
    config = json.loads(CONFIG.read_bytes())
    matches_applied = ACTIVE.is_file() and config == json.loads(ACTIVE.read_bytes())
    changed = False
    for inbound in config.get("inbounds", []):
        stream = inbound.get("streamSettings", {})
        transport = stream.get("network")
        if transport in ("ws", "xhttp"):
            settings = stream.get(f"{transport}Settings", {})
            if settings.get("path", "/") != "/":
                settings["path"] = "/"
                changed = True
    if changed:
        write_private(CONFIG, json_bytes(config))
    if matches_applied and changed:
        activate_config()
    elif matches_applied:
        print("WebSocket and XHTTP already use /.")
    else:
        print("The editable config uses / for WebSocket and XHTTP. Review it and choose 2 to apply.")


def update_image():
    previous = ENV_FILE.read_text()
    current = previous.strip().removeprefix("XRAY_IMAGE=")
    tag = ask("Official image tag", current.rsplit(":", 1)[-1])
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", tag):
        raise ManagerError("Enter a numbered release tag, for example 26.10.31.")
    candidate = f"{IMAGE_REPO}:{tag}"
    command(["docker", "pull", candidate])
    validate_config(ACTIVE, image=candidate)
    state = container_state()
    write_private(ENV_FILE, f"XRAY_IMAGE={candidate}\n")
    if state in ("running", "restarting"):
        try:
            recreate()
        except (subprocess.CalledProcessError, ManagerError):
            write_private(ENV_FILE, previous)
            recreate()
            raise ManagerError("The candidate image failed to start. The previous image was restored.")
    print(f"Configured image {candidate}")


def public_key(private):
    raw_private = base64.urlsafe_b64decode(private + "=" * (-len(private) % 4))
    if len(raw_private) != 32:
        raise ManagerError("Invalid X25519 private key length.")
    public_der = command(
        ["openssl", "pkey", "-inform", "DER", "-pubout", "-outform", "DER"],
        data=X25519_PRIVATE_PREFIX + raw_private, capture=True,
    )
    if not public_der.startswith(X25519_PUBLIC_PREFIX) or len(public_der) != 44:
        raise ManagerError("OpenSSL did not return an X25519 public key.")
    return base64.urlsafe_b64encode(public_der[-32:]).decode().rstrip("=")


def print_connection_fields(fields):
    for label, value in fields:
        print(f"  {label.ljust(18)}: {value}")


def deployed_cert_dirs():
    try:
        project = json.loads(compose("config", "--format", "json", capture=True))
    except (OSError, ValueError, subprocess.SubprocessError):
        return "See TLS bind mounts in docker-compose.yml"
    volumes = project.get("services", {}).get("xray", {}).get("volumes", [])
    directories = [mount["source"] for mount in volumes if mount.get("type") == "bind"
                   and mount.get("target", "").startswith("/run/xray-tls/")]
    return ", ".join(directories) or "See certificateFile in the applied config"


def show_connections(direct_address=None):
    if not ACTIVE.is_file():
        raise ManagerError("Choose Apply edited config before showing connection info.")
    config = json.loads(ACTIVE.read_text())
    tls_host = HOST_FILE.read_text().strip()
    server = direct_address or tls_host
    if server.startswith("[") and server.endswith("]"):
        server = server[1:-1]
    authority = server
    try:
        parsed_ip = ipaddress.ip_address(server)
        if parsed_ip.version == 6:
            authority = f"[{parsed_ip}]"
    except ValueError:
        if not re.fullmatch(r"[a-zA-Z0-9.-]+", server):
            raise ManagerError("Enter a DNS-only hostname or VPS IP.")

    divider = "-" * 60
    print(divider)
    print("Xray VPS inbound info")
    print(divider)
    print_connection_fields([
        ("Domain / cert SNI", tls_host),
        ("Direct server", server),
        ("Config path", CONFIG),
        ("Applied config", ACTIVE),
        ("Compose path", COMPOSE),
        ("Cert dir", deployed_cert_dirs()),
    ])

    for inbound in config.get("inbounds", []):
        tag = inbound.get("tag", "inbound")
        port = inbound.get("port")
        protocol = inbound.get("protocol", "unknown")
        stream = inbound.get("streamSettings", {})
        network = stream.get("network", "raw")
        security = stream.get("security", "none")
        transport = "tcp" if network == "raw" else network
        fields = [("Tag", tag), ("Server", server), ("Port", port),
                  ("Transport", transport), ("Security", security)]
        if protocol != "vless" or network not in ("ws", "xhttp", "raw", "tcp") or not isinstance(port, int):
            print(f"\n{protocol.upper()}  ({tag})")
            print_connection_fields(fields)
            continue

        account_settings = inbound.get("settings", {})
        clients = account_settings.get("clients") or account_settings.get("users") or []
        title = {"ws": "VLESS WebSocket", "xhttp": "VLESS XHTTP", "tcp": "VLESS TCP"}[transport]
        if security == "reality":
            title = "VLESS REALITY"
        elif security == "tls":
            if transport == "tcp" and any(client.get("flow") == "xtls-rprx-vision" for client in clients):
                title = "VLESS TCP XTLS Vision"
            else:
                title += " + TLS"
        print(f"\n{title}")

        params = {"encryption": "none", "security": security, "type": transport}
        client_stream = {"network": network, "security": security}
        if network in ("ws", "xhttp"):
            settings = stream.get(f"{network}Settings", {})
            path = settings.get("path", "/")
            params["path"] = path
            transport_settings = {"path": path}
            fields.append(("Path", path))
            host = settings.get("host")
            if network == "ws" and not host:
                headers = settings.get("headers", {})
                host = next((value for name, value in headers.items()
                             if name.lower() == "host"), None)
            if host:
                params["host"] = transport_settings["host"] = host
                fields.append(("HTTP Host", host))
            if network == "xhttp":
                mode = settings.get("mode", "auto")
                params["mode"] = transport_settings["mode"] = mode
                fields.append(("XHTTP mode", mode))
            client_stream[f"{network}Settings"] = transport_settings
        if security == "tls":
            tls = stream.get("tlsSettings", {})
            params["sni"] = tls.get("serverName") or tls_host
            tls_client = {"serverName": params["sni"]}
            fields.append(("TLS SNI", params["sni"]))
            if tls.get("alpn"):
                tls_client["alpn"] = tls["alpn"]
                fields.append(("ALPN", ", ".join(tls["alpn"])))
            if transport == "tcp":
                params["fp"] = "chrome"
                tls_client["fingerprint"] = params["fp"]
                fields.append(("Fingerprint", params["fp"]))
            client_stream["tlsSettings"] = tls_client
        if security == "reality":
            settings = stream["realitySettings"]
            public = public_key(settings["privateKey"])
            params.update({
                "sni": settings["serverNames"][0], "fp": "chrome",
                "pbk": public, "sid": settings["shortIds"][0],
            })
            fields.extend([
                ("REALITY target", settings.get("target") or settings.get("dest")),
                ("REALITY SNI", params["sni"]),
                ("REALITY public key", public),
                ("REALITY short ID", params["sid"] or "<empty>"),
                ("Fingerprint", params["fp"]),
            ])
            client_stream["realitySettings"] = {
                "serverName": params["sni"], "fingerprint": params["fp"],
                "password": public, "shortId": params["sid"],
            }
        print_connection_fields(fields)
        if security == "none":
            print("  Plain HTTP transport. Direct traffic is unencrypted.")
        for index, client in enumerate(clients, 1):
            if len(clients) > 1:
                print(f"  Client {index}")
            user = client.get("email") or tag
            identity = client["id"]
            flow = client.get("flow")
            account = {"id": identity, "encryption": "none"}
            query = dict(params)
            if flow:
                query["flow"] = account["flow"] = flow
            label = quote(str(user), safe="")
            link = (f"vless://{quote(identity, safe='')}@{authority}:{port}?"
                    f"{urlencode(query, quote_via=quote)}#{label}")
            print_connection_fields([
                ("User", user), ("UUID", identity), ("Flow", flow or "<empty>"), ("Link", link),
            ])
            outbound = {
                "tag": f"{tag}-out", "protocol": "vless",
                "settings": {"vnext": [{"address": server, "port": port, "users": [account]}]},
                "streamSettings": client_stream,
            }
            print("  Xray outbound snippet:")
            print(textwrap.indent(json.dumps(outbound, indent=2), "  "))

    print(divider)
    print("""
Cloudflare is optional. Use a supported client-facing port such as 443
and map it to the WS/XHTTP origin port. If cloudflared shares the VPS
network, the plain origins are http://127.0.0.1:9043 (WS) and
http://127.0.0.1:9343 (XHTTP). For TLS Tunnel origins use https and set
originServerName to the certificate hostname. For proxied XHTTP, try
packet-up first and verify the client and route. Use a DNS-only hostname
or VPS IP for direct access, including REALITY and Vision.
""")
    print(divider)


def start_or_restart(restart):
    if not ACTIVE.is_file():
        raise ManagerError("Choose Apply edited config before starting.")
    if not restart and container_state() == "running":
        print("Xray is already running.")
        return
    validate_config(ACTIVE)
    recreate()


def show_status():
    compose("ps", "-a")
    print(f"Image  {ENV_FILE.read_text().strip().removeprefix('XRAY_IMAGE=')}")
    if ACTIVE.is_file():
        print("Applied inbounds")
        for inbound in json.loads(ACTIVE.read_text()).get("inbounds", []):
            print(f"  {inbound.get('port', '-')}  {inbound.get('tag', inbound['protocol'])}")
        if CONFIG.read_bytes() != ACTIVE.read_bytes():
            print("config.json has edits waiting to be applied.")


def remove_container():
    if confirm("Remove the Xray container and keep config and certificate files"):
        compose("down")


def main():
    if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
        print("Usage: sudo bash xray_docker_multi.sh")
        return
    if len(sys.argv) != 1 or os.geteuid() != 0 or not sys.stdin.isatty():
        raise ManagerError("Run sudo bash xray_docker_multi.sh in an interactive VPS terminal.")
    os.umask(0o077)
    ROOT.mkdir(mode=0o700, exist_ok=True)
    with (ROOT / ".manager.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise ManagerError("Another Xray manager session is already open.") from exc
        menu()


def show_menu_header(divider):
    installed = all(path.is_file() for path in (COMPOSE, ENV_FILE, CONFIG, ACTIVE, HOST_FILE))
    print(divider)
    print(f"  Xray Manager   ({ROOT})")
    print(divider)
    if installed:
        try:
            hostname = HOST_FILE.read_text().strip()
        except OSError:
            hostname = "unavailable"
        print(f"  status: installed  domain: {hostname}")
    elif any(path.exists() for path in (COMPOSE, CONFIG, ACTIVE)):
        print("  status: setup incomplete")
    else:
        print("  status: not installed")

    if ACTIVE.is_file():
        label = "  ports : "
        try:
            inbounds = json.loads(ACTIVE.read_text()).get("inbounds", [])
            ports = [(entry.get("tag") or entry.get("protocol", "inbound"), entry["port"])
                     for entry in inbounds if entry.get("port") is not None]
        except (OSError, ValueError, AttributeError, TypeError):
            print(label + "unavailable")
            print(divider)
            return
    else:
        label = "  default ports: "
        ports = [(tag, port) for tag, port, *_ in INBOUNDS]

    names = {"vless-ws": "websocket", "vless-ws-tls": "websocket-tls"}
    values = "  ".join(f"{names.get(tag, tag)}={port}" for tag, port in ports)
    print(textwrap.fill(values or "none", width=78, initial_indent=label,
                        subsequent_indent=" " * len(label), break_on_hyphens=False,
                        break_long_words=False))
    print(divider)


def menu():
    divider = "-" * 60
    actions = {
        "1": ("Install with default inbounds", install),
        "2": ("Validate and apply edited config", activate_config),
        "3": ("Show config & connection info", show_connections),
        "4": ("Start", lambda: start_or_restart(False)),
        "5": ("Restart", lambda: start_or_restart(True)),
        "6": ("Stop", lambda: compose("stop")),
        "7": ("Logs (follow)", lambda: compose("logs", "--tail", "60", "-f")),
        "8": ("Update official Xray image", update_image),
        "9": ("Status", show_status),
        "10": ("Probe a REALITY target", lambda: probe_reality(*reality_prompt())),
        "11": ("Remove container and keep files", remove_container),
        "12": ("Set WebSocket and XHTTP paths to /", use_root_paths),
    }
    while True:
        if sys.stdout.isatty() and os.environ.get("TERM", "dumb") != "dumb":
            print("\033[2J\033[H", end="")
        show_menu_header(divider)
        for choice, (title, _) in actions.items():
            print(f"  {choice:>2}) {title}")
        print("   0) Exit")
        print(divider)
        try:
            selection = ask("Choose").split(maxsplit=1)
            choice = selection[0] if selection else ""
            if choice == "0":
                return
            if choice not in actions:
                print("Choose a listed number.")
            elif choice not in ("1", "10") and not COMPOSE.is_file():
                print("Choose Install first.")
            elif choice == "3":
                actions[choice][1](*selection[1:])
            elif len(selection) > 1:
                print("Only option 3 accepts a host or IP.")
            else:
                actions[choice][1]()
        except EOFError:
            return
        except KeyboardInterrupt:
            print()
        except (ManagerError, OSError, ValueError, subprocess.SubprocessError) as exc:
            if isinstance(exc, subprocess.CalledProcessError):
                print(f"Error: {shlex.quote(str(exc.cmd[0]))} exited with status {exc.returncode}.", file=sys.stderr)
                if exc.stderr:
                    print(exc.stderr.decode(errors="replace").strip(), file=sys.stderr)
            else:
                print(f"Error: {exc}", file=sys.stderr)
        try:
            input("\nPress Enter to continue...")
        except EOFError:
            return
        except KeyboardInterrupt:
            print()


if __name__ == "__main__":
    try:
        main()
    except (ManagerError, OSError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)
PYTHON
)" "$@"
