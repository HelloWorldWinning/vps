#!/bin/bash
# Neat header function
print_header() {
    echo -e "\n\e[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
    echo -e "\e[1;36m                              $1\e[0m"
    echo -e "\e[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
}

# Clear screen first
clear

# Active Connections Section with aligned spacing
print_header "ACTIVE CONNECTIONS"
echo -e "\e[1;33mPROTO        LOCAL ADDRESS             REMOTE ADDRESS           STATE            PROGRAM PID\e[0m"
echo -e "\e[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
ss -tap | grep -v "LISTEN" | awk '
NR>1 {
    # Extract program name and PID from the last field
    if ($NF ~ /users/) {
        # Extract the program name and PID using regex
        match($NF, /"([^"]+)",pid=([0-9]+)/)
        if (RSTART > 0) {
            program = substr($NF, RSTART+1, RLENGTH-1)
            split(program, parts, ",")
            prog_name = parts[1]
            sub(/"/, "", prog_name)  # Remove remaining quote
            pid = parts[2]
            sub(/pid=/, "", pid)     # Remove "pid=" prefix
            
            # Format the program and PID in a clean way
            prog_pid = sprintf("%-8s %s", prog_name, pid)
        } else {
            prog_pid = "-"
        }
    } else {
        prog_pid = "-"
    }
    
    # Print the formatted line
    printf "%-12s %-24s %-24s %-16s %s\n",
    $1, $4, $5, $2, prog_pid
}'
echo -e "\e[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"







# UDP Listening Ports Section
print_header "UDP LISTENING PORTS"
echo -e "\e[1;33mPROTO        PORT                          PID/PROGRAM\e[0m"
echo -e "\e[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
ss -ulnp | awk '
BEGIN {
    red="\033[1;31m"
    reset="\033[0m"
}
NR>1 {
    split($4, a, ":")
    addr = a[1]
    if (length(a) > 2) {
        addr = ""
        for (i=1; i<length(a); i++) {
            if (i > 1) addr = addr ":"
            addr = addr a[i]
        }
        port = a[length(a)]
    } else {
        addr = a[1]
        port = a[2]
    }
    
    if (addr == "0.0.0.0" || addr == "[::]" || addr == "*") {
        colored_port = sprintf("%s:%s%s%s", addr, red, port, reset)
    } else {
        colored_port = $4
    }
    printf "%-12s %-30s %-20s\n",
    $1, colored_port, $NF
}'
echo -e "\e[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"




# TCP Listening Ports Section with aligned columns and colored ports
print_header "TCP LISTENING PORTS"
echo -e "\e[1;33mSTATE        ADDRESS:PORT              USER           PID            PROGRAM\e[0m"
echo -e "\e[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
ss -tlnp | awk '
BEGIN {
    red="\033[1;31m"
    reset="\033[0m"
}
NR>1 {
    # Extract address and port
    split($4, a, ":")
    addr = a[1]
    if (length(a) > 2) {
        addr = ""
        for (i=1; i<length(a); i++) {
            if (i > 1) addr = addr ":"
            addr = addr a[i]
        }
        port = a[length(a)]
    } else {
        addr = a[1]
        port = a[2]
    }
    
    # Format address:port with colors for non-localhost addresses
    if (addr == "0.0.0.0" || addr == "[::]" || addr == "*") {
        # Calculate the padding needed for colored text
        base_text = sprintf("%s:%s", addr, port)
        padding = 24 - length(base_text)  # 24 is the desired field width
        colored_port = sprintf("%s:%s%s%s%*s", addr, red, port, reset, padding, "")
    } else {
        colored_port = sprintf("%-24s", sprintf("%s:%s", addr, port))
    }
    
    # Extract PID and program name from the last field
    pid_prog = $NF
    if (pid_prog ~ /pid=[0-9]+/) {
        # Extract PID
        match(pid_prog, /pid=[0-9]+/)
        pid = substr(pid_prog, RSTART+4, RLENGTH-4)
        
        # Extract program name
        match(pid_prog, /"([^"]+)"/)
        prog = substr(pid_prog, RSTART+1, RLENGTH-2)
        
        # Get user for the PID
        cmd = "ps -o user= -p " pid
        cmd | getline user
        close(cmd)
        
        # Print line with proper spacing
        priority = (addr == "127.0.0.1") ? 1 : 2
        printf "%d %-12s %-24s %-14s %-14s %-s\n",
        priority, $1, colored_port, user, pid, prog
    } else {
        printf "%d %-12s %-24s %-14s %-14s %-s\n",
        2, $1, colored_port, "-", "-", "-"
    }
}' | sort -k1,1 -k3,3 | sed 's/^.\{1\}//'
echo -e "\e[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"

# Process Details Section
print_header "PROCESS DETAILS"
echo -e "\e[1;33mPID      USER     PORT     PROTO             CMD\e[0m"
echo -e "\e[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
pids=$(ss -tap | grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -u | tr '\n' ',')
if [ -n "$pids" ]; then
    ps -o pid,user,cmd -p ${pids%,} 2>/dev/null | grep -v "PID USER" | while read pid user cmd; do
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
                print substr(ports, 1, length(ports)-2)
            } else {
                print "-"
            }
        }')
        
        if [ "$port_info" != "-" ]; then
            colored_ports=$(echo "$port_info" | sed 's/\([0-9]*\) \([A-Z]*\)/\\e[1;91m\1\\e[0m \\e[1;36m\2\\e[0m/g')
            printf -v formatted_line "%-8s %-8s %-30s %s\n" "$pid" "$user" "$colored_ports" "$cmd"
        else
            printf -v formatted_line "%-8s %-8s %-30s %s\n" "$pid" "$user" "-" "$cmd"
        fi
        
        echo -e "$formatted_line"
    done
fi
echo -e "\e[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"

