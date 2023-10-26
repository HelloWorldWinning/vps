# Clear the screen
clear

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
  echo "Last login: $ip  $cur_date"
fi




# Display uptime
echo -n "Uptime    : "
uptime -p | sed 's/up //'

# Display CPU information
CPU_MODEL=$(lscpu | grep "Model name:" | sed 's/Model name: *//' | awk '{printf "%s, ", $0}' | sed 's/, $/\n/')
CPU_CORES=$(lscpu | grep "^CPU(s):" | awk '{print $2}')
L1_CACHE=$(lscpu | grep "L1d cache:" | awk '{print $3 " " $4}')
L2_CACHE=$(lscpu | grep "L2 cache:" | awk '{print $3 " " $4}')
L3_CACHE=$(lscpu | grep "L3 cache:" | awk '{print $3 " " $4}')

echo "CPU Model : $CPU_MODEL"
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
free -h | awk '/Swap:/ {print $2 " (" $3 " used, "    $4 " free)"}' | sed 's/Mi/M/g'

# Display Memory Information
echo -n "RAM       : "
free -h | awk '/Mem:/ {print $2 " (" $3 " used, "    $4 " free)"}' | sed 's/Gi/G/g' | sed 's/Mi/M/g'
#echo -n "Mem       : "
#free -h | awk '/Mem:/ {print $2 " (" $3 " used, " $4 " free)"}' | sed 's/Gi/G/g' | sed 's/Mi/M/g'

# Display Disk Information
echo -n "Disk      : "
df -h --exclude-type overlay --exclude-type tmpfs --total | awk '/total/ {print $2 " (" $3 " used, "    $4" free)"}' | sed 's/G/G /g'

#df -h --total | awk '/total/ {print $2 " (" $3 " used, " $4 " free)"}' | sed 's/G/G /g'

echo "----------------------------------------------------------------------"

##########
