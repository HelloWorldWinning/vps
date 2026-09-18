#!/bin/bash
# ===========================================================================
#  OpenVPN (UDP/82) installer - DUAL STACK edition
#
#  Option B deployment: the container runs on a dedicated IPv6-enabled docker
#  bridge network. Traffic path for IPv6:
#
#     client  --(tunnel)-->  fd82:82:82::/64   [NAT66 inside the container]
#             -->            fd00:82:82::/64   [NAT66 by the docker daemon]
#             -->            the VPS global IPv6  -->  internet
#
#  Notable differences from the old script:
#    * creates/validates the IPv6 docker network before compose comes up
#    * enables ip6tables in the docker daemon (needed for NAT66 on the bridge)
#    * sets IPv4+IPv6 forwarding on the host, with accept_ra=2 so an
#      RA-learned IPv6 default route survives turning forwarding on
#    * NO LONGER appends "block-ipv6" to the client configs - it strips any
#      leftover ones instead, because IPv6 now goes through the tunnel
#    * runs a real end-to-end IPv6 egress test from inside the container
# ===========================================================================

NET_NAME="ovpn6"
NET_V4="172.30.82.0/24"
NET_V6="fd00:82:82::/64"
COMPOSE_DIR="/root/openvpn-server_z_udp"
CLIENT_DIR="/root/openvpn-clients_udp"
CONTAINER="openvpn_udp"
IMAGE="oklove/openvpn-server_z_udp"
NUM_CLIENTS=1000

hostname=$(hostname)

# ---------------------------------------------------------------------------
# 0. prerequisites
# ---------------------------------------------------------------------------
apt-get update -qq
apt-get install -y zip curl iproute2 python3

# pick whichever compose front-end this box has
if docker compose version >/dev/null 2>&1; then
	DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
	DC="docker-compose"
else
	echo "ERROR: neither 'docker compose' nor 'docker-compose' is installed. Aborting."
	exit 1
fi
echo "Using compose command: ${DC}"

# ---------------------------------------------------------------------------
# 1. host networking - forwarding + keep the RA-learned IPv6 default route
# ---------------------------------------------------------------------------
echo "============================================"
echo "Configuring host sysctls"
echo "============================================"
cat >/etc/sysctl.d/99-openvpn-dualstack.conf <<'EOF'
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1
# accept_ra=2 keeps an RA-learned IPv6 default route alive while forwarding is
# enabled. Without it the kernel ignores RAs and the host can lose IPv6.
net.ipv6.conf.all.accept_ra=2
net.ipv6.conf.default.accept_ra=2
EOF
sysctl --system >/dev/null 2>&1
echo "  net.ipv4.ip_forward           = $(sysctl -n net.ipv4.ip_forward)"
echo "  net.ipv6.conf.all.forwarding  = $(sysctl -n net.ipv6.conf.all.forwarding)"

# ---------------------------------------------------------------------------
# 2. docker daemon - ip6tables is what performs NAT66 on the bridge
# ---------------------------------------------------------------------------
echo "============================================"
echo "Checking docker daemon IPv6 support"
echo "============================================"
DAEMON_JSON="/etc/docker/daemon.json"
NEED_DOCKER_RESTART=0
mkdir -p /etc/docker

if [ ! -f "$DAEMON_JSON" ]; then
	cat >"$DAEMON_JSON" <<'EOF'
{
  "experimental": true,
  "ip6tables": true
}
EOF
	NEED_DOCKER_RESTART=1
	echo "Created ${DAEMON_JSON} with ip6tables enabled."
elif ! grep -Eq '"ip6tables"[[:space:]]*:[[:space:]]*true' "$DAEMON_JSON"; then
	cp "$DAEMON_JSON" "${DAEMON_JSON}.bak.$(date +%s)"
	python3 - "$DAEMON_JSON" <<'PY'
import json, sys
p = sys.argv[1]
try:
    with open(p) as fh:
        d = json.load(fh)
    if not isinstance(d, dict):
        d = {}
except Exception:
    d = {}
d["experimental"] = True
d["ip6tables"] = True
with open(p, "w") as fh:
    json.dump(d, fh, indent=2)
    fh.write("\n")
PY
	if [ $? -eq 0 ]; then
		NEED_DOCKER_RESTART=1
		echo "Patched ${DAEMON_JSON} (backup kept alongside it)."
	else
		echo "WARNING: could not patch ${DAEMON_JSON}. Add \"ip6tables\": true by hand."
	fi
else
	echo "ip6tables already enabled in ${DAEMON_JSON}."
fi

if [ "$NEED_DOCKER_RESTART" = "1" ]; then
	echo "Restarting docker to apply the daemon configuration..."
	systemctl restart docker
	sleep 6
fi

