#!/bin/bash
# Calculate total memory in bytes
total_mem_bytes=$(awk '/MemTotal/ {print $2 * 1024}' /proc/meminfo)
# Calculate 50% of total memory for shm_size, convert to gigabytes
shm_size_gb=$(awk -v mem=$total_mem_bytes 'BEGIN {printf "%.2f", mem * 0.5 / (1024^3)}')




# Step 1: Ask user to choose between Ray worker or Ray head
read -p "Do you want to install Ray worker or Ray head? [default worker: head/0] (default: worker): " choice
if [[ $choice == "head" ]] || [[ $choice == "0" ]]; then
    node_type="ray-head"
    image="rayproject/ray:latest"
    RAY_ADDRESS="auto"
    command="ray start --head --port=6379 --object-manager-port=8076 --node-manager-port=8077 --dashboard-host=0.0.0.0 && tail -f /dev/null"
else
    node_type="ray-worker"
    image="rayproject/ray-ml:latest"
    read -p "Enter RAY_ADDRESS (default: auto detect): " RAY_ADDRESS
    if [ -z "$RAY_ADDRESS" ]; then
	comment=yes
        # Automatically detect the primary network interface's IP
        primary_interface=$(ip route | grep default | awk '{print $5}' | head -n 1)
        RAY_ADDRESS=$(ip addr show $primary_interface | grep 'inet\b' | awk '{print $2}' | cut -d/ -f1):6379
    elif [[ "$RAY_ADDRESS" != *:* ]]; then
        RAY_ADDRESS="$RAY_ADDRESS:6379"
    fi
    command="ray start --address=$RAY_ADDRESS && tail -f /dev/null"
fi

# Step 2: Create directories and set permissions
mkdir -p /tmp/ray /data/ray
chmod -R 777 /tmp/ray /data/ray

# Step 3: Generate docker-compose.yml
cat > docker-compose.yml <<EOF
version: '3.8'
services:
  $node_type:
    image: $image
    container_name: $node_type
    command: >
      /bin/bash -c "$command"
    shm_size: '${shm_size_gb}gb'
    environment:
      - RAY_ADDRESS=$RAY_ADDRESS
    restart: always
    volumes:
      - /data/ray:/ray
      - /tmp/ray:/tmp/ray
EOF

# Conditional network mode based on RAY_ADDRESS
#if [ -z "$RAY_ADDRESS" ] ; then
#f [ -z "$RAY_ADDRESS" ] || [ "$RAY_ADDRESS" == "auto" ]; then
if  [ "$comment" = "yes" ]; then
    echo "    # network_mode: host" >> docker-compose.yml
else
    echo "    network_mode: host" >> docker-compose.yml
fi

# Step 4: Start docker-compose
docker-compose up -d

# Step 5: Check running status
docker ps -a | grep $node_type

sleep  5
# Step 6: Show logs
docker logs $node_type

