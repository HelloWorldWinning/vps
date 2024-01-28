#!/bin/bash
#top -bn1 | grep "Cpu(s)" | awk '{usage=$2+$4; printf "%.0f%%\n", usage}'
#cpu=$(top -bn1 | grep "Cpu(s)" | awk '{usage=$2+$4; printf "%.0f%%", usage}')
#ram=$(free | grep Mem | awk '{printf "%.0f%%", $3/$2 * 100}')
#echo "$cpu $ram"

#!/bin/bash
#cpu=$(top -bn1 | grep "Cpu(s)" | awk '{usage=$2+$4; printf "%.0f%%", usage}')
#ram=$(free | grep Mem | awk '{printf "%.0f%%", $3/$2 * 100}')
#disk=$(df -h | grep '/$' | awk '{print $5}')

cpu=$(top -bn1 | grep "Cpu(s)" | awk '{usage=$2+$4; printf "%.0f", usage}')
ram=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100}')
#disk=$(df -h | grep '/$' | awk '{print $5}')
disk=$(df -h | grep '/$' | awk '{print $4}')
echo "$cpu $ram $disk"