# ---------------------------------------------------------------------------
# 3. the IPv6-enabled docker network
#    Created with the CLI rather than inside docker-compose.yml, because the
#    legacy python docker-compose ignores enable_ipv6 in v3 compose files.
# ---------------------------------------------------------------------------
echo "============================================"
echo "Preparing IPv6 docker network: ${NET_NAME}"
echo "============================================"
if docker network inspect "$NET_NAME" >/dev/null 2>&1; then
	HAS_V6=$(docker network inspect -f '{{.EnableIPv6}}' "$NET_NAME" 2>/dev/null)
	if [ "$HAS_V6" != "true" ]; then
		echo "Network ${NET_NAME} exists but has no IPv6 - recreating it."
		docker rm -f "$CONTAINER" >/dev/null 2>&1
		docker network rm "$NET_NAME" >/dev/null 2>&1
	else
		echo "Network ${NET_NAME} already IPv6-enabled."
	fi
fi

if ! docker network inspect "$NET_NAME" >/dev/null 2>&1; then
	docker network create --ipv6 \
		--subnet "$NET_V4" \
		--subnet "$NET_V6" \
		"$NET_NAME" >/dev/null
	if [ $? -eq 0 ]; then
		echo "Created network ${NET_NAME} (${NET_V4}, ${NET_V6})."
	else
		echo "ERROR: failed to create the IPv6 docker network. Aborting."
		exit 1
	fi
fi

# ---------------------------------------------------------------------------
# 4. compose file
# ---------------------------------------------------------------------------
mkdir -p "$COMPOSE_DIR"
cat <<EOF >"${COMPOSE_DIR}/docker-compose.yml"
services:
  openvpn:
    image: ${IMAGE}
    container_name: ${CONTAINER}
    privileged: true
    devices:
      - "/dev/net/tun:/dev/net/tun"
    ports:
      - "82:82/udp"
    restart: always
    networks:
      - ${NET_NAME}

networks:
  ${NET_NAME}:
    external: true
EOF

# ---------------------------------------------------------------------------
# 5. start
# ---------------------------------------------------------------------------
cd "$COMPOSE_DIR" || exit 1
$DC pull
$DC down
$DC up -d

echo "Waiting for the OpenVPN container to initialize..."
sleep 12

