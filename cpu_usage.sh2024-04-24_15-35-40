#!/bin/bash
#cpu=$(top -bn1 | grep "Cpu(s)" | awk '{usage=$2+$4; printf "%.0f%%", usage}')
#cpu=$(top -bn1 | grep "Cpu(s)" | awk '{idle=$8; printf "%.0f%%", idle}')


#!/bin/bash

# Read the first line from /proc/stat
read -r cpu user nice system idle iowait irq softirq steal _ < /proc/stat

# Calculate total and idle times
total_time=$((user + nice + system + idle + iowait + irq + softirq + steal))
idle_time=$((idle + iowait))

# Calculate idle CPU percentage
idle_cpu=$((100 * (idle_time) / total_time))

#echo "${idle_cpu}%"




ram=$(free -h | grep Mem | awk '{sub("i", "", $7); print $7}')
disk=$(df -h | grep '/$' | awk '{print $4}')

echo "$idle_cpu% $ram $disk"

