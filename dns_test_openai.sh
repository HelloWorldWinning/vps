#!/bin/bash

echo "Starting DNS server testing..."
echo "Testing 30 DNS servers for both ping and resolution times..."

# Check if the script is run as root (required to write to /etc/resolv.conf)
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root to write to /etc/resolv.conf"
   exit 1
fi

# List of top 30 famous DNS servers
dns_servers=(
8.8.8.8             # Google
8.8.4.4             # Google
1.1.1.1             # Cloudflare
1.0.0.1             # Cloudflare
208.67.222.222      # OpenDNS
208.67.220.220      # OpenDNS
9.9.9.9             # Quad9
149.112.112.112     # Quad9
4.2.2.1             # Level3
4.2.2.2             # Level3
8.26.56.26          # Comodo Secure DNS
8.20.247.20         # Comodo Secure DNS
64.6.64.6           # Verisign
64.6.65.6           # Verisign
77.88.8.8           # Yandex DNS
77.88.8.1           # Yandex DNS
216.146.35.35       # DynDNS
216.146.36.36       # DynDNS
84.200.69.80        # DNS.WATCH
84.200.70.40        # DNS.WATCH
185.228.168.9       # CleanBrowsing
185.228.169.9       # CleanBrowsing
198.101.242.72      # Alternate DNS
23.253.163.53       # Alternate DNS
176.103.130.130     # AdGuard DNS
176.103.130.131     # AdGuard DNS
91.239.100.100      # UncensoredDNS
89.233.43.71        # UncensoredDNS
37.235.1.174        # FreeDNS
37.235.1.177        # FreeDNS
)

# Domain to query (using a less common domain to reduce caching effects)
domain="time.cloudflare.com"

# Temporary file to store results
tmpfile=$(mktemp)

# Counter for display
counter=1

# For each DNS server, test resolving speed and ping time
for dns in "${dns_servers[@]}"; do
    echo "Testing $dns ($counter/30)..."
    counter=$((counter + 1))

    # Use dig to query the domain using the DNS server and capture resolution time
    output=$(dig @$dns $domain +stats +tries=1 +timeout=2 2>/dev/null)
    query_time=$(echo "$output" | grep "Query time" | awk '{print $4}')

    if [ -z "$query_time" ]; then
        query_time=9999
    fi

    # Use ping to check response latency
    ping_time=$(ping -c 1 -W 1 $dns | grep 'time=' | awk -F'time=' '{print $2}' | awk '{print int($1)}')
    if [ -z "$ping_time" ]; then
        ping_time=9999
    fi

    # Calculate total time (using option 1: ping_time/2 + resolving_time)
    total_time=$((ping_time / 2 + query_time))

    # Log the result to the temp file
    echo "$dns $total_time $query_time $ping_time" >> "$tmpfile"

    # Display the result in the specified format
    echo "Ping: ${ping_time}ms Resolution: ${query_time}ms"
done

# Sort the results based on total time in ascending order and display the top 15
sorted=$(sort -k2 -n "$tmpfile")
top15=$(echo "$sorted" | head -n 15)

echo -e "\nTop 15 Fastest DNS Servers (Total Time = Ping/2 + Resolution Time):"
echo "============================================================="
echo "DNS Server         Total Time    Resolution Time    Ping Time"
echo "============================================================="
echo "$top15" | awk '{printf "%-17s %8sms %16sms %13sms\n", $1, $2, $3, $4}'

# Clean up temporary file
rm "$tmpfile"

