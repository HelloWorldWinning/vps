#!/bin/bash
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
)

# Domain to query (using a less common domain to reduce caching effects)
domain="time.cloudflare.com"

# Temporary file to store results
tmpfile=$(mktemp)

# Total number of servers to test
total_servers=${#dns_servers[@]}
current_server=0

echo "Starting DNS server testing..."
echo "Testing $total_servers DNS servers for both ping and resolution times..."

# For each DNS server, test resolving speed and ping time
for dns in "${dns_servers[@]}"; do
    ((current_server++))
    echo -n "Testing $dns ($current_server/$total_servers)... "
    
    # Get ping time (average of 3 pings with 1 second timeout)
    ping_output=$(ping -c 3 -W 1 $dns 2>/dev/null)
    if [ $? -eq 0 ]; then
        ping_time=$(echo "$ping_output" | tail -1 | awk -F '/' '{print $5}')
        echo -n "Ping: ${ping_time}ms "
    else
        ping_time=9999
        echo -n "Ping: Failed "
    fi

    # Use dig to query the domain using the DNS server
    output=$(dig @$dns $domain +stats +tries=1 +timeout=2 2>/dev/null)
    # Extract the query time
    query_time=$(echo "$output" | grep "Query time" | awk '{print $4}')
    
    if [ -z "$query_time" ]; then
        query_time=9999
        echo "Resolution: Failed"
    else
        echo "Resolution: ${query_time}ms"
    fi

    # Calculate total_time using option 1: total_time = ping_time/2 + resolving_time
    # Using awk for floating point arithmetic instead of bc
    if [ "$ping_time" != "9999" ] && [ "$query_time" != "9999" ]; then
        total_time=$(awk "BEGIN {printf \"%.1f\", $ping_time/2 + $query_time}")
    else
        total_time=9999
    fi

    # Output the DNS server and its times to the temp file
    echo "$dns $total_time $query_time $ping_time" >> "$tmpfile"
done

# Sort the results based on total time in ascending order
sorted=$(sort -k2 -n "$tmpfile")

# Get the top 5 fastest DNS servers and write to /etc/resolv.conf
top5=$(echo "$sorted" | head -n 5)

# Backup the current /etc/resolv.conf
cp /etc/resolv.conf /etc/resolv.conf.backup

# Output the top 5 DNS servers to /etc/resolv.conf
{
    echo "# Generated by script on $(date)"
    echo "$top5" | awk '{print "nameserver "$1}'
} > /etc/resolv.conf

# Display top 15 results
echo -e "\nTop 15 Fastest DNS Servers (Total Time = Ping/2 + Resolution Time):"
echo "============================================================="
echo "DNS Server         Total Time    Resolution Time    Ping Time"
echo "============================================================="
echo "$sorted" | head -n 15 | while read -r line; do
    dns=$(echo "$line" | awk '{print $1}')
    total=$(echo "$line" | awk '{print $2}')
    resolution=$(echo "$line" | awk '{print $3}')
    ping=$(echo "$line" | awk '{print $4}')
    printf "%-16s %8.1fms %12sms %12sms\n" "$dns" "$total" "$resolution" "$ping"
done

# Clean up temporary file
rm "$tmpfile"

echo -e "\nUpdated /etc/resolv.conf with the top 5 fastest DNS servers."