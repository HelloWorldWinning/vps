#!/usr/bin/env bash
# Hysteria 2 Docker manager for Debian/Ubuntu. Run: bash hy2_manager.sh
# Generated files, backups and exports live below hy2_main_path.
# Docker storage and the pre-existing HOST acme.sh installation are external.
# --install-cert records deployment paths/reloadcmd in the chosen acme certificate.
# It never issues/renews certificates, opens TCP 80, or restarts other containers.

set -uo pipefail
umask 077

hy2_main_path="/root/hy2_d"
default_auth="hy2_password"
default_salamander="salamander_password" # Stored as an inactive comment until enabled.
CONTAINER="hy2"
IMAGE="tobyxdd/hysteria:latest"
STATE="${hy2_main_path}/manager.json"
HELPER="${hy2_main_path}/lib/hy2_state.py"
ACME_BIN=""
ACME_HOME=""
TX=""
ACME_CHANGED=0
REPLY=""
COMPOSE=()

info() { printf '\n[INFO] %s\n' "$*"; }
ok() { printf '[ OK ] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
err() { printf '[ERR ] %s\n' "$*" >&2; }
ask() {
	REPLY=""
	IFS= read -r -u 3 -p "$1" REPLY
}
ask_default() {
	local label="$1" value="$2" seconds="${3:-0}"
	REPLY=""
	if ((seconds > 0)); then
		if ! IFS= read -r -u 3 -t "$seconds" -p "$label [$value; ${seconds}s]: " REPLY; then
			printf '\n'
			REPLY=""
		fi
	else
		ask "$label [$value]: " || return 1
	fi
	REPLY="${REPLY:-$value}"
}
confirm() { ask "$1 [y/N]: " && [[ "$REPLY" =~ ^[yY]([eE][sS])?$ ]]; }
pause_menu() { ask '按 Enter 返回菜单...' || true; }
py() { python3 "$HELPER" "$hy2_main_path" "$@"; }
get() { py get "$1"; }
put() { printf '%s' "$2" | py set "$1"; }
dc() { "${COMPOSE[@]}" -p hy2_manager -f "${hy2_main_path}/docker-compose.yml" "$@"; }
container_exists() { docker inspect "$CONTAINER" >/dev/null 2>&1; }
container_running() { [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" == true ]]; }
require_install() {
	[[ -f "$STATE" && -s "${hy2_main_path}/docker-compose.yml" ]] || {
		err '尚未安装，请先选择 1。'
		return 1
	}
}
require_owned() {
	local owner
	if container_exists; then
		owner="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$CONTAINER")"
		[[ "$owner" == hy2_manager ]] || {
			err "容器名 ${CONTAINER} 已被其他部署占用。请先修改脚本顶部 CONTAINER。"
			return 1
		}
	fi
}

apt_install() {
	command -v apt-get >/dev/null || {
		err '本脚本自动安装依赖仅支持 Debian/Ubuntu。'
		return 1
	}
	if [[ "${APT_UPDATED:-0}" != 1 ]]; then
		apt-get update || return 1
		APT_UPDATED=1
	fi
	DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}
ensure_tools() {
	local packages=() cmd pkg
	for cmd in python3 openssl curl qrencode flock ss; do
		case "$cmd" in
		python3) pkg=python3 ;; openssl) pkg=openssl ;; curl) pkg=curl ;;
		qrencode) pkg=qrencode ;; flock) pkg=util-linux ;; ss) pkg=iproute2 ;;
		esac
		command -v "$cmd" >/dev/null || packages+=("$pkg")
	done
	((${#packages[@]} == 0)) || apt_install ca-certificates "${packages[@]}" || return 1
}
detect_compose() {
	COMPOSE=()
	if docker compose version >/dev/null 2>&1; then
		COMPOSE=(docker compose)
	elif command -v docker-compose >/dev/null && docker-compose version >/dev/null 2>&1; then
		COMPOSE=(docker-compose)
	else
		return 1
	fi
}
ensure_docker() {
	if ! command -v docker >/dev/null; then
		info '安装发行版提供的 Docker...'
		apt_install docker.io || return 1
	fi
	if ! docker info >/dev/null 2>&1; then
		command -v systemctl >/dev/null && systemctl start docker || true
		docker info >/dev/null 2>&1 || {
			err 'Docker daemon 无法访问。'
			return 1
		}
	fi
	if ! detect_compose; then
		if apt-cache show docker-compose-v2 >/dev/null 2>&1; then
			apt_install docker-compose-v2 || return 1
		elif apt-cache show docker-compose-plugin >/dev/null 2>&1; then
			apt_install docker-compose-plugin || return 1
		else
			apt_install docker-compose || return 1
		fi
		detect_compose || {
			err '无法找到可用的 Docker Compose。'
			return 1
		}
	fi
	# Docker autostart provides container autostart through restart: unless-stopped.
	if command -v systemctl >/dev/null; then
		systemctl enable docker >/dev/null 2>&1 || warn '未能设置 Docker 开机启动，请检查你的服务管理器。'
	fi
}

write_helper() {
	mkdir -p "${hy2_main_path}/lib" "${hy2_main_path}/hooks" \
		"${hy2_main_path}/certs" "${hy2_main_path}/backups" "${hy2_main_path}/exports" || return 1
	cat >"$HELPER" <<'PY'
#!/usr/bin/env python3
"""Standard-library-only state validation, YAML generation and client exports."""
import datetime
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from urllib.parse import quote, urlencode

root = Path(sys.argv[1])
state = root / 'manager.json'
action = sys.argv[2]
args = sys.argv[3:]

def atom(x):
    return json.dumps(x, ensure_ascii=False)

def yaml(x, n=0):
    pad = ' ' * n
    lines = []
    if isinstance(x, dict):
        for k, v in x.items():
            if isinstance(v, (dict, list)) and v:
                lines += [pad + atom(k) + ':', yaml(v, n + 2)]
            else:
                lines.append(pad + atom(k) + ': ' + atom(v))
    elif isinstance(x, list):
        for v in x:
            if isinstance(v, (dict, list)) and v:
                lines += [pad + '-', yaml(v, n + 2)]
            else:
                lines.append(pad + '- ' + atom(v))
    return '\n'.join(lines)

def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + '.tmp')
    tmp.write_text(text, encoding='utf-8')
    tmp.chmod(0o600)
    os.replace(tmp, path)

def clean(s, what='value'):
    if not isinstance(s, str) or not s or any(ord(c) < 32 or ord(c) == 127 for c in s):
        raise ValueError(what + ' must be nonempty and contain no control characters')
    return s

def host(s):
    s = clean(s, 'host').strip().removeprefix('[').removesuffix(']')
    try:
        return str(ipaddress.ip_address(s))
    except ValueError:
        pass
    s = s.rstrip('.').encode('idna').decode('ascii')
    if len(s) > 253 or not all(re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?', p)
                                 for p in s.split('.')):
        raise ValueError('请输入有效 IP 或域名，不要包含协议、端口或路径')
    return s.lower()

def validate(s):
    s['server'] = host(s['server'])
    s['sni'] = host(s['sni'])
    if not (1 <= s['port_start'] <= s['port_end'] <= 65535):
        raise ValueError('端口范围必须满足 1 <= start <= end <= 65535')
    if s['outbound'] not in ['auto', '46', '64', '4', '6']:
        raise ValueError('invalid outbound mode')
    if s['auth_mode'] not in ['password', 'userpass']:
        raise ValueError('invalid auth mode')
    clean(s['password'], 'password')
    clean(s['obfs_password'], 'obfs password')
    for name, password in s['users'].items():
        if not re.fullmatch(r'[A-Za-z0-9_.-]{1,48}', name):
            raise ValueError('用户名只允许 1–48 个英文字母、数字、下划线、点或短横线')
        clean(password, 'user password')
    if s['auth_mode'] == 'userpass' and not s['users']:
        raise ValueError('多用户模式至少需要一个用户')
    if s['cert_mode'] not in ['self', 'acme']:
        raise ValueError('invalid certificate mode')
    if s['backend'] not in ['nftables', 'iptables']:
        raise ValueError('invalid firewall backend')
    for k in ['obfs', 'ignore_client_bandwidth']:
        if type(s[k]) is not bool:
            raise ValueError('invalid boolean: ' + k)
    return s

def save(s):
    validate(s)
    write(state, json.dumps(s, ensure_ascii=False, indent=2) + '\n')

def entries(s):
    return list(s['users'].items()) if s['auth_mode'] == 'userpass' else [('', s['password'])]

def server_config(s):
    start, end = s['port_start'], s['port_end']
    listen = ':' + (str(start) if start == end else f'{start}-{end}')
    auth = {'type': 'password', 'password': s['password']}
    if s['auth_mode'] == 'userpass':
        auth = {'type': 'userpass', 'userpass': s['users']}
    c = {'listen': listen,
         'tls': {'cert': '/etc/hy2/certs/fullchain.cer', 'key': '/etc/hy2/certs/private.key'},
         'auth': auth,
         'ignoreClientBandwidth': s['ignore_client_bandwidth'],
         'disableUDP': False, 'udpIdleTimeout': '60s',
         'outbounds': [{'name': 'direct', 'type': 'direct', 'direct': {'mode': s['outbound']}}],
         'masquerade': {'type': 'file', 'file': {'dir': '/etc/hy2/www'}}}
    # Use the official non-Brutal default (BBR); omit newer version-specific tuning keys.
    # No bandwidth limit is imposed; clients omit bandwidth for automatic BBR.
    # No TCP HTTP/HTTPS listener is enabled and no ACME section is generated.
    if s['obfs']:
        c['obfs'] = {'type': 'salamander', 'salamander': {'password': s['obfs_password']}}
    text = '# Generated by hy2_manager.sh; use the dashboard to change managed settings.\n'
    text += '# QUIC receive windows / congestion: official defaults (BBR without client bandwidth).\n'
    text += yaml(c) + '\n'
    if not s['obfs']:
        text += ('\n# Salamander is OFF. Enable it in the dashboard only when needed.\n'
                 '# obfs:\n#   type: salamander\n#   salamander:\n#     password: ' + atom(s['obfs_password']) + '\n')
    return text

def compose(s):
    return {'services': {'hysteria': {
        'image': s['image_ref'], 'container_name': s['container'],
        'user': '0:0', 'network_mode': 'host', 'restart': 'unless-stopped',
        'cap_add': ['NET_ADMIN'], 'stop_grace_period': '30s',
        'environment': {'HYSTERIA_FIREWALL_BACKEND': s['backend']},
        'volumes': [str(root / 'config.yaml') + ':/etc/hy2/config.yaml:ro',
                    str(root / 'certs') + ':/etc/hy2/certs:ro',
                    str(root / 'www') + ':/etc/hy2/www:ro'],
        'command': ['server', '-c', '/etc/hy2/config.yaml'],
        'ulimits': {'nofile': {'soft': 65536, 'hard': 65536}},
        'logging': {'driver': 'json-file', 'options': {'max-size': '10m', 'max-file': '3'}}}}}

def fingerprint():
    r = subprocess.run(['openssl', 'x509', '-in', str(root / 'certs/fullchain.cer'),
                        '-noout', '-fingerprint', '-sha256'], check=True,
                       capture_output=True, text=True)
    return r.stdout.strip().split('=', 1)[1]

def export(s):
    out = root / 'exports'
    # Whole directory is manager-owned; remove previous user exports after password/user changes.
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(mode=0o700)
    fp = fingerprint()
    iphost = '[' + s['server'] + ']' if ':' in s['server'] else s['server']
    prange = str(s['port_start']) if s['port_start'] == s['port_end'] else f"{s['port_start']}-{s['port_end']}"
    for i, (name, password) in enumerate(entries(s), 1):
        stem = f'{i:02d}-' + (name or 'single')
        auth = (name + ':' if name else '') + password
        userinfo = (quote(name, safe='') + ':' if name else '') + quote(password, safe='')
        params = {'sni': s['sni'], 'insecure': '1' if s['cert_mode'] == 'self' else '0'}
        if s['cert_mode'] == 'self':
            params['pinSHA256'] = fp
        if s['obfs']:
            params.update({'obfs': 'salamander', 'obfs-password': s['obfs_password']})
        def uri(port):
            return ('hysteria2://' + userinfo + '@' + iphost + ':' + str(port) + '/?' +
                    urlencode(params, quote_via=quote) + '#' + quote('hy2-' + (name or s['server']), safe=''))
        normal, hopping = uri(s['port_start']), uri(prange)
        write(out / (stem + '.uri.txt'), normal + '\n')
        write(out / (stem + '.hopping-uri.txt'), hopping + '\n')
        tls = {'sni': s['sni'], 'insecure': s['cert_mode'] == 'self'}
        if s['cert_mode'] == 'self':
            tls['pinSHA256'] = fp
        client = {'server': f'{iphost}:{prange}', 'auth': auth, 'tls': tls,
                  'transport': {'type': 'udp', 'udp': {'hopInterval': '30s'}},
                  'socks5': {'listen': '127.0.0.1:1080'}, 'http': {'listen': '127.0.0.1:8080'}}
        if s['obfs']:
            client['obfs'] = {'type': 'salamander', 'salamander': {'password': s['obfs_password']}}
        write(out / (stem + '.client.yaml'), '# Official Hysteria 2 client; bandwidth omitted => BBR.\n' + yaml(client) + '\n')
        details = [f'用户: {name or "单密码模式"}', '协议: Hysteria 2 / UDP',
                   f'服务器: {s["server"]}', f'单端口: {s["port_start"]}',
                   f'端口跳跃范围: {prange}', '跳跃间隔: 30 秒（客户端支持时填写）',
                   f'认证字符串: {auth}', f'TLS / SNI: {s["sni"]}', 'ALPN: h3（或客户端默认）',
                   f'允许不安全证书: {"是；同时使用指纹固定" if s["cert_mode"] == "self" else "否"}',
                   f'证书 SHA256: {fp}',
                   f'Salamander: {"开启" if s["obfs"] else "关闭"}',
                   f'上传/下载带宽: 留空（默认 BBR）；服务端忽略客户端带宽: {s["ignore_client_bandwidth"]}',
                   'Shadowrocket: 导入单端口 URI 或扫描其二维码；跳跃范围可按客户端界面手动填写。',
                   '单端口 URI 可直接连接，但不会自动启用端口跳跃。',
                   'hopping-uri 使用官方端口范围 URI；客户端不支持时使用单端口 URI。',
                   '若客户端忽略 pinSHA256，请手动固定证书/导入信任，或换用已有公信证书。',
                   'Quantumult X: 未确认官方支持 Hy2，不生成虚构的专用配置。']
        if s['obfs']:
            details.append('Salamander 密码: ' + s['obfs_password'])
        write(out / (stem + '.details.txt'), '\n'.join(details) + '\n')
        for suffix, content in [('', normal), ('.hopping', hopping)]:
            result = subprocess.run(['qrencode', '-l', 'M', '-o', str(out / (stem + suffix + '.png'))],
                                    input=content, text=True, capture_output=True)
            if result.returncode:
                raise RuntimeError('二维码生成失败: ' + result.stderr)

try:
    if action == 'init':
        save({'server': 'hy2.local', 'sni': 'hy2.local', 'port_start': 56000, 'port_end': 57999,
              'password': args[0], 'auth_mode': 'password', 'users': {},
              'obfs': False, 'obfs_password': args[1], 'outbound': 'auto',
              'ignore_client_bandwidth': False, 'cert_mode': 'self', 'cert_domain': '',
              'image_ref': 'tobyxdd/hysteria:latest', 'backend': 'nftables', 'container': args[2]})
    elif action == 'validate-host':
        print(host(sys.stdin.read()))
    elif action == 'check-ports':
        # stdin is the output of ss -H -u -a -n. Includes IPv4 and IPv6.
        lo, hi = map(int, args)
        clashes = []
        for line in sys.stdin:
            columns = line.split()
            if len(columns) >= 5:
                try:
                    port = int(columns[3].rsplit(':', 1)[1])
                except (ValueError, IndexError):
                    continue
                if lo <= port <= hi:
                    clashes.append(line.rstrip())
        if clashes:
            print('UDP 范围已有套接字占用（含临时出站套接字），请换范围或稍后重试：', file=sys.stderr)
            print('\n'.join(clashes[:20]), file=sys.stderr)
            sys.exit(1)
    else:
        s = validate(json.loads(state.read_text(encoding='utf-8')))
        if action == 'get':
            value = s[args[0]]
            print(json.dumps(value) if isinstance(value, (bool, int, dict, list)) else value)
        elif action == 'set':
            key, value = args[0], sys.stdin.read()
            if key not in s:
                raise ValueError('unknown setting')
            if isinstance(s[key], (bool, int, dict, list)):
                value = json.loads(value)
            s[key] = value
            save(s)
        elif action == 'ports':
            s['port_start'], s['port_end'] = map(int, args)
            save(s)
        elif action == 'user-add':
            s['users'][args[0]] = sys.stdin.read()
            s['auth_mode'] = 'userpass'
            save(s)
        elif action == 'user-del':
            del s['users'][args[0]]
            save(s)
        elif action == 'users':
            for name in s['users']:
                print(name)
        elif action == 'render':
            dest = Path(args[0])
            write(dest / 'config.yaml', server_config(s))
            write(dest / 'docker-compose.yml', yaml(compose(s)) + '\n')
        elif action == 'export':
            export(s)
        else:
            raise ValueError('unknown operation: ' + action)
except (ValueError, OSError, KeyError, RuntimeError, subprocess.CalledProcessError) as exc:
    print('hy2: ' + str(exc), file=sys.stderr)
    sys.exit(1)
PY
	chmod 600 "$HELPER" || return 1
	mkdir -p "${hy2_main_path}/www" || return 1
	if [[ ! -f "${hy2_main_path}/www/index.html" ]]; then
		printf '%s\n' '<!doctype html><html lang="en"><meta charset="utf-8"><title>Welcome</title><h1>Welcome</h1><p>This server is running.</p></html>' \
			>"${hy2_main_path}/www/index.html" || return 1
	fi
	# Script is separate so acme.sh has a stable reload target. It only restarts this container.
	{
		printf '#!/usr/bin/env bash\nset -uo pipefail\n'
		printf 'CONTAINER=%q\n' "$CONTAINER"
		cat <<'HOOK'
if ! command -v docker >/dev/null; then
    echo 'hy2: Docker not found for certificate reload' >&2
    exit 1
fi
# A stopped/uninstalled container should stay stopped. Initial installation has no container yet.
running="$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" || exit 0
[[ "$running" == true ]] || exit 0
owner="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$CONTAINER")" || exit 1
[[ "$owner" == hy2_manager ]] || exit 0
docker restart -t 30 "$CONTAINER"
HOOK
	} >"${hy2_main_path}/hooks/reload-hy2.sh" || return 1
	chmod 700 "${hy2_main_path}/hooks/reload-hy2.sh"
}

