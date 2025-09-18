#!/bin/bash
DIR="/root/port1777_markdown_D"
mkdir -p $DIR
cd $DIR

cat > docker-compose.yml << 'EOF'

services:
  flask_app:
    image: oklove/port1777_md
    container_name: port1777_md_others
    ports:
      - "1777:1777"
    volumes:
      - /:/Host

    restart: always
    environment:
      # Pygments style used ONLY for Markdown code blocks
      # Examples: "manni" (default), "monokai", "friendly", "github-dark"
      - markdown_theme=manni
      - TZ=Asia/Shanghai

EOF

docker compose  down
docker compose down --rmi all
docker compose  pull
docker compose up -d
sleep 3

STATUS=$(docker ps -a --format '{{.Status}}' --filter name=port1777_md_others)
RUNNING=$(echo $STATUS | grep -c "Up")

echo "Container status: $STATUS"
if [ $RUNNING -eq 1 ]; then
    echo "Service running successfully on port 16"
    docker ps -a | grep port1777_md_others
else
    echo "Service failed to start"
    docker logs port1777_md_others
fi
