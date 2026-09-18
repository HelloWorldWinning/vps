FROM debian:trixie-slim

# ===========================================================================
#  OpenVPN server - DUAL STACK (IPv4 + IPv6 carried inside the tunnel)
#  proto udp / port 82
#
#    IPv4 tunnel : 10.82.0.0/16     -> NAT44 (MASQUERADE) out of the uplink
#    IPv6 tunnel : fd82:82:82::/64  -> NAT66 (MASQUERADE) out of the uplink
#
#  Both default routes are pushed to the client, so the client can no longer
#  reach the internet over its own native IPv6.  That removes the IPv6 leak
#  WITHOUT needing "block-ipv6" in the .ovpn file, and IPv6 keeps working.
#
#  Failure mode is safe: if this container has no IPv6 uplink, client IPv6
#  traffic enters the tunnel and is dropped here - it never leaks out of the
#  client. Applications then fall back to IPv4 (Happy Eyeballs).
# ===========================================================================

# ---------------------------------------------------------------------------
# 1. OpenVPN from the upstream repo
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y wget gnupg ca-certificates && \
    wget -qO - https://swupdate.openvpn.net/repos/repo-public.gpg | gpg --dearmor > /usr/share/keyrings/openvpn-repo-public.gpg && \
    echo 'deb [signed-by=/usr/share/keyrings/openvpn-repo-public.gpg] http://build.openvpn.net/debian/openvpn/stable bookworm main' > /etc/apt/sources.list.d/openvpn-aptrepo.list && \
    apt-get update && \
    apt-get install -y openvpn

# iproute2 is required: the new up.sh detects the uplink interface with "ip"
RUN apt-get update && apt-get install -y \
    iptables \
    iproute2 \
    openssl \
    wget \
    ca-certificates \
    curl \
    net-tools \
    gnupg \
    procps \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# 2. easy-rsa + PKI  (unchanged)