# ---------------------------------------------------------------------------
# 6. public addresses of this host
# ---------------------------------------------------------------------------
THIS_HOST_IP=""
for service in ifconfig.me icanhazip.com checkip.amazonaws.com; do
	CANDIDATE=$(curl -4 -s --max-time 4 "$service" | tr -d '\r\n')
	if [[ $CANDIDATE =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		THIS_HOST_IP="$CANDIDATE"
		echo "Public IPv4 found: ${THIS_HOST_IP}"
		break
	fi
done
if [ -z "$THIS_HOST_IP" ]; then
	echo "ERROR: could not determine the public IPv4 address. Aborting before rewriting client configs."
	exit 1
fi

THIS_HOST_IP6=""
for service in https://ipv6.icanhazip.com https://api6.ipify.org https://v6.ident.me; do
	CANDIDATE=$(curl -6 -s --max-time 5 "$service" | tr -d '\r\n')
	if [[ $CANDIDATE == *:* ]]; then
		THIS_HOST_IP6="$CANDIDATE"
		echo "Public IPv6 found: ${THIS_HOST_IP6}"
		break
	fi
done
if [ -z "$THIS_HOST_IP6" ]; then
	echo "WARNING: this VPS has no working public IPv6."
	echo "         Clients will still be leak-free (IPv6 is routed into the tunnel"
	echo "         and dropped at the server), but IPv6 sites stay unreachable."
	echo "         On Alibaba Cloud, enable IPv6 on the VPC, the vSwitch and the ENI,"
	echo "         then assign IPv6 gateway bandwidth."
fi

# ---------------------------------------------------------------------------
# 7. extract client configs (one docker cp instead of 1000)
# ---------------------------------------------------------------------------
echo "============================================"
echo "Extracting client configurations"
echo "============================================"
mkdir -p "$CLIENT_DIR"
rm -f "${CLIENT_DIR}"/*.ovpn "${CLIENT_DIR}"/*.zip 2>/dev/null

RAW_DIR="/tmp/ovpn_raw_udp"
rm -rf "$RAW_DIR"
mkdir -p "$RAW_DIR"
docker cp "${CONTAINER}:/root/." "${RAW_DIR}/" >/dev/null 2>&1

COPIED=0
for i in $(seq 1 "$NUM_CLIENTS"); do
	SRC="${RAW_DIR}/client_udp_${i}.ovpn"
	if [ -f "$SRC" ]; then
		cp "$SRC" "${CLIENT_DIR}/${hostname}_client_udp_${i}.ovpn"
		COPIED=$((COPIED + 1))
	fi
done
rm -rf "$RAW_DIR"
echo "Copied ${COPIED} client configurations."

if [ "$COPIED" -eq 0 ]; then
	echo "ERROR: no client configs were extracted. Check: docker logs ${CONTAINER}"
	exit 1
fi

# ---------------------------------------------------------------------------
# 8. rewrite the remote address, and make sure block-ipv6 is GONE
# ---------------------------------------------------------------------------
sed -i "s/8\.210\.139\.66/${THIS_HOST_IP}/g" "${CLIENT_DIR}"/*.ovpn

# The old script appended "block-ipv6" here to hide the leak. That line must
# not exist any more: IPv6 is carried inside the tunnel now, and block-ipv6
# would kill it again.
sed -i '/^[[:space:]]*block-ipv6[[:space:]]*$/d' "${CLIENT_DIR}"/*.ovpn

LEFTOVER=$(grep -l '^[[:space:]]*block-ipv6' "${CLIENT_DIR}"/*.ovpn 2>/dev/null | wc -l)
echo "Configs still containing block-ipv6: ${LEFTOVER} (must be 0)"

cd /root/ || exit 1
rm -f "${CLIENT_DIR}/${hostname}_vpn_client_udp_${NUM_CLIENTS}_configs.zip"
zip -q "${CLIENT_DIR}/${hostname}_vpn_client_udp_${NUM_CLIENTS}_configs.zip" openvpn-clients_udp/*.ovpn

# ---------------------------------------------------------------------------
# 9. verification - this is the part that tells you IPv6 really works
# ---------------------------------------------------------------------------
echo "============================================"
echo "IPv6 verification"
echo "============================================"

echo "--- container addresses ---"
docker exec "$CONTAINER" ip -6 addr show scope global 2>/dev/null | grep inet6 || echo "  (none)"

echo "--- NAT66 rule inside the container ---"
docker exec "$CONTAINER" ip6tables -t nat -S POSTROUTING 2>/dev/null | grep MASQUERADE || echo "  MISSING - check 'docker logs ${CONTAINER}' for up.sh warnings"

echo "--- end-to-end IPv6 egress test from inside the container ---"
CONTAINER_IP6=""
for service in https://ipv6.icanhazip.com https://api6.ipify.org https://v6.ident.me; do
	CANDIDATE=$(docker exec "$CONTAINER" curl -6 -s --max-time 8 "$service" 2>/dev/null | tr -d '\r\n')
	if [[ $CANDIDATE == *:* ]]; then
		CONTAINER_IP6="$CANDIDATE"
		break
	fi
done

if [ -n "$CONTAINER_IP6" ]; then
	echo "  PASS - the container reaches the IPv6 internet as ${CONTAINER_IP6}"
	IPV6_STATUS="working"
else
	echo "  FAIL - the container cannot reach the IPv6 internet."
	echo "         Clients stay leak-free, but they get no IPv6."
	echo "         Check, in order:"
	echo "           1) does the VPS itself have IPv6?   curl -6 https://ifconfig.co"
	echo "           2) is ip6tables on in the daemon?   cat /etc/docker/daemon.json"
	echo "           3) host forwarding?                 sysctl net.ipv6.conf.all.forwarding"
	echo "           4) docker version (27+ preferred):  docker version --format '{{.Server.Version}}'"
	IPV6_STATUS="NOT working"
fi

# ---------------------------------------------------------------------------
# 10. cleanup + summary
# ---------------------------------------------------------------------------
docker image prune -a -f >/dev/null 2>&1
docker builder prune -a -f >/dev/null 2>&1

echo "============================================"
echo "OpenVPN Server Setup Complete"
echo "============================================"
echo "Server IPv4        : ${THIS_HOST_IP}"
echo "Server IPv6        : ${THIS_HOST_IP6:-none}"
echo "Port               : 82/udp"
echo "Docker network     : ${NET_NAME} (${NET_V4}, ${NET_V6})"
echo "IPv6 through VPN   : ${IPV6_STATUS}"
echo "Client configs     : ${CLIENT_DIR}/"
echo "Client configs zip : ${CLIENT_DIR}/${hostname}_vpn_client_udp_${NUM_CLIENTS}_configs.zip"
echo "Files in dir       : $(ls -1 "${CLIENT_DIR}" | wc -l)"
echo "============================================"

if docker ps | grep -q "$CONTAINER"; then
	echo "OpenVPN container is running"
	docker ps | grep "$CONTAINER"
else
	echo "Warning: OpenVPN container is NOT running"
	echo "Check logs with: docker logs ${CONTAINER}"
fi

echo
echo "Verify from a connected client at https://test-ipv6.com"
echo "Expect 10/10 with BOTH addresses showing ${THIS_HOST_IP} / ${THIS_HOST_IP6:-your VPS IPv6}."
