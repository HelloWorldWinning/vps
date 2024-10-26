#!/bin/bash
# Neat header function
print_header() {
    echo -e "\n\e[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
    echo -e "\e[1;36m                  $1\e[0m"
    echo -e "\e[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
}
# Clear screen first
clear
print_header "ACTIVE CONNECTIONS"
ss -tap | grep -v "LISTEN" | awk 'NR>1 {
    printf "Protocol: %-5s\tLocal: %-20s\tRemote: %-20s\tState: %-10s\tPID/Program: %s\n",
    $1, $4, $5, $2, $NF
}'
print_header "UDP LISTENING PORTS"
ss -ulnp | awk '
BEGIN {
    red="\033[1;31m"
    reset="\033[0m"
}
NR>1 {
    # Extract address and port more carefully
    split($4, a, ":")
    # Handle IPv6 addresses properly
    addr = a[1]
    if (length(a) > 2) {
        # IPv6 address - join all parts except the last one (which is the port)
        addr = ""
        for (i=1; i<length(a); i++) {
            if (i > 1) addr = addr ":"
            addr = addr a[i]
        }
        port = a[length(a)]
    } else {
        # IPv4 address
        addr = a[1]
        port = a[2]
    }
    
    # Check if addr is 0.0.0.0, [::], or *
    if (addr == "0.0.0.0" || addr == "[::]" || addr == "*") {
        # Color only the port number
        colored_port = sprintf("%s:%s%s%s", addr, red, port, reset)
    } else {
        colored_port = $4
    }
    printf "Protocol: %-5s\tPort: %-25s\tPID/Program: %-20s\n",
    $1, colored_port, $NF
}'
print_header "TCP LISTENING PORTS"
ss -tlnp | awk '
BEGIN {
    red="\033[1;31m"
    reset="\033[0m"
}
NR>1 {
    # Extract address and port more carefully
    split($4, a, ":")
    # Handle IPv6 addresses properly
    addr = a[1]
    if (length(a) > 2) {
        # IPv6 address - join all parts except the last one (which is the port)
        addr = ""
        for (i=1; i<length(a); i++) {
            if (i > 1) addr = addr ":"
            addr = addr a[i]
        }
        port = a[length(a)]
    } else {
        # IPv4 address
        addr = a[1]
        port = a[2]
    }
    
    # Check if addr is 0.0.0.0, [::], or *
    if (addr == "0.0.0.0" || addr == "[::]" || addr == "*") {
        # Color only the port number
        colored_port = sprintf("%s:%s%s%s", addr, red, port, reset)
    } else {
        colored_port = $4
    }
    printf "Protocol: %-5s\tPort: %-25s\tPID/Program: %-20s\n",
    $1, colored_port, $NF
}'
print_header "PROCESS DETAILS"
echo -e "\e[1;33mPID      USER     PORT     PROTO             CMD\e[0m"
echo -e "\e[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
# Process the PIDs
pids=$(ss -tap | grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -u | tr '\n' ',')
if [ -n "$pids" ]; then
    ps -o pid,user,cmd -p ${pids%,} 2>/dev/null | grep -v "PID USER" | while read pid user cmd; do
        # Get port info for this PID
        port_info=$(ss -tulpn | grep "pid=$pid," | awk '{
            split($5,a,":")
            proto = toupper($1)
            printf "%s %s\n", a[length(a)], proto
        }' | sort -u | awk '
        {
            ports = ports sprintf("%-8s %-4s, ", $1, $2)
        } 
        END {
            if (length(ports) > 0) {
                # Remove trailing comma and space
                print substr(ports, 1, length(ports)-2)
            } else {
                print "-"
            }
        }')
        
        # If there are ports, color them
        if [ "$port_info" != "-" ]; then
            # Color ports in magenta and protocols in cyan
            colored_ports=$(echo "$port_info" | sed 's/\([0-9]*\) \([A-Z]*\)/\\e[1;35m\1\\e[0m \\e[1;36m\2\\e[0m/g')
            printf -v formatted_line "%-8s %-8s %-30s %s\n" "$pid" "$user" "$colored_ports" "$cmd"
        else
            printf -v formatted_line "%-8s %-8s %-30s %s\n" "$pid" "$user" "-" "$cmd"
        fi
        
        # Print the formatted line with color interpretation
        echo -e "$formatted_line"
    done
fi
# Add final line for clean look
echo -e "\e[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