begin_tx() {
	[[ -z "$TX" ]] || {
		err '另一个配置事务尚未完成。'
		return 1
	}
	require_owned || return 1
	ACME_CHANGED=0
	TX="$(mktemp -d "${hy2_main_path}/backups/$(date +%Y%m%d_%H%M%S).XXXXXX")" || return 1
	local f
	for f in manager.json config.yaml docker-compose.yml certs exports; do
		if [[ -e "${hy2_main_path}/$f" ]]; then
			cp -a "${hy2_main_path}/$f" "$TX/" || {
				TX=""
				return 1
			}
		fi
	done
	if container_running; then touch "$TX/was-running"; fi
	ok "已备份: $TX"
}
restore_tx() {
	[[ -n "$TX" ]] || return 0
	local f backup="$TX"
	warn "操作失败，恢复本地配置和证书: $backup"
	if container_exists && require_owned; then
		docker stop -t 30 "$CONTAINER" >/dev/null || warn '容器未能正常停止。'
	fi
	for f in manager.json config.yaml docker-compose.yml certs exports; do
		rm -rf "${hy2_main_path:?}/$f"
		if [[ -e "$backup/$f" ]]; then cp -a "$backup/$f" "$hy2_main_path/" || return 1; fi
	done
	TX=""
	if [[ -f "$backup/was-running" && -f "${hy2_main_path}/docker-compose.yml" ]]; then
		dc up -d || {
			err '恢复配置后启动失败，请查看日志。'
			return 1
		}
	fi
	if [[ "$ACME_CHANGED" == 1 ]]; then
		warn '外部 acme.sh 的部署登记不在本地回滚范围；本脚本不会改回其他服务的登记。'
	fi
}
commit_tx() {
	TX=""
	ACME_CHANGED=0
}
interrupted() {
	trap - INT TERM
	[[ -z "$TX" ]] || restore_tx || true
	exit 130
}

