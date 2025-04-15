#!/bin/bash
DIR="/root/port16_py_jupyter_D"
mkdir -p $DIR
cd $DIR

cat > docker-compose.yml << 'EOF'
services:
  port16_py_jupyter_instance:
    container_name: port16_py_jupyter_container
    image: oklove/port16_py_jupyter
    environment:
      - TZ=Asia/Shanghai
    restart: always
    ports:
      - "16:16"
    volumes:
      - /:/Host
EOF

docker compose  down
docker compose  pull
docker compose up -d
sleep 3

STATUS=$(docker ps -a --format '{{.Status}}' --filter name=port16_py_jupyter_container)
RUNNING=$(echo $STATUS | grep -c "Up")

echo "Container status: $STATUS"
if [ $RUNNING -eq 1 ]; then
    echo "Service running successfully on port 16"
    docker ps -a | grep port16_py_jupyter_container
else
    echo "Service failed to start"
    docker logs port16_py_jupyter_container
fi
