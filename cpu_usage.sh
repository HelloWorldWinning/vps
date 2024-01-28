#!/bin/bash
cpu=$(top -bn1 | grep "Cpu(s)" | awk '{usage=$2+$4; printf "%.0f%%", usage}')
ram=$(free -h | grep Mem | awk '{sub("i", "", $7); print $7}')
disk=$(df -h | grep '/$' | awk '{print $4}')

echo "$cpu $ram $disk"

