# Clear the screen
clear
printf "\033c"

# Display separator
echo "----------------------------------------------------------------------"

# Display last login without 'from still'
#last -n 1 -i | awk '{print "Last login: " $3 " " $4 " " $5 " " $6 " " $7}'
# If this is an SSH connection
if [ -n "$SSH_CLIENT" ]; then
  # Parse SSH_CLIENT for the IP address
  ip=$(echo $SSH_CLIENT | awk '{print $1}')

  # Get current date info
  cur_date=$(date "+%Y-%m-%d %H:%M:%S %a")

  # Display modified 'Last login' line
  echo "Last login: from $ip $cur_date"
fi

#!/bin/bash

# Get the total uptime in seconds
total_seconds=$(cat /proc/uptime | awk '{print $1}' | cut -d. -f1)

# Define time constants
seconds_per_minute=60
seconds_per_hour=$((60 * seconds_per_minute))
seconds_per_day=$((24 * seconds_per_hour))
seconds_per_month=$((30 * seconds_per_day)) # Approximation
seconds_per_year=$((12 * seconds_per_month)) # Approximation

# Calculate time components
years=$((total_seconds / seconds_per_year))
remaining_seconds=$((total_seconds % seconds_per_year))
months=$((remaining_seconds / seconds_per_month))
remaining_seconds=$((remaining_seconds % seconds_per_month))
days=$((remaining_seconds / seconds_per_day))
remaining_seconds=$((remaining_seconds % seconds_per_day))
hours=$((remaining_seconds / seconds_per_hour))
remaining_seconds=$((remaining_seconds % seconds_per_hour))
minutes=$((remaining_seconds / seconds_per_minute))

# Total days calculation
total_days=$((years * 12 * 30 + months * 30 + days)) # Approximation using 30 days per month

# Build the output string
output=""
if [ $years -gt 0 ]; then
  output="${years} years, "
fi

if [ $months -gt 0 ]; then
  output="${output}${months} months, "
fi

if [ $days -gt 0 ]; then
  output="${output}${days} days, "
fi

if [ $hours -gt 0 ]; then
  output="${output}${hours} hours, "
fi

if [ $minutes -gt 0 ]; then
  output="${output}${minutes} minutes"
fi

# Append total days to the output
output="${output} (up ${total_days} days)"

# Trim any trailing comma and whitespace, and output the result
#echo $output | sed 's/, $//' | xargs

# Display uptime
echo -n "Uptime    : "
echo $output | sed 's/, $//' | xargs
#uptime -p | sed 's/up //'

# Display CPU information
CPU_MODEL=$(echo "CPU Model : $(cat /proc/cpuinfo | awk -F: '/model name/ {print $2; exit}' | sed 's/^ *//')")
CPU_MHZ=$(echo "cpu MHz   : $(cat /proc/cpuinfo | awk -F: '/cpu MHz/ {print $2; exit}' | sed 's/^ *//')")

CPU_CORES=$(lscpu | grep "^CPU(s):" | awk '{print $2}')
L1_CACHE=$(lscpu | grep "L1d cache:" | awk '{print $3 " " $4}')
L2_CACHE=$(lscpu | grep "L2 cache:" | awk '{print $3 " " $4}')
L3_CACHE=$(lscpu | grep "L3 cache:" | awk '{print $3 " " $4}')

echo "$CPU_MODEL"
echo "$CPU_MHZ"
echo "CPU Cores : $CPU_CORES"
echo "CPU Cache : L1:$L1_CACHE / L2:$L2_CACHE / L3:$L3_CACHE"

# Display OS information
echo -n "OS        : "
lsb_release -d | awk -F':' '{print $2}' | sed 's/^[ \t]*//'

echo -n "Arch      : "
uname -m

echo -n "Kernel    : "
uname -r

echo -n "TCP CC    : "
sysctl -n net.ipv4.tcp_congestion_control

echo -n "Swap      : "
free -m | awk '/Swap:/ {printf "%5s | %5s | %5s M\n", $4, $3, $2}'

# Display Memory Information
echo -n "RAM       : "
free -m | awk '/Mem:/ {total=$2/1024; used=$3/1024; available=$7/1024; printf "%5.1f | %5.1f | %5.1f G\n", available, used, total}'

# Display Disk Information
echo -n "Disk      : "
df -BG --exclude-type overlay --exclude-type tmpfs --total | awk '/total/ {sub(/G/, "", $4); sub(/G/, "", $3); sub(/G/, "", $2); printf "%5s | %5s | %5s G\n", $4, $3, $2}'


echo -n "Public IP : "
curl -s -m 5 https://ipinfo.io/ip 2>/dev/null || \
curl -s -m 5 https://api.ipify.org 2>/dev/null || \
curl -s -m 5 https://icanhazip.com 2>/dev/null || \
echo "Unable to determine"


echo -e "\n----------------------------------------------------------------------"
