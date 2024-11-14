#!/bin/bash

echo "=== Analyzing PHP-FPM Processes ==="

# List all PHP-FPM master processes
echo -e "\nPHP-FPM Master Processes:"
ps aux | grep "php-fpm: master" | grep -v grep

# List all PHP-FPM pool processes
echo -e "\nPHP-FPM Pool Processes:"
ps aux | grep "php-fpm: pool" | grep -v grep

# Get Docker container info for each PHP-FPM process
echo -e "\nDocker Container Information:"
for pid in $(pgrep -f "php-fpm"); do
    echo -e "\nProcess ID: $pid"
    echo "Docker Container ID: $(cat /proc/$pid/cgroup 2>/dev/null | grep docker | cut -d'/' -f3 | head -1)"
    echo "Command: $(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ')"
    echo "Working Directory: $(readlink /proc/$pid/cwd 2>/dev/null)"
    echo "Environment:"
    cat /proc/$pid/environ 2>/dev/null | tr '\0' '\n' | grep -E 'DOCKER|CONTAINER|PHP'
done

# Check for suspicious open files
echo -e "\nOpen Files for PHP-FPM Processes:"
for pid in $(pgrep -f "php-fpm"); do
    echo -e "\nProcess ID: $pid"
    lsof -p $pid 2>/dev/null | grep -E '/tmp|/var/tmp'
done

# List Docker containers running PHP-FPM
echo -e "\nDocker Containers Running PHP-FPM:"
docker ps | grep -i php-fpm

# Check Docker container logs
echo -e "\nRecent Docker Container Logs:"
for container_id in $(docker ps -q); do
    echo -e "\nContainer ID: $container_id"
    docker logs --tail 50 $container_id 2>&1 | grep -E 'error|warning|critical|kdevtmpfsi'
done