detect_acme() {
	ACME_BIN=""
	ACME_HOME=""
	local candidate
	for candidate in "${HY2_ACME_BIN:-}" "$(command -v acme.sh 2>/dev/null || true)" \
		/root/.acme.sh/acme.sh "${HOME}/.acme.sh/acme.sh"; do
		if [[ -n "$candidate" && -x "$candidate" ]]; then
			ACME_BIN="$(readlink -f "$candidate")"
			break
		fi
	done
	[[ -n "$ACME_BIN" ]] || {
		err '没有找到主机 acme.sh，请先在主机管理好已有证书。'
		return 1
	}
	ACME_HOME="${HY2_ACME_HOME:-$(dirname "$ACME_BIN")}"
}
pick_domain() {
	detect_acme || return 1
	local listing choice row i=0 domain key ecc
	local domains=() kinds=()
	listing="$("$ACME_BIN" --home "$ACME_HOME" --list 2>"${hy2_main_path}/acme-list.err")" || {
		cat "${hy2_main_path}/acme-list.err" >&2
		return 1
	}
	while read -r domain key; do
		[[ -n "$domain" ]] || continue
		domains+=("$domain")
		kinds+=("$key")
	done < <(printf '%s\n' "$listing" | awk 'NR>1 && NF>1 {print $1, $2}')
	((${#domains[@]} > 0)) || {
		err "acme.sh --list 没有已登记的证书: $ACME_HOME"
		return 1
	}
	printf '\nHOST acme.sh 已有证书:\n'
	for row in "${!domains[@]}"; do
		printf '  %d) %s  [key=%s]\n' "$((row + 1))" "${domains[$row]}" "${kinds[$row]}"
	done
	while :; do
		ask "选择证书 [1-${#domains[@]}，0 返回]: " || return 1
		choice="$REPLY"
		[[ "$choice" == 0 ]] && return 1
		if [[ "$choice" =~ ^[0-9]{1,6}$ ]]; then
			i=$((10#$choice))
			if ((i >= 1 && i <= ${#domains[@]})); then break; fi
		fi
		warn '无效选择。'
	done
	DOMAIN="${domains[$((i - 1))]}"
	ecc="${kinds[$((i - 1))]}"
	ECC=()
	if [[ "$ecc" == *[Ee][Cc]* ]]; then
		ECC=(--ecc)
	elif [[ -d "${ACME_HOME}/${DOMAIN}_ecc" && ! -d "${ACME_HOME}/${DOMAIN}" ]]; then
		ECC=(--ecc)
	fi
	ok "已选择: $DOMAIN (${ecc})"
}
validate_cert() {
	local dir="$1" cert_pub key_pub expiry
	[[ -s "$dir/fullchain.cer" && -s "$dir/private.key" ]] || {
		err '缺少证书/私钥文件。'
		return 1
	}
	openssl x509 -in "$dir/fullchain.cer" -noout -checkend 0 >/dev/null || {
		err '证书无效或已经过期。'
		return 1
	}
	cert_pub="$(openssl x509 -in "$dir/fullchain.cer" -pubkey -noout)" || return 1
	key_pub="$(openssl pkey -in "$dir/private.key" -passin pass: -pubout 2>/dev/null)" || {
		err '私钥无效，或需要口令。'
		return 1
	}
	[[ "$cert_pub" == "$key_pub" ]] || {
		err '证书与私钥不匹配。'
		return 1
	}
	chmod 600 "$dir/private.key" || return 1
}
certificate_menu() {
	local choice name certdir="${hy2_main_path}/certs" temp
	printf '\n证书方式:\n  1) OpenSSL 自签 20 年（默认）\n  2) 从 HOST acme.sh --list 选择已有证书并 --install-cert\n'
	ask_default '选择' 1 || return 1
	choice="$REPLY"
	case "$choice" in
	1)
		name="$(get sni)" || return 1
		ask_default '证书域名/SNI（也可以是 IP）' "$name" || return 1
		name="$(printf '%s' "$REPLY" | py validate-host)" || return 1
		temp="$(mktemp -d "${hy2_main_path}/certs-new.XXXXXX")" || return 1
		local san
		san="$(
			python3 - "$name" <<'PY'
import ipaddress, sys
try:
    ipaddress.ip_address(sys.argv[1]); prefix='IP:'
except ValueError:
    prefix='DNS:'
print(prefix+sys.argv[1])
PY
		)" || {
			rm -rf "$temp"
			return 1
		}
		if ! openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -sha256 \
			-nodes -days 7305 -subj "/CN=$name" -addext "subjectAltName=$san" \
			-addext 'basicConstraints=critical,CA:FALSE' \
			-addext 'keyUsage=critical,digitalSignature' \
			-addext 'extendedKeyUsage=serverAuth' \
			-keyout "$temp/private.key" -out "$temp/fullchain.cer"; then
			rm -rf "$temp"
			return 1
		fi
		validate_cert "$temp" || {
			rm -rf "$temp"
			return 1
		}
		mkdir -p "$certdir" || return 1
		cp "$temp/fullchain.cer" "$temp/private.key" "$certdir/" || {
			rm -rf "$temp"
			return 1
		}
		rm -rf "$temp"
		put cert_mode self && put cert_domain "$name" && put sni "$name" || return 1
		ok '已生成 ECDSA P-256 自签证书，有效期约 20 年。'
		;;
	2)
		pick_domain || return 1
		name="$DOMAIN"
		[[ "$name" != \*.* ]] || name="$(get server)"
		ask_default '客户端 TLS SNI（必须被所选证书覆盖）' "$name" || return 1
		name="$(printf '%s' "$REPLY" | py validate-host)" || return 1
		info '调用 --install-cert；该命令会登记此证书的部署路径与 reloadcmd。'
		info '只操作 Hy2 容器，不执行签发/续期，也不编辑其他代理配置。'
		mkdir -p "$certdir" || return 1
		# acme.sh performs a copy/install, not a symlink. Persisted paths are its normal behavior.
		ACME_CHANGED=1
		"$ACME_BIN" --home "$ACME_HOME" --install-cert -d "$DOMAIN" "${ECC[@]}" \
			--fullchain-file "$certdir/fullchain.cer" \
			--key-file "$certdir/private.key" \
			--reloadcmd "'${hy2_main_path}/hooks/reload-hy2.sh'" || return 1
		validate_cert "$certdir" || return 1
		if python3 - "$name" <<'PY'; then
import ipaddress, sys
try: ipaddress.ip_address(sys.argv[1])
except ValueError: sys.exit(1)
PY
			openssl x509 -in "$certdir/fullchain.cer" -noout -checkip "$name" || return 1
		else
			openssl x509 -in "$certdir/fullchain.cer" -noout -checkhost "$name" || return 1
		fi
		put cert_mode acme && put cert_domain "$DOMAIN" && put sni "$name" || return 1
		ok '已有证书已安装到 Hy2；主机原有 acme.sh 定时续期机制负责续期。'
		;;
	*)
		err '无效证书选项。'
		return 1
		;;
	esac
	chmod 600 "$certdir/private.key"
}

choose_address() {
	local current detected=""
	current="$(get server)" || return 1
	if [[ "$current" == hy2.local ]]; then
		detected="$(curl -fsS --connect-timeout 3 --max-time 5 https://api64.ipify.org 2>/dev/null)" || detected=""
		if [[ -n "$detected" ]]; then
			current="$(printf '%s' "$detected" | py validate-host)" || current=hy2.local
		fi
	fi
	info '连接地址填服务器公网 IP 或 DNS-only 域名；普通 Cloudflare 橙云不能代理此 UDP 服务。'
	while :; do
		ask_default '客户端连接地址' "$current" || return 1
		if current="$(printf '%s' "$REPLY" | py validate-host)"; then
			[[ "$current" != hy2.local ]] || {
				warn '未探测到公网地址，请填写实际 IP/域名。'
				continue
			}
			put server "$current" || return 1
			if [[ "$(get sni)" == hy2.local ]]; then put sni "$current" || return 1; fi
			return 0
		fi
		current="$(get server)"
	done
}
pull_image() {
	local ref
	info "拉取 $IMAGE（现有容器保持运行，直至应用配置）..."
	docker pull "$IMAGE" || return 1
	ref="$(docker image inspect -f '{{range .RepoDigests}}{{println .}}{{end}}' "$IMAGE" |
		awk '/tobyxdd\/hysteria@sha256:/{print; exit}')" || return 1
	[[ -n "$ref" ]] || {
		err '镜像缺少 RepoDigest，无法固定版本及可靠回滚。'
		return 1
	}
	put image_ref "$ref" || return 1
	ok "镜像已固定: $ref"
}
check_backend() {
	local ref backend
	ref="$(get image_ref)" || return 1
	# Read-only probe; no firewall rules are created by this manager.
	backend="$(docker run --rm --network host --cap-add NET_ADMIN --user 0:0 \
		--entrypoint /bin/sh "$ref" -c '
        if command -v nft >/dev/null 2>&1 && nft list tables >/dev/null 2>&1; then
            echo nftables
        elif command -v iptables >/dev/null 2>&1 && command -v ip6tables >/dev/null 2>&1 &&
             iptables -t nat -S >/dev/null 2>&1; then
            echo iptables
        else
            echo "hy2: container lacks usable nft/iptables or NET_ADMIN permission" >&2
            exit 1
        fi')" || {
		err '镜像防火墙工具/内核权限检查失败，无法启用内置端口跳跃。'
		return 1
	}
	put backend "$backend" || return 1
	ok "Hysteria 内置端口跳跃后端: $backend"
}
check_ports() {
	local sockets
	sockets="$(ss -H -u -a -n)" || return 1
	printf '%s\n' "$sockets" | py check-ports "$(get port_start)" "$(get port_end)"
}
wait_ready() {
	local since="$1" i running restarts logs
	for ((i = 0; i < 25; i++)); do
		running="$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)"
		restarts="$(docker inspect -f '{{.RestartCount}}' "$CONTAINER" 2>/dev/null)"
		logs="$(docker logs --since "$since" "$CONTAINER" 2>&1)" || logs=""
		if [[ "$running" == true && "$restarts" == 0 && "$logs" == *'server up and running'* ]]; then
			sleep 2
			container_running && [[ "$(docker inspect -f '{{.RestartCount}}' "$CONTAINER")" == 0 ]] && return 0
		fi
		[[ "${restarts:-0}" =~ ^[0-9]+$ ]] && ((restarts > 0)) && break
		sleep 1
	done
	err '服务未通过启动日志检查。最近日志：'
	docker logs --tail 60 "$CONTAINER" 2>&1 || true
	return 1
}
render_and_start() {
	local stage started
	require_owned || return 1
	validate_cert "${hy2_main_path}/certs" || return 1
	stage="$(mktemp -d "${hy2_main_path}/render.XXXXXX")" || return 1
	if ! py render "$stage" || ! "${COMPOSE[@]}" -p hy2_manager -f "$stage/docker-compose.yml" config --quiet; then
		rm -rf "$stage"
		return 1
	fi
	# Graceful stop lets Hysteria clean its own previous range rules before replacement.
	if container_running; then
		docker stop -t 30 "$CONTAINER" >/dev/null || {
			rm -rf "$stage"
			return 1
		}
	fi
	check_ports || {
		rm -rf "$stage"
		return 1
	}
	mv "$stage/config.yaml" "${hy2_main_path}/config.yaml" &&
		mv "$stage/docker-compose.yml" "${hy2_main_path}/docker-compose.yml" || {
		rm -rf "$stage"
		return 1
	}
	rmdir "$stage" || true
	started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	dc up -d --force-recreate || return 1
	wait_ready "$started" || return 1
	py export || return 1
	ok 'Hy2 已启动，连接信息和 PNG 二维码已生成。'
	firewall_notice
}
apply_change() {
	if render_and_start; then
		commit_tx
		return 0
	fi
	restore_tx
	return 1
}
firewall_notice() {
	local start end
	start="$(get port_start)"
	end="$(get port_end)"
	printf '\n请确保主机防火墙及云安全组允许 UDP %s–%s（IPv4/IPv6 分别检查）。\n' "$start" "$end"
	printf '如使用 UFW，放行命令为: ufw allow %s:%s/udp\n' "$start" "$end"
	printf '本脚本不额外写 REDIRECT 规则；由 Hysteria 自动创建/清理范围转发。\n'
}

