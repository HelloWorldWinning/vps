#!/bin/bash
DIR="/root/port7778_D"
mkdir -p $DIR
cd $DIR

cat > docker-compose.yml << 'EOF'

services:
  file-recv-api:
#   build:
#     context: .          # path containing Dockerfile + src/ + Cargo.toml
#     dockerfile: Dockerfile
    image: oklove/file-recv-api:latest
    container_name: file_recv_api
    restart: unless-stopped
    environment:
      API_PASSWD: "kkb"
      TIMEZONE: "Asia/Shanghai"
      SAVING_PATH: "/saving_path"
      PORT: "7778"
      RUST_LOG: "info"
      # Optional: override allowed extensions (commas, spaces OK)
      FILE_TYPES_EXTENSION: "conf, pdf, doc, docx, xls, xlsx, ppt, pptx, txt, md, csv, json, xml, html, css, js, ts, py, java, c, cpp, cs, go, rs, rb, php, sh, bat, ps1, sql, yaml, yml, ini, log, jpg, jpeg, png, gif, bmp, svg, webp, tiff, ico, mp3, wav, aac, flac, ogg, m4a, mp4, mov, mkv, avi, webm, wmv, zip, rar, 7z, tar, gz, bz2"
    ports:
      - "7778:7778"
    volumes:
      - /data/files_recv_d:/saving_path
    healthcheck:               # (compose-level mirror of image healthcheck is fine)
      test: ["CMD", "curl", "-fsS", "http://127.0.0.1:7778/healthz"]
      interval: 15s
      timeout: 3s
      retries: 5

EOF

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
