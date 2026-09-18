#!/bin/bash
# ===========================================================================
#  OpenVPN (TCP/81) installer - DUAL STACK edition
#
#  Same Option B deployment as the working UDP/82 stack: the container runs on
#  a dedicated IPv6-enabled docker bridge network. Traffic path for IPv6:
#
#     client  --(tunnel)-->  fd81:81:81::/64   [NAT66 inside the container]
#             -->            the bridge ULA    [NAT66 by the docker daemon]
#             -->            the VPS global IPv6  -->  internet
#
#  This stack is fully independent of the UDP/82 one: different network name,
#  different container, different VPN subnets. Both can run on the same VPS.
#
#  Notable differences from the old script:
#    * creates/validates an IPv6 docker network before compose comes up
#    * enables ip6tables in the docker daemon (needed for NAT66 on the bridge)
#    * sets IPv4+IPv6 forwarding on the host, with accept_ra=2 so an
#      RA-learned IPv6 default route survives turning forwarding on
#    * NO LONGER appends "block-ipv6" to the client configs - it strips any
#      leftover ones instead, because IPv6 now goes through the tunnel
#    * runs a real end-to-end IPv6 egress test from inside the container
# ===========================================================================

NET_NAME="ovpn6_tcp"
COMPOSE_DIR="/root/openvpn-server_z"
CLIENT_DIR="/root/openvpn-clients"
CONTAINER="openvpn_tcp"
IMAGE="oklove/openvpn-server_z"
PORT=81
NUM_CLIENTS=1000

hostname=$(hostname)

# ---------------------------------------------------------------------------
# 0. prerequisites
# ---------------------------------------------------------------------------
apt-get update -qq
apt-get install -y zip curl iproute2 python3

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

