# Complete system and network information test
docker run --rm oklove/openvpn-server_z_udp bash -c "
echo '=========================='
echo '🔍 SYSTEM INFORMATION'
echo '=========================='
echo '📋 Container OS:'
cat /etc/os-release | grep PRETTY_NAME

echo -e '\n📦 OpenVPN Version:'
openvpn --version | head -1

echo -e '\n🔐 OpenSSL Version:'
openssl version -a | head -3

echo -e '\n=========================='
echo '🌐 NETWORK CONFIGURATION'
echo '=========================='

echo -e '\n📡 IPv4 Interfaces:'
ip -4 addr show | grep -E '^[0-9]+:|inet ' | sed 's/^/  /'

echo -e '\n📡 IPv6 Interfaces:'
ip -6 addr show | grep -E '^[0-9]+:|inet6 ' | sed 's/^/  /'

echo -e '\n🔧 All Network Interfaces (brief):'
ip addr show | grep -E '^[0-9]+: |inet ' | sed 's/^/  /'

echo -e '\n📋 Network Interface Summary:'
printf '%-10s %-15s %-15s %-10s\n' 'Interface' 'IPv4' 'IPv6' 'State'
printf '%-10s %-15s %-15s %-10s\n' '---------' '----' '----' '-----'
ip link show | awk '/^[0-9]+:/ {
    interface = \$2; gsub(\":\", \"\", interface); gsub(\"@.*\", \"\", interface)
    state = \$9
    ipv4 = \"N/A\"
    ipv6 = \"N/A\"
    
    # Get IPv4
    cmd = \"ip -4 addr show \" interface \" 2>/dev/null | grep inet | head -1 | awk '{print \$2}' | cut -d/ -f1\"
    cmd | getline ipv4
    close(cmd)
    if (ipv4 == \"\") ipv4 = \"N/A\"
    
    # Get IPv6
    cmd = \"ip -6 addr show \" interface \" 2>/dev/null | grep 'inet6.*global' | head -1 | awk '{print \$2}' | cut -d/ -f1\"
    cmd | getline ipv6
    close(cmd)
    if (ipv6 == \"\") ipv6 = \"N/A\"
    
    printf \"%-10s %-15s %-15s %-10s\n\", interface, ipv4, ipv6, state
}'

echo -e '\n=========================='
echo '⚙️  OPENVPN CONFIGURATION'
echo '=========================='

echo -e '\n🔧 Server Network Config:'
grep -E '^(server|port|proto|dev)' /etc/openvpn/server.conf | sed 's/^/  /'

echo -e '\n🛡️  Security Settings:'
grep -E '^(cipher|auth|tls-)' /etc/openvpn/server.conf | sed 's/^/  /'

echo -e '\n📁 Certificate Files:'
ls -la /etc/openvpn/config/*.{crt,key,pem} 2>/dev/null | awk '{print \"  \" \$9 \" (\" \$5 \" bytes, \" \$6 \" \" \$7 \" \" \$8 \")\"}' || echo '  No certificate files found'

echo -e '\n=========================='
echo '🔒 IPTABLES & ROUTING'
echo '=========================='

echo -e '\n🔥 IPv4 NAT Rules:'
iptables -t nat -L POSTROUTING -n | grep -E 'MASQUERADE|source' | sed 's/^/  /'

echo -e '\n🔥 IPv6 NAT Rules:'
ip6tables -t nat -L POSTROUTING -n 2>/dev/null | grep -E 'MASQUERADE|source' | sed 's/^/  /' || echo '  IPv6 NAT not configured'

echo -e '\n🔥 Firewall INPUT Rules (VPN related):'
iptables -L INPUT -n | grep -E ':82|:1194|tun|ACCEPT' | sed 's/^/  /'

echo -e '\n🔥 Firewall FORWARD Rules:'
iptables -L FORWARD -n | grep -E 'tun|ACCEPT' | sed 's/^/  /'

echo -e '\n📊 IP Forwarding Status:'
echo '  IPv4 forwarding: ' \$(cat /proc/sys/net/ipv4/ip_forward)
echo '  IPv6 forwarding: ' \$(cat /proc/sys/net/ipv6/conf/all/forwarding)

echo -e '\n=========================='
echo '📊 SYSTEM RESOURCES'
echo '=========================='

echo -e '\n💾 Memory Usage:'
free -h | sed 's/^/  /'

echo -e '\n💽 Disk Usage:'
df -h | head -2 | sed 's/^/  /'

echo -e '\n⚡ Process Count:'
echo '  Total processes: ' \$(ps aux | wc -l)
echo '  OpenVPN processes: ' \$(ps aux | grep openvpn | grep -v grep | wc -l)

echo -e '\n=========================='
echo '🔍 DETAILED ANALYSIS'
echo '=========================='

echo -e '\n🔍 VPN Network vs NAT Rule Analysis:'
SERVER_NET=\$(grep '^server ' /etc/openvpn/server.conf | awk '{print \$2 \"/\" \$3}')
NAT_NET=\$(iptables -t nat -L POSTROUTING -n | grep MASQUERADE | awk '{print \$4}' | head -1)
echo \"  Server assigns IPs: \$SERVER_NET\"
echo \"  NAT rule covers: \$NAT_NET\"

if [[ \"\$SERVER_NET\" == *\"10.1.0.0\"* && \"\$NAT_NET\" == *\"10.1.0.0\"* ]]; then
    echo '  ✅ MATCH: VPN clients will have internet access'
elif [[ \"\$SERVER_NET\" == *\"10.8.0.0\"* && \"\$NAT_NET\" == *\"10.8.0.0\"* ]]; then
    echo '  ✅ MATCH: VPN clients will have internet access'
else
    echo '  ❌ MISMATCH: VPN clients may NOT have internet access!'
fi

echo -e '\n🔍 Certificate Validity:'
openssl x509 -in /etc/openvpn/config/server.crt -noout -dates 2>/dev/null | sed 's/^/  /' || echo '  Could not read server certificate'

echo -e '\n🔍 Easy-RSA Status:'
if [ -d /etc/openvpn/easy-rsa/pki ]; then
    echo '  PKI Directory: ✅ Present'
    echo '  CA Certificate: ' \$([ -f /etc/openvpn/easy-rsa/pki/ca.crt ] && echo '✅ Present' || echo '❌ Missing')
    echo '  Server Certificate: ' \$([ -f /etc/openvpn/easy-rsa/pki/issued/server.crt ] && echo '✅ Present' || echo '❌ Missing')
    echo '  Client Certificates: ' \$(ls /etc/openvpn/easy-rsa/pki/issued/client_udp_*.crt 2>/dev/null | wc -l) ' found'
else
    echo '  ❌ PKI Directory missing'
fi

echo -e '\n=========================='
echo '✅ TEST COMPLETED'
echo '=========================='
"
