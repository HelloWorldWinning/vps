#!/usr/bin/env bash
# hy2.sh — bootstrap Hysteria2 using a fixed working directory: /root/hysteria2
set -Eeuo pipefail

# -------- settings --------
WORKDIR="/root/hysteria2"

# -------- helpers --------
err() { echo -e "\e[31m[ERR]\e[0m $*" >&2; }
ok() { echo -e "\e[32m[OK]\e[0m  $*"; }
inf() { echo -e "\e[34m[INFO]\e[0m $*"; }
warn() { echo -e "\e[33m[WARN]\e[0m $*"; }

# -------- ensure workdir --------
mkdir -p "$WORKDIR"
cd "$WORKDIR"
inf "Using working dir: $WORKDIR"

# -------- docker / compose checks --------
if ! command -v docker >/dev/null 2>&1; then
	err "Docker is not installed or not in PATH."
	exit 1
fi
if docker compose version >/dev/null 2>&1; then
	COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
	COMPOSE="docker-compose"
else
	err "Neither 'docker compose' nor 'docker-compose' found."
	exit 1
fi

# -------- inputs --------
echo
read -rp "Enter ACME domain(s) for your cert (comma or space separated, REQUIRED): " DOMAINS_INPUT
DOMAINS_INPUT="${DOMAINS_INPUT:-}"
if [[ -z "$DOMAINS_INPUT" ]]; then
	err "At least one domain is required (e.g., nl.eu.org)."
	exit 1
fi

read -rp "Enter listen port (default 4443): " PORT_INPUT
PORT="${PORT_INPUT:-4443}"

# basic port validation
if ! [[ "$PORT" =~ ^[0-9]{1,5}$ ]] || ((PORT < 1 || PORT > 65535)); then
	err "Invalid port: $PORT"
	exit 1
fi

# Normalize domains: allow commas or spaces
DOMAINS_INPUT="${DOMAINS_INPUT// /,}" # convert spaces to commas
IFS=',' read -ra _DOMS <<<"$DOMAINS_INPUT"

DOMAINS_YAML=""
for d in "${_DOMS[@]}"; do
	d="$(echo "$d" | xargs)" # trim
	[[ -z "$d" ]] && continue
	DOMAINS_YAML+="    - \"$d\"\n"
done

if [[ -z "$DOMAINS_YAML" ]]; then
	err "No valid domain parsed from input."
	exit 1
fi

# -------- show plan --------
echo
inf "Configuration summary:"
echo "  Domains: $(echo "$DOMAINS_INPUT" | tr ',' ' ')"
echo "  Listen : :$PORT"
echo "  Files  : $WORKDIR/hysteria.yaml and docker-compose.yml"
echo

# Backup existing hysteria.yaml if present
if [[ -f hysteria.yaml ]]; then
	BK="hysteria.yaml.bak.$(date +%Y%m%d-%H%M%S)"
	cp -f hysteria.yaml "$BK"
	warn "Existing hysteria.yaml backed up to $BK"
fi

# -------- write hysteria.yaml (preserve comments) --------
cat >hysteria.yaml <<EOF
logLevel: error   # 只显示真正的错误日志
listen: :$PORT

acme:
  domains:
EOF

# append dynamic domain list
printf "%b" "$DOMAINS_YAML" >>hysteria.yaml

# append the remainder (comments intact)
cat >>hysteria.yaml <<'EOF'
  email: abcd@gmail.com
  # 自动申请/续期证书

auth:
  type: password
  password: a

#masquerade:
#  type: proxy
#  proxy:
#    url: https://www.cloudflare.com/
#    rewriteHost: true

## QUIC 性能优化
#quic:
#  initStreamReceiveWindow: 26843545   # 初始流接收窗口
#  initConnReceiveWindow: 67108864     # 初始连接接收窗口
#  maxIdleTimeout: 60s                 # 空闲超时
#  maxIncomingStreams: 1024
#  maxIncomingUniStreams: 1024
#
#udpIdleTimeout: 60s                   # UDP 空闲超时
#disableMTUDiscovery: true             # 关闭 MTU 探测
#maxMTU: 1350                           # 固定 MTU 避免分片丢包
#
EOF

ok "Wrote $WORKDIR/hysteria.yaml"

# -------- preflight checks --------
if command -v ss >/dev/null 2>&1; then
	if ss -lnt | awk '{print $4}' | grep -qE "[:.]${PORT}$"; then
		warn "Port $PORT appears to be in use on the host. With host networking, this may conflict."
	fi
fi

# Ensure docker-compose.yml exists; if not, create it using your template
if [[ ! -f docker-compose.yml ]]; then
	warn "docker-compose.yml not found. Creating a default one based on your template."
	cat >docker-compose.yml <<'YML'
services:
  hysteria:
    image: tobyxdd/hysteria
    container_name: hysteria
    restart: always
    network_mode: "host"
    volumes:
      - ./acme:/acme
      - ./hysteria.yaml:/etc/hysteria.yaml
    command: ["server", "-c", "/etc/hysteria.yaml"]
#volumes:
#  acme:
YML
	ok "Wrote $WORKDIR/docker-compose.yml"
fi

# -------- launch --------
echo
inf "Starting (or reloading) the Hysteria server container..."
$COMPOSE down
$COMPOSE pull
$COMPOSE up -d
ok "Compose is up."
docker image prune -f

# -------- status & logs (echoing running info) --------
echo
inf "Compose status:"
$COMPOSE ps

echo
RUNSTATE="$(docker inspect -f '{{.State.Status}}' hysteria 2>/dev/null || echo 'unknown')"
inf "Container 'hysteria' state: $RUNSTATE"

echo
inf "Recent logs from container 'hysteria' (last 80 lines):"
if docker ps --format '{{.Names}}' | grep -qx 'hysteria'; then
	docker logs --tail 80 hysteria || true
else
	warn "Container 'hysteria' not running yet — check compose status above."
fi

echo
ok "All done. To follow live logs: docker logs -f hysteria"
