FROM debian:bookworm-slim

# Install required packages
RUN apt-get update && apt-get install -y \
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

# Install easy-rsa
RUN wget -O /tmp/easy-rsa.tgz https://github.com/OpenVPN/easy-rsa/releases/download/v3.1.2/EasyRSA-3.1.2.tgz \
    && mkdir -p /etc/openvpn/easy-rsa \
    && tar xzf /tmp/easy-rsa.tgz --strip-components=1 --no-same-owner --directory /etc/openvpn/easy-rsa \
    && rm -f /tmp/easy-rsa.tgz

# Setup OpenVPN configuration
WORKDIR /etc/openvpn/easy-rsa

# Create vars file first
RUN echo "set_var EASYRSA_ALGO ec\n\
set_var EASYRSA_CURVE prime256v1\n\
set_var EASYRSA_CA_EXPIRE 3650\n\
set_var EASYRSA_CERT_EXPIRE 3650\n\
set_var EASYRSA_CRL_DAYS 3650" > vars

# Initialize PKI and create certificates
RUN ./easyrsa init-pki && \
    ./easyrsa --batch build-ca nopass && \
    ./easyrsa --batch build-server-full server nopass && \
    ./easyrsa gen-crl && \
    # Generate keys for 100 clients
    for i in $(seq 1 1000); do \
        ./easyrsa --batch build-client-full "client_udp_${i}" nopass; \
    done

# Create necessary directories
RUN mkdir -p /var/log/openvpn /etc/sysctl.d /etc/openvpn/config

# Generate DH parameters
RUN openssl dhparam -out /etc/openvpn/config/dh2048.pem 2048

# Copy necessary files
RUN cp pki/ca.crt pki/private/ca.key pki/issued/server.crt pki/private/server.key pki/crl.pem /etc/openvpn/config/ && \
    chmod 644 /etc/openvpn/config/crl.pem

# Generate tls-crypt key
RUN openvpn --genkey secret /etc/openvpn/config/tls-crypt.key

# Create server configuration
RUN echo "port 82\n\
proto udp\n\
dev tun\n\
user nobody\n\
group nogroup\n\
persist-key\n\
persist-tun\n\
keepalive 10 120\n\
topology subnet\n\
server 10.8.0.0 255.255.255.0\n\
ifconfig-pool-persist ipp.txt\n\
push \"dhcp-option DNS 1.1.1.1\"\n\
push \"dhcp-option DNS 8.8.8.8\"\n\
push \"dhcp-option DNS 9.9.9.9\"\n\
push \"dhcp-option DNS 1.0.0.1\"\n\
push \"dhcp-option DNS 8.8.4.4\"\n\
push \"redirect-gateway def1 bypass-dhcp\"\n\
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

# Create client configs
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

# Create start script
RUN echo '#!/bin/sh\n\
mkdir -p /dev/net\n\
if [ ! -c /dev/net/tun ]; then\n\
    mknod /dev/net/tun c 10 200\n\
fi\n\
\n\
# Set ip forwarding directly\n\
echo 1 > /proc/sys/net/ipv4/ip_forward\n\
echo 1 > /proc/sys/net/ipv6/conf/all/forwarding\n\
\n\
/etc/openvpn/up.sh\n\
exec openvpn --config /etc/openvpn/server.conf' > /etc/openvpn/start.sh && \
    chmod +x /etc/openvpn/start.sh

# Add iptables rules script
RUN echo '#!/bin/sh\n\
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE\n\
iptables -A INPUT -i tun0 -j ACCEPT\n\
iptables -A FORWARD -i eth0 -o tun0 -j ACCEPT\n\
iptables -A FORWARD -i tun0 -o eth0 -j ACCEPT\n\
iptables -A INPUT -i eth0 -p udp --dport 82 -j ACCEPT\n\
ip6tables -t nat -A POSTROUTING -s fd42:42:42:42::/112 -o eth0 -j MASQUERADE\n\
ip6tables -A INPUT -i tun0 -j ACCEPT\n\
ip6tables -A FORWARD -i eth0 -o tun0 -j ACCEPT\n\
ip6tables -A FORWARD -i tun0 -o eth0 -j ACCEPT\n\
ip6tables -A INPUT -i eth0 -p udp --dport 82 -j ACCEPT' > /etc/openvpn/up.sh && \
    chmod +x /etc/openvpn/up.sh

EXPOSE 82/udp
CMD ["/etc/openvpn/start.sh"]






