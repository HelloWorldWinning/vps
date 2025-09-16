#!/bin/bash
DIR="/root/port7778_D"
mkdir -p $DIR
cd $DIR

wget -O docker-compose.yml https://raw.githubusercontent.com/HelloWorldWinning/vps/main/file_recv_ap2/docker-compose.yml

docker compose  down
docker compose down --rmi all
docker compose  pull
docker compose up -d
sleep 3

STATUS=$(docker ps -a --format '{{.Status}}' --filter name=file_recv_api)
RUNNING=$(echo $STATUS | grep -c "Up")

echo "Container status: $STATUS"
if [ $RUNNING -eq 1 ]; then
    echo "Service running successfully on port 16"
    docker ps -a | grep file_recv_api
else
    echo "Service failed to start"
    docker logs file_recv_api
fi
