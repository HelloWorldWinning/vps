#!/bin/bash
# Calculate total memory in bytes

sudo apt-get -y install dnsutils

rm -r /tmp/ray/
mkdir -p /tmp/ray 
chmod -R 777 /tmp/ray  

# Check if the 'ray' user exists; if not, create it
if ! id -u ray > /dev/null 2>&1; then
    sudo useradd ray
    echo "User 'ray' created."
fi

# Check if the 'users' group exists; if not, create it
if ! getent group users > /dev/null 2>&1; then
    sudo groupadd users
    echo "Group 'users' created."
fi

# Change ownership of /tmp/ray to user 'ray' and group 'users'
sudo chown -R ray:users /tmp/ray
echo "Ownership of /tmp/ray changed to user 'ray' and group 'users'."



clear




total_mem_bytes=$(awk '/MemTotal/ {print $2 * 1024}' /proc/meminfo)

shm_size_gb=$(awk -v mem=$total_mem_bytes 'BEGIN {printf "%.2f", mem * 0.9 / (1024^3)}')

# Calculate shm_size in bytes
shm_size_bytes=$(awk -v shm_gb=$shm_size_gb 'BEGIN {printf "%.0f", shm_gb * (1024^3)}')

# Calculate a percentage of shm_size for object-store-memory, e.g., 80% of shm_size
object_store_mem_bytes=$(awk -v shm_bytes=$shm_size_bytes 'BEGIN {printf "%.0f", shm_bytes * 0.5}')







services=(
  "https://api.ipify.org"
  "https://ipinfo.io/ip"
  "https://ifconfig.me"
)

# Function to get public IP using curl
get_public_ip() {
  for service in "${services[@]}"; do
    ip=$(curl -s "$service")
    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo $ip
      return 0
    fi
  done

  echo "Failed to get public IP." >&2
  return 1
}

public_ip=$(get_public_ip)


# Step 1: Ask user to choose between Ray worker or Ray head
#read -p "Do you want to install Ray worker or Ray head? [default worker: head/0] (default: worker): " choice
read -p "[default worker: head|0] (default: worker): " choice
if [[ $choice == "head" ]] || [[ $choice == "0" ]]; then
    node_type="ray-head"
    image="rayproject/ray-ml:latest"
  # image="rayproject/ray:latest"
  # RAY_ADDRESS="auto"
    RAY_ADDRESS="$public_ip:6379"
    command="ray start --head --object-store-memory=$object_store_mem_bytes  --port=6379 --object-manager-port=8076  --node-ip-address=$public_ip    --node-manager-port=8077 --dashboard-host=0.0.0.0 && tail -f /dev/null"
else
    node_type="ray-worker"
    rm -r /tmp/ray/
    image="rayproject/ray-ml:latest"
    read -p "Enter RAY_ADDRESS (default: auto detect): " RAY_ADDRESS
    if [ -z "$RAY_ADDRESS" ]; then
	comment=yes
        # Automatically detect the primary network interface's IP
        primary_interface=$(ip route | grep default | awk '{print $5}' | head -n 1)
        RAY_ADDRESS=$(ip addr show $primary_interface | grep 'inet\b' | awk '{print $2}' | cut -d/ -f1):6379
    else
        IP=""
        PORT="6379" # Default port
        if [[ "$RAY_ADDRESS" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:[0-9]+)?$ ]]; then
            # It's an IP address, optionally with a port
            IP=${RAY_ADDRESS%:*}  # Extract IP
            PORT=${RAY_ADDRESS#*:}  # Extract port if it exists
            [ "$IP" = "$PORT" ] && PORT="6379"  # If no port was found, use default
        else
            # Assume it's a domain, possibly with a port
            DOMAIN=${RAY_ADDRESS%:*}  # Extract domain
            PORT=${RAY_ADDRESS#*:}  # Extract port if it exists
            [ "$DOMAIN" = "$PORT" ] && PORT="6379"  # If no port was found, use default
            IP=$(dig +short $DOMAIN | head -n 1)  # Convert domain to IP
        fi
    
        if [ -n "$IP" ]; then
            RAY_ADDRESS="$IP:$PORT"
            echo "Converted RAY_ADDRESS to $RAY_ADDRESS"
        else
            echo "Invalid RAY_ADDRESS input."
        fi
    fi
    command="ray start --address=$RAY_ADDRESS   --object-store-memory=$object_store_mem_bytes    --node-ip-address=$public_ip  && tail -f /dev/null"
fi

if [ "$node_type" = "ray-worker" ]; then

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
#   restart: always
#   volumes:
#     - /tmp/ray:/tmp/ray
    network_mode: host
    restart: on-failure
    deploy:
      restart_policy:
        condition: on-failure
        delay: 3m
        max_attempts: 30
        window: 120s

EOF

else

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
#   restart: always
    volumes:
      - /tmp/ray:/tmp/ray
    network_mode: host
    restart: on-failure
    deploy:
      restart_policy:
        condition: on-failure
        delay: 3m
        max_attempts: 30
        window: 120s

EOF
fi
#if  [ "$comment" = "yes" ]; then
#    echo "    # network_mode: host" >> docker-compose.yml
#else
#    echo "    network_mode: host" >> docker-compose.yml
#fi

# Step 4: Start docker-compose
docker-compose up -d

# Step 5: Check running status
docker ps -a | grep $node_type

sleep  7
# Step 6: Show logs
docker logs $node_type