# "experimental": true,
if [ ! -f "$DAEMON_JSON" ]; then
	cat >"$DAEMON_JSON" <<'EOF'
{
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
#d["experimental"] = True
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
	echo "NOTE: this briefly restarts every container on this host, including"
	echo "      the UDP/82 OpenVPN stack if it is running here."
	systemctl restart docker
	sleep 6
fi

# ---------------------------------------------------------------------------
# 3. the IPv6-enabled docker network
#    Created with the CLI rather than inside docker-compose.yml, because the
#    legacy python docker-compose ignores enable_ipv6 in v3 compose files.
#    Subnets are auto-selected: any hardcoded pair fails with "Pool overlaps
#    with other one on this address space" as soon as another network - the
#    UDP stack's ovpn6, or the daemon default-address-pool / fixed-cidr-v6 -
#    already covers it.
# ---------------------------------------------------------------------------
echo "============================================"
echo "Preparing IPv6 docker network: ${NET_NAME}"
echo "============================================"

echo "Subnets already allocated to docker networks:"
for n in $(docker network ls --format '{{.Name}}'); do
	SUBS=$(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' "$n" 2>/dev/null)
	[ -n "$SUBS" ] && printf '  %-22s %s\n' "$n" "$SUBS"
done
FIXED_V6=$(grep -Eo '"fixed-cidr-v6"[^,}]*' "$DAEMON_JSON" 2>/dev/null)
[ -n "$FIXED_V6" ] && echo "  daemon.json            ${FIXED_V6}"
POOLS=$(grep -Eo '"default-address-pools".*' "$DAEMON_JSON" 2>/dev/null)
[ -n "$POOLS" ] && echo "  daemon.json            ${POOLS}"

# an existing ovpn6_tcp without IPv6 is useless - drop it
if docker network inspect "$NET_NAME" >/dev/null 2>&1; then
	HAS_V6=$(docker network inspect -f '{{.EnableIPv6}}' "$NET_NAME" 2>/dev/null)
	if [ "$HAS_V6" != "true" ]; then
		echo "Network ${NET_NAME} exists but has no IPv6 - recreating it."
		docker rm -f "$CONTAINER" >/dev/null 2>&1
		docker network rm "$NET_NAME" >/dev/null 2>&1
	fi
fi

if docker network inspect "$NET_NAME" >/dev/null 2>&1; then
	echo "Network ${NET_NAME} is already IPv6-enabled - keeping it."
else
	# a randomly generated ULA as the last-resort candidate
	RAND_HEX=$(head -c 5 /dev/urandom | od -An -tx1 | tr -d ' \n')
	RAND_V6="fd${RAND_HEX:0:2}:${RAND_HEX:2:4}:${RAND_HEX:6:4}::/64"

	# 10.81.0.0/16 is this VPN's IPv4 pool and fd81:81:81::/64 its IPv6 pool,
	# so neither may appear here. The UDP stack's ranges are simply rejected
	# by docker and the loop moves on.
	V4_CANDIDATES=(172.30.81.0/24 172.28.81.0/24 10.181.81.0/24 10.184.81.0/24 192.168.181.0/24)
	V6_CANDIDATES=(fd00:81:81::/64 fdb6:8181:1::/64 fdc7:9a4e:81::/64 "$RAND_V6")

	NET_CREATED=0
	for v4 in "${V4_CANDIDATES[@]}"; do
		for v6 in "${V6_CANDIDATES[@]}"; do
			if docker network create --ipv6 --subnet "$v4" --subnet "$v6" "$NET_NAME" >/dev/null 2>&1; then
				echo "Created network ${NET_NAME} (${v4}, ${v6})."
				NET_CREATED=1
				break 2
			fi
		done
	done

	if [ "$NET_CREATED" != "1" ]; then
		echo "ERROR: every candidate subnet pair overlapped an existing pool."
		echo "       Re-running one attempt to show the raw docker error:"
		docker network create --ipv6 --subnet "${V4_CANDIDATES[0]}" --subnet "${V6_CANDIDATES[0]}" "$NET_NAME"
		echo "       Free a range, or edit V4_CANDIDATES / V6_CANDIDATES above."
		exit 1
	fi
fi

NET_SUBNETS=$(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' "$NET_NAME" 2>/dev/null)
echo "Network ${NET_NAME} subnets: ${NET_SUBNETS}"

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
      - "${PORT}:${PORT}/tcp"
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

RAW_DIR="/tmp/ovpn_raw_tcp"
rm -rf "$RAW_DIR"
mkdir -p "$RAW_DIR"
docker cp "${CONTAINER}:/root/." "${RAW_DIR}/" >/dev/null 2>&1

COPIED=0
for i in $(seq 1 "$NUM_CLIENTS"); do
	SRC="${RAW_DIR}/client_${i}.ovpn"
	if [ -f "$SRC" ]; then
		cp "$SRC" "${CLIENT_DIR}/${hostname}_client_${i}.ovpn"
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
rm -f "${CLIENT_DIR}/${hostname}_vpn_client_${NUM_CLIENTS}_configs.zip"
zip -q "${CLIENT_DIR}/${hostname}_vpn_client_${NUM_CLIENTS}_configs.zip" openvpn-clients/*.ovpn

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
# 10. targeted image cleanup - only old tags of THIS image, so a UDP/82 stack
#     on the same host is left untouched
# ---------------------------------------------------------------------------
echo "============================================"
echo "Cleaning up old images of ${IMAGE}"
echo "============================================"
CURRENT_IMAGE_FULL_ID=$(docker inspect -f '{{.Image}}' "$CONTAINER" 2>/dev/null | cut -d: -f2 | cut -c1-12)
if [ -z "$CURRENT_IMAGE_FULL_ID" ]; then
	CURRENT_IMAGE_FULL_ID=$(docker images "$IMAGE" --format "{{.ID}}" | head -1)
fi
echo "Current image in use: ${CURRENT_IMAGE_FULL_ID}"

ALL_IMAGES=$(docker images "$IMAGE" --format "{{.ID}}" | sort -u)
IMAGE_COUNT=$(echo "$ALL_IMAGES" | grep -c -v '^$')

if [ "$IMAGE_COUNT" -gt 1 ]; then
	echo "Found ${IMAGE_COUNT} images of ${IMAGE}, removing the old ones..."
	for img_id in $ALL_IMAGES; do
		if [ "$img_id" != "$CURRENT_IMAGE_FULL_ID" ]; then
			echo "  removing ${img_id}"
			docker rmi "$img_id" 2>/dev/null || echo "    (in use by a stopped container, skipped)"
		fi
	done
else
	echo "Only one image found, no cleanup needed."
fi

DANGLING=$(docker images -f "dangling=true" -q)
if [ -n "$DANGLING" ]; then
	echo "Removing dangling images..."
	# shellcheck disable=SC2086
	docker rmi $DANGLING 2>/dev/null || echo "  (some dangling images could not be removed)"
fi

# ---------------------------------------------------------------------------
# 11. summary
# ---------------------------------------------------------------------------
echo "============================================"
echo "OpenVPN Server Setup Complete"
echo "============================================"
echo "Server IPv4        : ${THIS_HOST_IP}"
echo "Server IPv6        : ${THIS_HOST_IP6:-none}"
echo "Port               : ${PORT}/tcp"
echo "VPN IPv4 subnet    : 10.81.0.0/16"
echo "VPN IPv6 subnet    : fd81:81:81::/64"
echo "Docker network     : ${NET_NAME} (${NET_SUBNETS})"
echo "IPv6 through VPN   : ${IPV6_STATUS}"
echo "Client configs     : ${CLIENT_DIR}/"
echo "Client configs zip : ${CLIENT_DIR}/${hostname}_vpn_client_${NUM_CLIENTS}_configs.zip"
echo "Files in dir       : $(ls -1 "${CLIENT_DIR}" | wc -l)"
echo "============================================"

if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
	echo "OpenVPN container is running"
	docker ps --filter "name=^${CONTAINER}$"
else
	echo "Warning: OpenVPN container is NOT running"
	echo "Check logs with: docker logs ${CONTAINER}"
fi

echo
echo "Verify from a connected client at https://test-ipv6.com"
echo "Expect 10/10 with BOTH addresses showing ${THIS_HOST_IP} / ${THIS_HOST_IP6:-your VPS IPv6}."