# ---------------------------------------------------------------------------
RUN EASYRSA_LATEST=$(curl -s4 https://api.github.com/repos/OpenVPN/easy-rsa/releases/latest | grep "tag_name" | cut -d\" -f4) && \
    wget -O /tmp/easy-rsa.tgz https://github.com/OpenVPN/easy-rsa/releases/download/${EASYRSA_LATEST}/EasyRSA-${EASYRSA_LATEST#v}.tgz \
    && mkdir -p /etc/openvpn/easy-rsa \
    && tar xzf /tmp/easy-rsa.tgz --strip-components=1 --no-same-owner --directory /etc/openvpn/easy-rsa \
    && rm -f /tmp/easy-rsa.tgz

WORKDIR /etc/openvpn/easy-rsa

RUN echo "set_var EASYRSA_ALGO ec\n\
set_var EASYRSA_CURVE prime256v1\n\
set_var EASYRSA_CA_EXPIRE 3650\n\
set_var EASYRSA_CERT_EXPIRE 3650\n\
set_var EASYRSA_CRL_DAYS 3650" > vars

RUN ./easyrsa init-pki && \
    ./easyrsa --batch build-ca nopass && \
    ./easyrsa --batch build-server-full server nopass && \
    ./easyrsa gen-crl && \
    for i in $(seq 1 1000); do \
        ./easyrsa --batch build-client-full "client_udp_${i}" nopass; \
    done

RUN mkdir -p /var/log/openvpn /etc/sysctl.d /etc/openvpn/config

RUN openssl dhparam -out /etc/openvpn/config/dh2048.pem 2048

RUN cp pki/ca.crt pki/private/ca.key pki/issued/server.crt pki/private/server.key pki/crl.pem /etc/openvpn/config/ && \
    chmod 644 /etc/openvpn/config/crl.pem

RUN openvpn --genkey secret /etc/openvpn/config/tls-crypt.key

# ---------------------------------------------------------------------------
# 3. Server configuration - IPv4 + IPv6
# ---------------------------------------------------------------------------
RUN echo "port 82\n\
# proto udp6 = a dual-stack [::]:82 socket. It serves native IPv6 clients AND\n\
# IPv4 clients (as v4-mapped addresses), because --bind ipv6only is not set.\n\
# Plain \"proto udp\" binds 0.0.0.0 only, which is unreachable for IPv6 clients\n\
# once the docker daemon has ip6tables enabled and DNATs inbound v6 to the\n\
# container address.\n\
proto udp6\n\
dev tun\n\
user nobody\n\
group nogroup\n\
persist-key\n\
persist-tun\n\
keepalive 10 120\n\
topology subnet\n\
\n\
# ---------- IPv4 tunnel ----------\n\
server 10.82.0.0 255.255.0.0\n\
\n\
# ---------- IPv6 tunnel ----------\n\
# ULA prefix, masqueraded (NAT66) behind the single global IPv6 of the VPS.\n\
# A ULA is used because cloud providers hand out a /128, not a routed /64.\n\
server-ipv6 fd82:82:82::/64\n\
\n\
ifconfig-pool-persist ipp.txt\n\
\n\
# ---------- push BOTH default routes: this is what kills the IPv6 leak ----------\n\
push \"redirect-gateway def1 bypass-dhcp ipv6\"\n\
push \"route-ipv6 2000::/3\"\n\
\n\
# ---------- DNS (v4 + v6 resolvers) ----------\n\
push \"dhcp-option DNS 1.1.1.1\"\n\
push \"dhcp-option DNS 8.8.8.8\"\n\
push \"dhcp-option DNS 9.9.9.9\"\n\
push \"dhcp-option DNS 1.0.0.1\"\n\
push \"dhcp-option DNS 8.8.4.4\"\n\
push \"dhcp-option DNS6 2606:4700:4700::1111\"\n\
push \"dhcp-option DNS6 2001:4860:4860::8888\"\n\
push \"dhcp-option DNS6 2620:fe::fe\"\n\
\n\
dh /etc/openvpn/config/dh2048.pem\n\
tls-crypt /etc/openvpn/config/tls-crypt.key\n\
crl-verify /etc/openvpn/config/crl.pem\n\
ca /etc/openvpn/config/ca.crt\n\
cert /etc/openvpn/config/server.crt\n\
key /etc/openvpn/config/server.key\n\
auth SHA256\n\
cipher AES-128-GCM\n\
data-ciphers AES-128-GCM\n\
data-ciphers-fallback AES-128-GCM\n\
tls-server\n\
tls-version-min 1.2\n\
tls-cipher TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256\n\
status /var/log/openvpn/status.log\n\
verb 3" > /etc/openvpn/server.conf

# ---------------------------------------------------------------------------
# 4. Client configurations
#    NOTE: no block-ipv6 here - IPv6 now goes through the tunnel.
# ---------------------------------------------------------------------------
RUN mkdir -p /root/client-configs && \
    for i in $(seq 1 1000); do \
        echo "client\n\
proto udp\n\
remote 8.210.139.66 82\n\
dev tun\n\
resolv-retry infinite\n\
nobind\n\
persist-key\n\
persist-tun\n\
remote-cert-tls server\n\
verify-x509-name server name\n\
auth SHA256\n\
auth-nocache\n\
cipher AES-128-GCM\n\
data-ciphers AES-128-GCM\n\
data-ciphers-fallback AES-128-GCM\n\
tls-client\n\
tls-version-min 1.2\n\
tls-cipher TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256\n\
ignore-unknown-option block-outside-dns\n\
setenv opt block-outside-dns\n\
# IPv6 is carried inside the tunnel - do NOT add block-ipv6 to this file.\n\
# Requires an OpenVPN 2.5+ client.\n\
verb 3\n\
<ca>\n\
$(cat /etc/openvpn/config/ca.crt)\n\
</ca>\n\
<cert>\n\
$(awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' /etc/openvpn/easy-rsa/pki/issued/client_udp_${i}.crt)\n\
</cert>\n\
<key>\n\
$(cat /etc/openvpn/easy-rsa/pki/private/client_udp_${i}.key)\n\
</key>\n\
<tls-crypt>\n\
$(cat /etc/openvpn/config/tls-crypt.key)\n\
</tls-crypt>" > /root/client_udp_${i}.ovpn; \
    done

# ---------------------------------------------------------------------------
# 5. Firewall / NAT - IPv4 and IPv6, uplink interface auto-detected
# ---------------------------------------------------------------------------
RUN echo '#!/bin/sh\n\
V4NET=10.82.0.0/16\n\
V6NET=fd82:82:82::/64\n\
PORT=82\n\
\n\
# Find the interface holding the default route (eth0 under a docker bridge,\n\
# but something else under --network host, e.g. ens5 on Alibaba Cloud).\n\
detect_if() {\n\
    _prev=\n\
    _dev=\n\
    for _tok in $(ip -$1 route show default 2>/dev/null | head -n 1); do\n\
        if [ "$_prev" = "dev" ]; then _dev=$_tok; break; fi\n\
        _prev=$_tok\n\
    done\n\
    echo $_dev\n\
}\n\
\n\
WAN4=$(detect_if 4)\n\
[ -n "$WAN4" ] || WAN4=eth0\n\
WAN6=$(detect_if 6)\n\
[ -n "$WAN6" ] || WAN6=$WAN4\n\
\n\
echo "[up.sh] IPv4 uplink: $WAN4"\n\
echo "[up.sh] IPv6 uplink: $WAN6"\n\
\n\
# ---------------- IPv4 ----------------\n\
iptables -t nat -A POSTROUTING -s $V4NET -o $WAN4 -j MASQUERADE\n\
iptables -A INPUT -i tun0 -j ACCEPT\n\
iptables -A INPUT -i $WAN4 -p udp --dport $PORT -j ACCEPT\n\
iptables -A FORWARD -i $WAN4 -o tun0 -j ACCEPT\n\
iptables -A FORWARD -i tun0 -o $WAN4 -j ACCEPT\n\
\n\
# ---------------- IPv6 ----------------\n\
if ip6tables -n -L INPUT >/dev/null 2>&1; then\n\
    ip6tables -t nat -A POSTROUTING -s $V6NET -o $WAN6 -j MASQUERADE || echo "[up.sh] WARNING: NAT66 rule rejected - the host kernel is missing ip6table_nat"\n\
    ip6tables -A INPUT -i tun0 -j ACCEPT\n\
    ip6tables -A INPUT -i $WAN6 -p udp --dport $PORT -j ACCEPT\n\
    ip6tables -A FORWARD -i $WAN6 -o tun0 -j ACCEPT\n\
    ip6tables -A FORWARD -i tun0 -o $WAN6 -j ACCEPT\n\
else\n\
    echo "[up.sh] WARNING: ip6tables is unusable here - IPv6 will not be routed"\n\
fi' > /etc/openvpn/up.sh && \
    chmod +x /etc/openvpn/up.sh

# ---------------------------------------------------------------------------
# 6. Entrypoint - sysctls, firewall, IPv6 readiness report, then openvpn
# ---------------------------------------------------------------------------
RUN echo '#!/bin/sh\n\
mkdir -p /dev/net\n\
if [ ! -c /dev/net/tun ]; then\n\
    mknod /dev/net/tun c 10 200\n\
fi\n\
\n\
set_sysctl() {\n\
    if [ -w "$1" ]; then echo "$2" > "$1"; fi\n\
}\n\
\n\
set_sysctl /proc/sys/net/ipv4/ip_forward 1\n\
set_sysctl /proc/sys/net/ipv6/conf/all/disable_ipv6 0\n\
set_sysctl /proc/sys/net/ipv6/conf/default/disable_ipv6 0\n\
\n\
# accept_ra=2 keeps an RA-learned IPv6 default route alive once forwarding is\n\
# switched on - without it the kernel drops RAs and the uplink loses IPv6.\n\
for f in /proc/sys/net/ipv6/conf/*/accept_ra; do set_sysctl "$f" 2; done\n\
\n\
set_sysctl /proc/sys/net/ipv6/conf/all/forwarding 1\n\
set_sysctl /proc/sys/net/ipv6/conf/default/forwarding 1\n\
\n\
# bindv6only=0 is what makes the [::]:82 socket also accept IPv4 clients.\n\
set_sysctl /proc/sys/net/ipv6/bindv6only 0\n\
\n\
# The server binds a dual-stack socket (proto udp6). If this container somehow\n\
# has no IPv6 stack at all that bind fails and openvpn refuses to start, so\n\
# fall back to IPv4-only instead of dying.\n\
if [ ! -f /proc/sys/net/ipv6/conf/all/disable_ipv6 ] || [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)" = "1" ]; then\n\
    echo "[start] no usable IPv6 stack here - falling back to proto udp (IPv4 only)"\n\
    sed -i "s@^proto udp6@proto udp@" /etc/openvpn/server.conf\n\
fi\n\
\n\
if [ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" != "1" ]; then\n\
    echo "[start] WARNING: IPv4 forwarding is OFF. Run the container with --privileged or --sysctl net.ipv4.ip_forward=1"\n\
fi\n\
if [ "$(cat /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null)" != "1" ]; then\n\
    echo "[start] WARNING: IPv6 forwarding is OFF. Run the container with --privileged or --sysctl net.ipv6.conf.all.forwarding=1"\n\
fi\n\
\n\
/etc/openvpn/up.sh\n\
\n\
echo "[start] ---- IPv6 readiness ----"\n\
ip -6 addr show scope global 2>/dev/null | grep inet6 || echo "[start] no global IPv6 address on this container"\n\
if ip -6 route show default 2>/dev/null | grep -q default; then\n\
    echo "[start] IPv6 default route present - clients get working IPv6 through the tunnel"\n\
else\n\
    echo "[start] WARNING: no IPv6 default route inside this container."\n\
    echo "[start]          Clients still receive an IPv6 default route into the tunnel, so"\n\
    echo "[start]          nothing leaks, but IPv6 destinations stay unreachable."\n\
    echo "[start]          Fix: run with --network host, or attach the container to an"\n\
    echo "[start]          IPv6-enabled docker network."\n\
fi\n\
echo "[start] ------------------------"\n\
\n\
exec openvpn --config /etc/openvpn/server.conf' > /etc/openvpn/start.sh && \
    chmod +x /etc/openvpn/start.sh

EXPOSE 82/udp
CMD ["/etc/openvpn/start.sh"]