install_manager() {
	if [[ -f "$STATE" ]]; then
		warn '已存在管理配置。重新安装将重置认证、端口、出站和混淆设置，并保留备份。'
		confirm '重新安装？' || return 0
	fi
	ensure_docker && require_owned && begin_tx || return 1
	if ! py init "$default_auth" "$default_salamander" "$CONTAINER"; then
		restore_tx
		return 1
	fi
	if ! choose_address; then
		restore_tx
		return 1
	fi
	# Exactly one auth prompt: timeout, empty input and Enter all use default_auth.
	ask_default '单用户认证密码' "$default_auth" 5 || {
		restore_tx
		return 1
	}
	put password "$REPLY" || {
		restore_tx
		return 1
	}
	# No Salamander prompt at install. Its inactive value is stored in config comments.
	if ! certificate_menu || ! pull_image || ! check_backend; then
		restore_tx
		return 1
	fi
	apply_change && show_connections
}
update_manager() {
	require_install && ensure_docker && begin_tx || return 1
	if ! pull_image || ! check_backend; then
		restore_tx
		return 1
	fi
	apply_change
}
change_ports() {
	require_install || return 1
	local first last
	ask_default '起始 UDP 端口' "$(get port_start)" || return 1
	first="$REPLY"
	ask_default '结束 UDP 端口（与起始相同则关闭跳跃）' "$(get port_end)" || return 1
	last="$REPLY"
	[[ "$first" =~ ^[0-9]{1,5}$ && "$last" =~ ^[0-9]{1,5}$ ]] || {
		err '请输入有效端口数字。'
		return 1
	}
	begin_tx || return 1
	py ports "$((10#$first))" "$((10#$last))" || {
		restore_tx
		return 1
	}
	apply_change
}
change_address() {
	require_install && begin_tx || return 1
	choose_address || {
		restore_tx
		return 1
	}
	local name
	ask_default '客户端 SNI（需与证书匹配；改 IP 不一定需要改 SNI）' "$(get sni)" || {
		restore_tx
		return 1
	}
	name="$(printf '%s' "$REPLY" | py validate-host)" || {
		restore_tx
		return 1
	}
	put sni "$name" || {
		restore_tx
		return 1
	}
	# Avoid silently shipping URI values that do not match the current certificate.
	if python3 - "$name" <<'PY'; then
import ipaddress, sys
try: ipaddress.ip_address(sys.argv[1])
except ValueError: sys.exit(1)
PY
		openssl x509 -in "${hy2_main_path}/certs/fullchain.cer" -noout -checkip "$name" || {
			restore_tx
			return 1
		}
	else
		openssl x509 -in "${hy2_main_path}/certs/fullchain.cer" -noout -checkhost "$name" || {
			restore_tx
			return 1
		}
	fi
	apply_change
}
change_cert() {
	require_install && begin_tx || return 1
	certificate_menu || {
		restore_tx
		return 1
	}
	apply_change
}
auth_menu() {
	require_install || return 1
	local mode name password
	mode="$(get auth_mode)"
	printf '\n当前认证: %s\n' "$mode"
	printf '  1) 切换到单用户/修改单密码\n  2) 启用多用户/添加用户/修改用户密码\n  3) 删除用户\n  4) 列出用户名\n  0) 返回\n'
	ask '选择: ' || return 1
	case "$REPLY" in
	1)
		ask_default '单用户密码' "$default_auth" || return 1
		password="$REPLY"
		begin_tx || return 1
		put password "$password" && put auth_mode password || {
			restore_tx
			return 1
		}
		apply_change
		;;
	2)
		warn '启用 userpass 后，客户端认证须改成 username:password；原单密码 URI 将失效。'
		ask '用户名（英文字母/数字/_.-）: ' || return 1
		name="$REPLY"
		ask '该用户密码: ' || return 1
		password="$REPLY"
		begin_tx || return 1
		printf '%s' "$password" | py user-add "$name" || {
			restore_tx
			return 1
		}
		apply_change
		;;
	3)
		py users
		ask '要删除的用户名（不能删除最后一个启用用户）: ' || return 1
		name="$REPLY"
		begin_tx || return 1
		py user-del "$name" || {
			restore_tx
			return 1
		}
		apply_change
		;;
	4) py users ;;
	0) return 0 ;;
	*) warn '无效选择。' ;;
	esac
}
obfs_menu() {
	require_install || return 1
	printf '\nSalamander 当前: %s\n' "$(get obfs)"
	printf '  1) 开启（使用已保存的密码；初始为 salamander_password）\n  2) 关闭\n  3) 修改保存的 Salamander 密码\n  0) 返回\n'
	local value key
	ask '选择: ' || return 1
	case "$REPLY" in
	1)
		key=obfs
		value=true
		;;
	2)
		key=obfs
		value=false
		;;
	3)
		ask '新的 Salamander 密码: ' || return 1
		key=obfs_password
		value="$REPLY"
		;;
	0) return 0 ;;
	*)
		warn '无效选择。'
		return 1
		;;
	esac
	begin_tx || return 1
	put "$key" "$value" || {
		restore_tx
		return 1
	}
	apply_change
}
outbound_menu() {
	require_install || return 1
	printf '\n出站模式: auto=双栈自动，46=IPv4优先，64=IPv6优先，4=仅IPv4，6=仅IPv6\n'
	ask_default '模式' "$(get outbound)" || return 1
	local value="$REPLY"
	begin_tx || return 1
	put outbound "$value" || {
		restore_tx
		return 1
	}
	apply_change
}
bandwidth_menu() {
	require_install || return 1
	printf '\n当前 ignoreClientBandwidth=%s\n' "$(get ignore_client_bandwidth)"
	printf '  1) 允许客户端选择 Brutal（默认）；客户端留空带宽则使用默认 BBR\n'
	printf '  2) 忽略客户端带宽，使用各端配置的非 Brutal 控制器（服务端默认 BBR）\n  0) 返回\n'
	local value
	ask '选择: ' || return 1
	case "$REPLY" in 1) value=false ;; 2) value=true ;; 0) return 0 ;; *) return 1 ;; esac
	begin_tx || return 1
	put ignore_client_bandwidth "$value" || {
		restore_tx
		return 1
	}
	apply_change
}
show_connections() {
	require_install || return 1
	py export || return 1
	local file
	for file in "${hy2_main_path}"/exports/*.details.txt; do
		printf '\n------------------------------------------------------------\n'
		cat "$file"

		printf '\n复制即用的单端口 URI:\n'
		cat "${file%.details.txt}.uri.txt"

		printf '\n官方格式的端口跳跃 URI（客户端须支持范围 URI）:\n'
		cat "${file%.details.txt}.hopping-uri.txt"

		printf '\n========== 单端口连接二维码 ==========\n'
		qrencode -t ANSIUTF8 <"${file%.details.txt}.uri.txt" ||
			warn '单端口二维码生成失败，请使用 PNG 文件。'

		printf '\n========== 端口跳跃范围连接二维码 ==========\n'
		qrencode -t ANSIUTF8 <"${file%.details.txt}.hopping-uri.txt" ||
			warn '端口跳跃二维码生成失败，请使用 hopping PNG 文件。'

		printf '\nPNG: %s\n跳跃 PNG: %s\n官方客户端配置: %s\n' \
			"${file%.details.txt}.png" \
			"${file%.details.txt}.hopping.png" \
			"${file%.details.txt}.client.yaml"

	done
}
show_status() {
	printf '\n------------------------------------------------------------\n'
	printf '  Hysteria 2 Manager  (%s)\n' "$hy2_main_path"
	printf '%s\n' '------------------------------------------------------------'
	if [[ ! -f "$STATE" ]]; then
		printf '  status: not installed\n  默认: UDP 56000–57999 / 自签20年 / Salamander OFF\n'
	else
		printf '  UDP: %s–%s | auth: %s | Salamander: %s\n' \
			"$(get port_start)" "$(get port_end)" "$(get auth_mode)" "$(get obfs)"
		printf '  地址: %s | SNI: %s | cert: %s | outbound: %s\n' \
			"$(get server)" "$(get sni)" "$(get cert_mode)" "$(get outbound)"
		if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
			docker inspect -f '  container: {{.Name}} | status: {{.State.Status}} | restarts: {{.RestartCount}}' \
				"$CONTAINER" 2>/dev/null || printf '  container: absent\n'
		else
			printf '  Docker: unavailable\n'
		fi
	fi
}
diagnostics() {
	require_install || return 1
	show_status
	docker exec "$CONTAINER" /usr/local/bin/hysteria version 2>/dev/null || true
	openssl x509 -in "${hy2_main_path}/certs/fullchain.cer" -noout -subject -issuer -dates -fingerprint -sha256 || true
	printf '\nUDP sockets:\n'
	ss -H -u -l -n -p || true
	printf '\nContainer firewall tools/backend (read only):\n'
	docker exec "$CONTAINER" /bin/sh -c 'command -v nft; command -v iptables; command -v ip6tables; printf "backend=%s\n" "$HYSTERIA_FIREWALL_BACKEND"' || true
	if command -v ufw >/dev/null; then ufw status; fi
	firewall_notice
	printf '\n注意: 容器启动/监听成功不代表公网 UDP 已打通，最终需从客户端连接验证。\n'
}
restart_manager() {
	require_install && require_owned && begin_tx || return 1
	apply_change
}
stop_manager() {
	require_install && require_owned || return 1
	dc stop -t 30 && ok '已停止；Hysteria 会清理其自动创建的端口范围转发规则。'
}
uninstall_manager() {
	require_install && require_owned || return 1
	confirm '卸载 Hy2 容器？默认保留配置、证书和备份' || return 0
	dc down --timeout 30 || return 1
	# Keep reload hook, even after removing secrets: acme.sh may still refer to it.
	if confirm '同时删除 Hy2 的配置、证书、导出和备份？此步无法撤销'; then
		local f
		for f in manager.json config.yaml docker-compose.yml certs exports backups www acme-list.err; do
			rm -rf "${hy2_main_path:?}/$f" || return 1
		done
		mkdir -p "${hy2_main_path}/certs" "${hy2_main_path}/backups" "${hy2_main_path}/exports" || return 1
		warn '已删除 Hy2 数据。未删除 Docker/镜像，也未改动主机 acme.sh 登记。'
		warn '如果 acme.sh 仍登记这些路径，下一次续期可能重新写入证书文件。'
	fi
	ok 'Hy2 容器已卸载。'
}

main() {
	[[ "${EUID}" -eq 0 ]] || {
		err '请以 root 运行: sudo bash hy2_manager.sh'
		return 1
	}
	[[ "$(uname -s)" == Linux ]] || {
		err '端口范围监听需要 Linux。'
		return 1
	}
	[[ "$hy2_main_path" =~ ^/[A-Za-z0-9_./-]+$ && "$hy2_main_path" != / ]] || {
		err 'hy2_main_path 必须是安全的绝对路径，不包含空格或 shell 特殊字符。'
		return 1
	}
	[[ "$CONTAINER" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || {
		err '无效容器名。'
		return 1
	}
	exec 3<>/dev/tty || {
		err '本脚本需要交互式终端。'
		return 1
	}
	mkdir -p "$hy2_main_path" || return 1
	chmod 700 "$hy2_main_path" || return 1
	ensure_tools || return 1
	exec 9>"${hy2_main_path}/manager.lock" || return 1
	flock -n 9 || {
		err '另一个 hy2_manager 已经运行。'
		return 1
	}
	# Keep a runnable copy alongside all generated files.

	# Keep a runnable copy alongside all generated files.
	local src="${BASH_SOURCE[0]-}"

	if [[ -n "$src" && -f "$src" ]]; then
		src="$(readlink -f -- "$src")" || return 1

		if [[ "$src" != "${hy2_main_path}/hy2_manager.sh" ]]; then
			cp -- "$src" "${hy2_main_path}/hy2_manager.sh" || return 1
		fi
	fi

	if [[ -f "${hy2_main_path}/hy2_manager.sh" ]]; then
		chmod 700 "${hy2_main_path}/hy2_manager.sh" || return 1
	fi

	write_helper || return 1
	trap interrupted INT TERM
	detect_compose || true
	if [[ -f "$STATE" && "$(get container)" != "$CONTAINER" ]]; then
		err 'CONTAINER 与已有 manager.json 不一致，请恢复脚本顶部名称。'
		return 1
	fi
	while :; do
		show_status
		cat <<'MENU'
------------------------------------------------------------
  1) Install / reinstall (默认单密码；输入超时5秒)
  2) Update image + regenerate compose/config
  3) Show connection URI, QR codes & manual settings
  4) Restart / regenerate config
  5) Stop
  6) Start
  7) Logs (follow, Ctrl+C 返回)
  8) Change UDP port range
  9) Authentication / multi-user passwords
 10) Change certificate / choose existing acme.sh domain
 11) Salamander OFF/ON / change obfs password
 12) Change server address / SNI
 13) IPv4 / IPv6 outbound preference
 14) Bandwidth policy (BBR / allow client Brutal)
 15) Status / certificates / network diagnostics
 16) Show generated server config & compose
 17) Uninstall
  0) Exit
------------------------------------------------------------
MENU
		ask 'Choose: ' || break
		case "$REPLY" in
		1) install_manager || err '安装未完成，请查看上述错误。' ;;
		2) ensure_docker && update_manager || err '更新失败。' ;;
		3) show_connections || true ;;
		4 | 6) ensure_docker && restart_manager || err '启动/重启失败。' ;;
		5) ensure_docker && stop_manager || true ;;
		7)
			if require_install && detect_compose; then
				# Ignore SIGINT only while foreground docker logs receives Ctrl+C.
				trap ':' INT
				dc logs --tail 100 -f || true
				trap interrupted INT
			fi
			;;
		8) ensure_docker && change_ports || true ;;
		9) ensure_docker && auth_menu || true ;;
		10) ensure_docker && change_cert || true ;;
		11) ensure_docker && obfs_menu || true ;;
		12) ensure_docker && change_address || true ;;
		13) ensure_docker && outbound_menu || true ;;
		14) ensure_docker && bandwidth_menu || true ;;
		15) diagnostics || true ;;
		16)
			if require_install; then
				printf '\n--- config.yaml ---\n'
				cat "${hy2_main_path}/config.yaml"
				printf '\n--- docker-compose.yml ---\n'
				cat "${hy2_main_path}/docker-compose.yml"
			fi
			;;
		17) ensure_docker && uninstall_manager || true ;;
		0) break ;;
		*)
			warn '无效选择。'
			continue
			;;
		esac
		pause_menu
	done
}

if [[ "${BASH_SOURCE[0]-}" == "$0" || -z "${BASH_SOURCE[0]-}" ]]; then
	main "$@"
fi
