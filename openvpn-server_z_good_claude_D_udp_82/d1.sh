FROM debian:bookworm-slim

# Install OpenVPN and dependencies
RUN apt-get update && apt-get install -y wget gnupg ca-certificates && \
    wget -qO - https://swupdate.openvpn.net/repos/repo-public.gpg | gpg --dearmor > /usr/share/keyrings/openvpn-repo-public.gpg && \
    echo 'deb [signed-by=/usr/share/keyrings/openvpn-repo-public.gpg] http://build.openvpn.net/debian/openvpn/stable bookworm main' > /etc/apt/sources.list.d/openvpn-aptrepo.list && \
    apt-get update && \
    apt-get install -y \
    openvpn \
    iptables \
    openssl \
    wget \
    ca-certificates \
    curl \
    net-tools \
    gnupg \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Install easy-rsa (latest version)
RUN EASYRSA_LATEST=$(curl -s https://api.github.com/repos/OpenVPN/easy-rsa/releases/latest | grep "tag_name" | cut -d\" -f4) && \
    wget -O /tmp/easy-rsa.tgz https://github.com/OpenVPN/easy-rsa/releases/download/${EASYRSA_LATEST}/EasyRSA-${EASYRSA_LATEST#v}.tgz && \
    mkdir -p /etc/openvpn/easy-rsa && \
    tar xzf /tmp/easy-rsa.tgz --strip-components=1 --no-same-owner --directory /etc/openvpn/easy-rsa && \
    rm -f /tmp/easy-rsa.tgz

# Setup OpenVPN configuration
WORKDIR /etc/openvpn/easy-rsa

# Create vars file with stronger security settings
RUN echo "set_var EASYRSA_ALGO ec\n\
set_var EASYRSA_CURVE prime256v1\n\
set_var EASYRSA_CA_EXPIRE 7300\n\
set_var EASYRSA_CERT_EXPIRE 3650\n\
set_var EASYRSA_CRL_DAYS 3650\n\
set_var EASYRSA_KEY_SIZE 256" > vars

# Initialize PKI and create certificates
RUN ./easyrsa init-pki && \
    ./easyrsa --batch build-ca nopass && \
    ./easyrsa --batch build-server-full server nopass && \
    ./easyrsa gen-crl

# Generate client certificates (configurable number)
ARG NUM_CLIENTS=100
RUN for i in $(seq 1 ${NUM_CLIENTS}); do \
        ./easyrsa --batch build-client-full "client_udp_${i}" nopass; \
    done

# Create necessary directories
RUN mkdir -p /var/log/openvpn /etc/sysctl.d /etc/openvpn/config /root/client-configs

# Generate stronger DH parameters (or use EC for better performance)
RUN openssl dhparam -out /etc/openvpn/config/dh2048.pem 2048

# Copy necessary certificate files
RUN cp pki/ca.crt pki/private/ca.key pki/issued/server.crt pki/private/server.key pki/crl.pem /etc/openvpn/config/ && \
    chmod 644 /etc/openvpn/config/crl.pem && \
    chmod 600 /etc/openvpn/config/ca.key /etc/openvpn/config/server.key

# Generate tls-crypt key for additional security
RUN openvpn --genkey secret /etc/openvpn/config/tls-crypt.key

# Create server configuration with environment variables support
ARG VPN_PORT=82
ARG VPN_PROTOCOL=udp
ARG VPN_NETWORK=10.1.0.0
ARG VPN_NETMASK=255.255.0.0
ARG SERVER_IP=8.210.139.66

ENV VPN_PORT=${VPN_PORT}
ENV VPN_PROTOCOL=${VPN_PROTOCOL}
ENV VPN_NETWORK=${VPN_NETWORK}
ENV VPN_NETMASK=${VPN_NETMASK}
ENV SERVER_IP=${SERVER_IP}

# Create server configuration template
RUN echo "port ${VPN_PORT}\n\
proto ${VPN_PROTOCOL}\n\
dev tun\n\
user nobody\n\
group nogroup\n\
persist-key\n\
persist-tun\n\
keepalive 10 120\n\
topology subnet\n\
server ${VPN_NETWORK} ${VPN_NETMASK}\n\
ifconfig-pool-persist ipp.txt\n\
push \"dhcp-option DNS 1.1.1.1\"\n\
push \"dhcp-option DNS 8.8.4.4\"\n\
push \"dhcp-option DNS 8.8.8.8\"\n\
push \"dhcp-option DNS 9.9.9.9\"\n\
push \"dhcp-option DNS 1.0.0.1\"\n\
push \"redirect-gateway def1 bypass-dhcp\"\n\
dh /etc/openvpn/config/dh2048.pem\n\
tls-crypt /etc/openvpn/config/tls-crypt.key\n\
crl-verify /etc/openvpn/config/crl.pem\n\
ca /etc/openvpn/config/ca.crt\n\
cert /etc/openvpn/config/server.crt\n\
key /etc/openvpn/config/server.key\n\
auth SHA256\n\
cipher AES-256-GCM\n\
data-ciphers AES-256-GCM:AES-128-GCM\n\
data-ciphers-fallback AES-256-GCM\n\
tls-server\n\
tls-version-min 1.2\n\
tls-cipher TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384:TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256\n\
status /var/log/openvpn/status.log\n\
log-append /var/log/openvpn/openvpn.log\n\
verb 3\n\
mute 20\n\
explicit-exit-notify 1" > /etc/openvpn/server.conf.template

# Create dynamic client config generation script
RUN echo '#!/bin/bash\n\
CLIENT_NAME=${1:-client_udp_1}\n\
SERVER_IP=${SERVER_IP:-8.210.139.66}\n\
VPN_PORT=${VPN_PORT:-82}\n\
VPN_PROTOCOL=${VPN_PROTOCOL:-udp}\n\
\n\
cat > /root/client-configs/${CLIENT_NAME}.ovpn << EOF\n\
client\n\
proto ${VPN_PROTOCOL}\n\
remote ${SERVER_IP} ${VPN_PORT}\n\
dev tun\n\
resolv-retry infinite\n\
nobind\n\
persist-key\n\
persist-tun\n\
remote-cert-tls server\n\
verify-x509-name server name\n\
auth SHA256\n\
auth-nocache\n\
cipher AES-256-GCM\n\
data-ciphers AES-256-GCM:AES-128-GCM\n\
data-ciphers-fallback AES-256-GCM\n\
tls-client\n\
tls-version-min 1.2\n\
tls-cipher TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384:TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256\n\
ignore-unknown-option block-outside-dns\n\
setenv opt block-outside-dns\n\
verb 3\n\
<ca>\n\
$(cat /etc/openvpn/config/ca.crt)\n\
</ca>\n\
<cert>\n\
$(awk "/BEGIN CERTIFICATE/,/END CERTIFICATE/" /etc/openvpn/easy-rsa/pki/issued/${CLIENT_NAME}.crt)\n\
</cert>\n\
<key>\n\
$(cat /etc/openvpn/easy-rsa/pki/private/${CLIENT_NAME}.key)\n\
</key>\n\
<tls-crypt>\n\
$(cat /etc/openvpn/config/tls-crypt.key)\n\
</tls-crypt>\n\
EOF\n\
echo "Client config generated: /root/client-configs/${CLIENT_NAME}.ovpn"\n\
' > /usr/local/bin/generate-client-config && \
    chmod +x /usr/local/bin/generate-client-config

# Generate all client configs using the script
RUN for i in $(seq 1 ${NUM_CLIENTS:-100}); do \
        /usr/local/bin/generate-client-config "client_udp_${i}"; \
    done

# Create startup script with proper variable substitution
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
# Create tun device if it does not exist\n\
mkdir -p /dev/net\n\
if [ ! -c /dev/net/tun ]; then\n\
    mknod /dev/net/tun c 10 200\n\
fi\n\
\n\
# Enable IP forwarding\n\
echo 1 > /proc/sys/net/ipv4/ip_forward\n\
echo 1 > /proc/sys/net/ipv6/conf/all/forwarding\n\
\n\
# Generate final server config from template\n\
envsubst < /etc/openvpn/server.conf.template > /etc/openvpn/server.conf\n\
\n\
# Extract network from VPN_NETWORK and VPN_NETMASK for iptables\n\
VPN_SUBNET=$(ipcalc -n ${VPN_NETWORK}/${VPN_NETMASK} | cut -d= -f2)\n\
VPN_CIDR=$(ipcalc -n ${VPN_NETWORK}/${VPN_NETMASK} | cut -d= -f2 | cut -d. -f1-2).0.0/16\n\
\n\
# Setup iptables rules\n\
iptables -t nat -A POSTROUTING -s ${VPN_CIDR} -o eth0 -j MASQUERADE\n\
iptables -A INPUT -i tun0 -j ACCEPT\n\
iptables -A FORWARD -i eth0 -o tun0 -j ACCEPT\n\
iptables -A FORWARD -i tun0 -o eth0 -j ACCEPT\n\
iptables -A INPUT -i eth0 -p ${VPN_PROTOCOL} --dport ${VPN_PORT} -j ACCEPT\n\
\n\
# IPv6 rules\n\
ip6tables -t nat -A POSTROUTING -s fd42:42:42:42::/112 -o eth0 -j MASQUERADE\n\
ip6tables -A INPUT -i tun0 -j ACCEPT\n\
ip6tables -A FORWARD -i eth0 -o tun0 -j ACCEPT\n\
ip6tables -A FORWARD -i tun0 -o eth0 -j ACCEPT\n\
ip6tables -A INPUT -i eth0 -p ${VPN_PROTOCOL} --dport ${VPN_PORT} -j ACCEPT\n\
\n\
echo "Starting OpenVPN server on port ${VPN_PORT}/${VPN_PROTOCOL}..."\n\
echo "VPN network: ${VPN_NETWORK}/${VPN_NETMASK}"\n\
echo "Server IP: ${SERVER_IP}"\n\
\n\
# Start OpenVPN\n\
exec openvpn --config /etc/openvpn/server.conf\n\
' > /etc/openvpn/start.sh && \
    chmod +x /etc/openvpn/start.sh

# Install envsubst for template substitution
RUN apt-get update && apt-get install -y gettext-base ipcalc && rm -rf /var/lib/apt/lists/*

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD netstat -an | grep ${VPN_PORT} > /dev/null || exit 1

# Expose port (can be overridden with build args)
EXPOSE ${VPN_PORT}/${VPN_PROTOCOL}

# Add labels for better management
LABEL maintainer="your-email@example.com"
LABEL description="OpenVPN Server with configurable parameters"
LABEL version="1.0"

CMD ["/etc/openvpn/start.sh"]
